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
  Function(int lines, CubeType tier, int damageHp, int diamondLines, int opponentHp)? onIncomingAttack;
  Function(String userId, String teamId)? onPlayerKnockout;
  Function(String winnerTeamId)? onMatchEnd;
  Function(bool isOpponentConnected)? onOpponentConnectionChanged;
  /// Distinto de onMatchEnd: se dispara solo cuando el rival se declara
  /// abandonado por timeout real (no por fin de partida jugado), para poder
  /// aplicar la penalización de ELO contra su user_id real.
  Function(String opponentUserId)? onOpponentTimeout;

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
  });

  bool _checkIsOpponent(dynamic p) {
    if (p == null) return false;
    try {
      if (p is Map) {
        final isOpp = p['user_id'] != null && p['user_id'] != currentUserId;
        if (isOpp) opponentUserId = p['user_id'] as String;
        return isOpp;
      }
      final dynamic payload = p.payload;
      if (payload is Map) {
        final isOpp = payload['user_id'] != null && payload['user_id'] != currentUserId;
        if (isOpp) opponentUserId = payload['user_id'] as String;
        return isOpp;
      }
    } catch (_) {}
    return false;
  }

  void connect() {
    final client = SupabaseConfig.client;
    _channel = client.channel('match:$matchId');

    _channel.onPresenceSync((_) {
      bool opponentFound = false;
      try {
        final dynamic state = _channel.presenceState();
        if (state is Map) {
          state.forEach((key, val) {
            if (val is Iterable) {
              for (final dynamic item in val) {
                if (_checkIsOpponent(item)) {
                  opponentFound = true;
                  break;
                }
              }
            } else if (_checkIsOpponent(val)) {
              opponentFound = true;
            }
          });
        } else if (state is Iterable) {
          for (final dynamic item in state) {
            if (_checkIsOpponent(item)) {
              opponentFound = true;
              break;
            }
            try {
              final dynamic payloads = item.payloads;
              if (payloads is Iterable) {
                for (final dynamic p in payloads) {
                  if (_checkIsOpponent(p)) {
                    opponentFound = true;
                    break;
                  }
                }
              }
            } catch (_) {}
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
          for (final dynamic item in newPresences) {
            if (_checkIsOpponent(item)) {
              _cancelReconnectTimer();
              onOpponentConnectionChanged?.call(true);
              break;
            }
          }
        }
      } catch (_) {}
    });

    _channel.onPresenceLeave((dynamic payload) {
      try {
        final dynamic leftPresences = payload.leftPresences;
        if (leftPresences is Iterable && leftPresences.isNotEmpty) {
          for (final dynamic item in leftPresences) {
            if (_checkIsOpponent(item)) {
              _startReconnectTimer();
              onOpponentConnectionChanged?.call(false);
              break;
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
        final senderTeamId = payload['sender_team_id'] as String?;
        if (senderTeamId != myTeamId) {
          _cancelReconnectTimer();
          onOpponentConnectionChanged?.call(true);
        }
        final lines = payload['lines'] as int? ?? 0;
        final damageHp = payload['damage_hp'] as int? ?? (lines > 0 ? 10 : 0);
        final diamondLines = payload['diamond_lines'] as int? ?? 0;
        final opponentHp = payload['sender_hp'] as int? ?? 100;
        final tierStr = payload['tier'] as String? ?? 'none';

        // Si el ataque viene del rival (no es mi propio eco), recibir el ataque!
        if (senderTeamId != myTeamId && (lines > 0 || damageHp > 0 || diamondLines > 0)) {
          final tier = tierStr == 'gold'
              ? CubeType.gold
              : (tierStr == 'silver' ? CubeType.silver : (tierStr == 'diamond' ? CubeType.diamond : CubeType.none));
          onIncomingAttack?.call(lines, tier, damageHp, diamondLines, opponentHp);
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
    reconnectSecondsRemaining = 120; // 2 minutos de tolerancia máxima para evitar cortes prematuros

    _reconnectTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      reconnectSecondsRemaining--;
      if (reconnectSecondsRemaining <= 0) {
        timer.cancel();
        // Solo finalizar por abandono prolongado de 2 minutos sin conexión
        onMatchEnd?.call(myTeamId);
        if (opponentUserId != null) {
          onOpponentTimeout?.call(opponentUserId!);
        }
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
    int damageHp = 0,
    int diamondLines = 0,
    int senderHp = 100,
  }) async {
    if (lines <= 0 && damageHp <= 0 && diamondLines <= 0) return;
    await _channel.sendBroadcastMessage(
      event: 'team_attack',
      payload: {
        'sender_team_id': myTeamId,
        'target_team_id': opponentTeamId,
        'lines': lines,
        'tier': tier == CubeType.gold
            ? 'gold'
            : (tier == CubeType.silver ? 'silver' : (tier == CubeType.diamond ? 'diamond' : 'none')),
        'damage_hp': damageHp,
        'diamond_lines': diamondLines,
        'sender_hp': senderHp,
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
