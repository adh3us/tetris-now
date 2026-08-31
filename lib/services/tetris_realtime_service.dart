import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase_config.dart';
import '../game/tetris_types.dart';

class TetrisRealtimeService {
  final String matchId;
  final String myTeamId;
  final String opponentTeamId;
  final String currentUserId;
  late RealtimeChannel _channel;

  Function(String userId, String teamId)? onPlayerReady;
  Function()? onMatchStart;
  Function(int lines, CubeType tier)? onIncomingAttack;
  Function(String userId, String teamId)? onPlayerKnockout;
  Function(String winnerTeamId)? onMatchEnd;
  Function(bool isOpponentConnected)? onOpponentConnectionChanged;

  /// Se dispara si el rival no vuelve a conectarse dentro de los 30s
  /// del timeout de reconexión (abandono/desconexión) — distinto de
  /// [onMatchEnd], que es el cierre normal por partida jugada. Quien
  /// sigue conectado es quien reporta el resultado y dispara la
  /// penalización de ELO de quien abandonó (usa [opponentUserId]).
  Function()? onOpponentTimeout;

  /// user_id real del rival, capturado por presence apenas se conecta
  /// a la sala (necesario para tetris.penalizar_abandono, que trabaja
  /// con user_id, no con team_id).
  String? opponentUserId;

  Timer? _reconnectTimer;
  int reconnectSecondsRemaining = 30;

  TetrisRealtimeService({
    required this.matchId,
    required this.myTeamId,
    required this.opponentTeamId,
    required this.currentUserId,
    this.onPlayerReady,
    this.onMatchStart,
    this.onIncomingAttack,
    this.onPlayerKnockout,
    this.onMatchEnd,
    this.onOpponentConnectionChanged,
    this.onOpponentTimeout,
  });

  void connect() {
    final client = SupabaseConfig.client;
    _channel = client.channel('match:$matchId');

    _channel.onPresenceSync((_) {
      bool opponentFound = false;
      try {
        final dynamic state = _channel.presenceState();
        if (state is Iterable) {
          for (final dynamic item in state) {
            final dynamic payloads = item.payloads;
            if (payloads is Iterable) {
              for (final dynamic p in payloads) {
                if (p is Map && p['user_id'] != currentUserId) {
                  opponentFound = true;
                  opponentUserId = p['user_id'] as String?;
                  break;
                }
              }
            }
          }
        }
      } catch (_) {}

      onOpponentConnectionChanged?.call(opponentFound);
      _handlePresenceStatus(opponentFound);
    });

    _channel.onPresenceJoin((dynamic payload) {
      try {
        final dynamic newPresences = payload.newPresences;
        if (newPresences is Iterable && newPresences.isNotEmpty) {
          final dynamic first = newPresences.first;
          final dynamic payloads = first.payloads;
          if (payloads is Iterable && payloads.isNotEmpty) {
            final dynamic p = payloads.first;
            if (p is Map && p['user_id'] != currentUserId) {
              opponentUserId = p['user_id'] as String?;
              _cancelReconnectTimer();
              onOpponentConnectionChanged?.call(true);
            }
          }
        }
      } catch (_) {}
    });

    _channel.onPresenceLeave((dynamic payload) {
      try {
        final dynamic leftPresences = payload.leftPresences;
        if (leftPresences is Iterable && leftPresences.isNotEmpty) {
          final dynamic first = leftPresences.first;
          final dynamic payloads = first.payloads;
          if (payloads is Iterable && payloads.isNotEmpty) {
            final dynamic p = payloads.first;
            if (p is Map && p['user_id'] != currentUserId) {
              _startReconnectTimer();
              onOpponentConnectionChanged?.call(false);
            }
          }
        }
      } catch (_) {}
    });

    _channel.onBroadcast(
      event: 'player_ready',
      callback: (payload) {
        final userId = payload['user_id'] as String;
        final teamId = payload['team_id'] as String;
        onPlayerReady?.call(userId, teamId);
      },
    );

    _channel.onBroadcast(
      event: 'match_start',
      callback: (payload) {
        onMatchStart?.call();
      },
    );

    _channel.onBroadcast(
      event: 'team_attack',
      callback: (payload) {
        final targetTeamId = payload['target_team_id'] as String;
        final lines = payload['lines'] as int;
        final tierStr = payload['tier'] as String? ?? 'none';

        if (targetTeamId == myTeamId) {
          final tier = tierStr == 'gold'
              ? CubeType.gold
              : (tierStr == 'silver' ? CubeType.silver : CubeType.none);
          onIncomingAttack?.call(lines, tier);
        }
      },
    );

    _channel.onBroadcast(
      event: 'player_knockout',
      callback: (payload) {
        final userId = payload['user_id'] as String;
        final teamId = payload['team_id'] as String;
        onPlayerKnockout?.call(userId, teamId);
      },
    );

    _channel.onBroadcast(
      event: 'match_end',
      callback: (payload) {
        final winnerTeamId = payload['winner_team_id'] as String;
        onMatchEnd?.call(winnerTeamId);
      },
    );

    _channel.subscribe((status, [error]) async {
      if (status == RealtimeSubscribeStatus.subscribed) {
        await _channel.track({
          'user_id': currentUserId,
          'team_id': myTeamId,
          'online_at': DateTime.now().toIso8601String(),
        });
      }
    });
  }

  void _handlePresenceStatus(bool isOpponentOnline) {
    if (!isOpponentOnline) {
      _startReconnectTimer();
    } else {
      _cancelReconnectTimer();
    }
  }

  void _startReconnectTimer() {
    if (_reconnectTimer != null && _reconnectTimer!.isActive) return;
    reconnectSecondsRemaining = 30;

    _reconnectTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      reconnectSecondsRemaining--;
      if (reconnectSecondsRemaining <= 0) {
        timer.cancel();
        onOpponentTimeout?.call();
      }
    });
  }

  void _cancelReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    reconnectSecondsRemaining = 30;
  }

  Future<void> sendReady() async {
    await _channel.sendBroadcastMessage(
      event: 'player_ready',
      payload: {
        'user_id': currentUserId,
        'team_id': myTeamId,
      },
    );
  }

  Future<void> sendMatchStart() async {
    await _channel.sendBroadcastMessage(
      event: 'match_start',
      payload: {},
    );
  }

  Future<void> sendAttack({
    required int lines,
    CubeType tier = CubeType.none,
  }) async {
    if (lines <= 0) return;
    await _channel.sendBroadcastMessage(
      event: 'team_attack',
      payload: {
        'sender_team_id': myTeamId,
        'target_team_id': opponentTeamId,
        'lines': lines,
        'tier': tier == CubeType.gold ? 'gold' : (tier == CubeType.silver ? 'silver' : 'none'),
      },
    );
  }

  Future<void> sendKnockout() async {
    await _channel.sendBroadcastMessage(
      event: 'player_knockout',
      payload: {
        'user_id': currentUserId,
        'team_id': myTeamId,
      },
    );
  }

  Future<void> sendMatchEnd(String winnerTeamId) async {
    await _channel.sendBroadcastMessage(
      event: 'match_end',
      payload: {
        'winner_team_id': winnerTeamId,
      },
    );
  }

  void disconnect() {
    _cancelReconnectTimer();
    SupabaseConfig.client.removeChannel(_channel);
  }
}
