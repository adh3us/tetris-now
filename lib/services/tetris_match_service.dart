import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase_config.dart';

String generateUuidV4() {
  final rng = Random();
  String hex(int length) => List.generate(length, (_) => rng.nextInt(16).toRadixString(16)).join();
  final y = ['8', '9', 'a', 'b'][rng.nextInt(4)];
  return '${hex(8)}-${hex(4)}-4${hex(3)}-$y${hex(3)}-${hex(12)}';
}

class TetrisMatchModel {
  final String id;
  final String roomCode;
  final String roomName;
  final String? password;
  final bool isPrivate;
  final bool allowSpectators;
  final String? tournamentId;
  final int roundNumber;
  final String format; // '1v1'
  final String status; // 'pending', 'ready_check', 'in_progress', 'finished'
  final String team1Id;
  final String team2Id;
  final String? winnerTeamId;
  final int team1ArmorTier;
  final int team2ArmorTier;
  final int team1LinesSent;
  final int team2LinesSent;
  final DateTime createdAt;

  TetrisMatchModel({
    required this.id,
    this.roomCode = '90960',
    this.roomName = 'Duelo 1c1',
    this.password,
    this.isPrivate = false,
    this.allowSpectators = true,
    this.tournamentId,
    this.roundNumber = 1,
    required this.format,
    required this.status,
    required this.team1Id,
    required this.team2Id,
    this.winnerTeamId,
    this.team1ArmorTier = 0,
    this.team2ArmorTier = 0,
    this.team1LinesSent = 0,
    this.team2LinesSent = 0,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory TetrisMatchModel.fromMap(Map<String, dynamic> map) {
    return TetrisMatchModel(
      id: map['id'] as String,
      roomCode: map['room_code'] as String? ?? '90960',
      roomName: map['room_name'] as String? ?? 'Duelo 1c1 Gameros',
      // La contraseña nunca se guarda ni se lee en texto plano: la columna
      // real es 'password_hash' (bcrypt) y solo el server la compara vía
      // tetris.verificar_password_sala.
      password: null,
      isPrivate: map['is_private'] as bool? ?? false,
      allowSpectators: map['allow_spectators'] as bool? ?? true,
      tournamentId: map['tournament_id'] as String?,
      roundNumber: map['round_number'] as int? ?? 1,
      format: map['format'] as String? ?? '1v1',
      status: map['status'] as String? ?? 'pending',
      team1Id: map['team_1_id'] as String? ?? generateUuidV4(),
      team2Id: map['team_2_id'] as String? ?? generateUuidV4(),
      winnerTeamId: map['winner_team_id'] as String?,
      team1ArmorTier: map['team_1_armor_tier'] as int? ?? 0,
      team2ArmorTier: map['team_2_armor_tier'] as int? ?? 0,
      team1LinesSent: map['team_1_lines_sent'] as int? ?? 0,
      team2LinesSent: map['team_2_lines_sent'] as int? ?? 0,
      createdAt: DateTime.tryParse(map['created_at'] ?? '') ?? DateTime.now(),
    );
  }
}

class TetrisPlayerModel {
  final String id;
  final String matchId;
  final String teamId;
  final String userId;
  final String gamerTag;
  final bool isAlive;
  final int linesCleared;
  final int linesSent;

  TetrisPlayerModel({
    required this.id,
    required this.matchId,
    required this.teamId,
    required this.userId,
    required this.gamerTag,
    this.isAlive = true,
    this.linesCleared = 0,
    this.linesSent = 0,
  });

  factory TetrisPlayerModel.fromMap(Map<String, dynamic> map) {
    return TetrisPlayerModel(
      id: map['id'] as String,
      matchId: map['match_id'] as String,
      teamId: map['team_id'] as String,
      userId: map['user_id'] as String,
      gamerTag: map['gamer_tag'] as String? ?? 'Gamer',
      isAlive: map['is_alive'] as bool? ?? true,
      linesCleared: map['lines_cleared'] as int? ?? 0,
      linesSent: map['lines_sent'] as int? ?? 0,
    );
  }
}

class TetrisMatchService {
  SupabaseClient get supabase => SupabaseConfig.client;

  /// Búsqueda Rápida 1v1 Automática
  Future<Map<String, dynamic>> buscarPartidaRapida(String gamerTag) async {
    final user = supabase.auth.currentUser;
    if (user == null) throw Exception('Debes iniciar sesión para buscar partida');

    try {
      // Firma real desplegada en Supabase (supabase/0002_matchmaking_seguridad.sql):
      // tetris.buscar_partida_automatica(p_gamer_tag TEXT) — el usuario se
      // identifica con auth.uid() adentro de la función, no por parámetro.
      final res = await supabase.schema('tetris').rpc('buscar_partida_automatica', params: {
        'p_gamer_tag': gamerTag,
      });
      if (res != null && res is Map) {
        return Map<String, dynamic>.from(res);
      }
    } catch (_) {
      // Red de seguridad si la función no está desplegada en este entorno.
      return await _matchmakingDirecto(user.id, gamerTag);
    }

    return await _matchmakingDirecto(user.id, gamerTag);
  }

  Future<Map<String, dynamic>> _matchmakingDirecto(String userId, String gamerTag) async {
    try {
      final since = DateTime.now().subtract(const Duration(seconds: 45)).toIso8601String();
      final pendingMatches = await supabase
          .schema('tetris')
          .from('match_tetris')
          .select('*, match_tetris_players(*)')
          .eq('status', 'pending')
          .eq('format', '1v1')
          .gte('created_at', since)
          .order('created_at', ascending: false)
          .limit(5);

      if (pendingMatches is List && pendingMatches.isNotEmpty) {
        for (final m in pendingMatches) {
          final players = (m['match_tetris_players'] as List? ?? []);
          final isMeInMatch = players.any((p) => p['user_id'] == userId);
          if (!isMeInMatch && players.length == 1) {
            final matchId = m['id'] as String;
            final team2Id = m['team_2_id'] as String;

            await supabase.schema('tetris').from('match_tetris_players').insert({
              'match_id': matchId,
              'team_id': team2Id,
              'user_id': userId,
              'gamer_tag': gamerTag,
            });

            await supabase.schema('tetris').from('match_tetris').update({
              'status': 'in_progress',
              'started_at': DateTime.now().toIso8601String(),
            }).eq('id', matchId);

            return {
              'status': 'matched',
              'match_id': matchId,
              'team_id': team2Id,
              'is_host': false,
            };
          } else if (isMeInMatch) {
            if (m['status'] == 'in_progress' || players.length >= 2) {
              return {
                'status': 'matched',
                'match_id': m['id'],
                'team_id': m['team_1_id'],
                'is_host': true,
              };
            }
            return {
              'status': 'waiting',
              'match_id': m['id'],
              'team_id': m['team_1_id'],
              'is_host': true,
            };
          }
        }
      }
    } catch (_) {}

    final team1Uuid = generateUuidV4();
    final team2Uuid = generateUuidV4();

    final newMatch = await supabase.schema('tetris').from('match_tetris').insert({
      'format': '1v1',
      'team_1_id': team1Uuid,
      'team_2_id': team2Uuid,
      'status': 'pending',
    }).select('id, team_1_id, team_2_id, status').single();

    final matchId = newMatch['id'] as String;

    await supabase.schema('tetris').from('match_tetris_players').insert({
      'match_id': matchId,
      'team_id': team1Uuid,
      'user_id': userId,
      'gamer_tag': gamerTag,
    });

    return {
      'status': 'waiting',
      'match_id': matchId,
      'team_id': team1Uuid,
      'is_host': true,
    };
  }

  Future<Map<String, dynamic>> consultarEstadoMatch(String matchId, String myTeamId) async {
    try {
      final res = await supabase
          .schema('tetris')
          .from('match_tetris')
          .select('status, match_tetris_players(*)')
          .eq('id', matchId)
          .maybeSingle();

      if (res != null) {
        final status = res['status'] as String?;
        final players = res['match_tetris_players'] as List? ?? [];
        if (status == 'in_progress' || players.length >= 2) {
          return {
            'status': 'matched',
            'match_id': matchId,
            'team_id': myTeamId,
          };
        }
      }
    } catch (_) {}
    return {'status': 'waiting', 'match_id': matchId, 'team_id': myTeamId};
  }

  Future<void> cancelarBusqueda(String matchId) async {
    try {
      await supabase.schema('tetris').from('match_tetris').delete().eq('id', matchId).eq('status', 'pending');
    } catch (_) {}
  }

  Future<TetrisMatchModel> createMatch({
    required String format,
    required String team1Id,
    required String team2Id,
    String roomName = 'Duelo 1c1',
    String? password,
    bool allowSpectators = true,
    String? tournamentId,
    int roundNumber = 1,
  }) async {
    final isPriv = password != null && password.trim().isNotEmpty;

    // Asegurar UUIDs válidos para no violar el esquema de Supabase
    final safeTeam1 = RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(team1Id) ? team1Id : generateUuidV4();
    final safeTeam2 = RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(team2Id) ? team2Id : generateUuidV4();

    if (isPriv) {
      // La contraseña nunca viaja como texto plano a una columna: el RPC
      // tetris.crear_sala_privada la hashea con pgcrypto/bcrypt en el server
      // (supabase/0002_matchmaking_seguridad.sql).
      final res = await supabase.schema('tetris').rpc('crear_sala_privada', params: {
        'p_room_name': roomName,
        'p_password': password.trim(),
        'p_team_1_id': safeTeam1,
        'p_team_2_id': safeTeam2,
        'p_format': format,
        'p_allow_spectators': allowSpectators,
        if (tournamentId != null) 'p_tournament_id': tournamentId,
        'p_round_number': roundNumber,
      });
      return TetrisMatchModel.fromMap(Map<String, dynamic>.from(res as Map));
    }

    final response = await supabase
        .schema('tetris')
        .from('match_tetris')
        .insert({
          'format': format,
          'team_1_id': safeTeam1,
          'team_2_id': safeTeam2,
          'room_name': roomName,
          'is_private': false,
          'allow_spectators': allowSpectators,
          'tournament_id': tournamentId,
          'round_number': roundNumber,
          'status': 'pending',
        })
        .select('id, format, status, team_1_id, team_2_id, created_at')
        .single();

    return TetrisMatchModel.fromMap(response);
  }

  Future<void> joinMatch({
    required String matchId,
    required String teamId,
    required String gamerTag,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      throw Exception('Debes iniciar sesión para unirte a una partida');
    }
    final safeTeamId = RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(teamId) ? teamId : generateUuidV4();

    await supabase.schema('tetris').from('match_tetris_players').upsert({
      'match_id': matchId,
      'team_id': safeTeamId,
      'user_id': user.id,
      'gamer_tag': gamerTag,
    });
  }

  Future<TetrisMatchModel> getMatch(String matchIdOrCode, [String? password]) async {
    final cleanInput = matchIdOrCode.trim();

    final res = await supabase
        .schema('tetris')
        .from('match_tetris')
        .select('id, format, status, team_1_id, team_2_id, room_name, is_private, allow_spectators, created_at')
        .eq('id', cleanInput)
        .single();

    final match = TetrisMatchModel.fromMap(res);
    if (match.isPrivate) {
      // La verificación corre en el server contra el hash bcrypt guardado
      // (tetris.verificar_password_sala) — nunca se compara texto plano acá.
      final ok = await supabase.schema('tetris').rpc('verificar_password_sala', params: {
        'p_match_id': match.id,
        'p_password': password?.trim() ?? '',
      });
      if (ok != true) {
        throw Exception('Contraseña de sala incorrecta.');
      }
    }
    return match;
  }

  Future<List<TetrisMatchModel>> getActivePublicRooms() async {
    try {
      final res = await supabase
          .schema('tetris')
          .from('match_tetris')
          .select()
          .eq('status', 'pending')
          .order('created_at', ascending: false)
          .limit(20);

      return (res as List).map((e) => TetrisMatchModel.fromMap(e)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<TetrisPlayerModel>> getMatchPlayers(String matchId) async {
    final res = await supabase
        .schema('tetris')
        .from('match_tetris_players')
        .select()
        .eq('match_id', matchId);

    return (res as List).map((e) => TetrisPlayerModel.fromMap(e)).toList();
  }

  Future<void> startMatch(String matchId) async {
    await supabase.schema('tetris').from('match_tetris').update({
      'status': 'in_progress',
      'started_at': DateTime.now().toIso8601String(),
    }).eq('id', matchId);
  }


  /// Reporte automático directo para Torneos Gameros (Decisión de Lucas)
  /// Dispara el RPC 'reportar_resultado_cruce_torneo' para avanzar el bracket,
  /// actualizar posiciones y notificar en Discord sin requerir doble confirmación.
  Future<Map<String, dynamic>> reportarResultadoCruceTorneo({
    required String matchId,
    required String winnerTeamId,
    String? tournamentId,
    Map<String, dynamic>? payload,
  }) async {
    try {
      final res = await supabase.rpc('reportar_resultado_cruce_torneo', params: {
        'p_match_id': matchId,
        'p_winner_team_id': winnerTeamId,
        if (tournamentId != null) 'p_tournament_id': tournamentId,
        'p_payload': payload ?? {
          'juego': 'Tetris Now',
          'fecha': DateTime.now().toIso8601String(),
        },
      });
      if (res != null && res is Map) {
        return Map<String, dynamic>.from(res);
      }
      return {'status': 'reported', 'result': res};
    } catch (_) {
      return await reportMatchResult(
        matchId: matchId,
        winnerTeamId: winnerTeamId,
        payload: payload,
      );
    }
  }

  /// Penaliza el ELO del jugador que abandonó (15% del rating actual, sin
  /// piso — puede quedar negativo). tetris.penalizar_abandono valida el
  /// match/jugador server-side (supabase/0002_matchmaking_seguridad.sql).
  Future<void> penalizarAbandono({
    required String matchId,
    required String userId,
  }) async {
    await supabase.schema('tetris').rpc('penalizar_abandono', params: {
      'p_match_id': matchId,
      'p_user_id': userId,
    });
  }

  Future<Map<String, dynamic>> reportMatchResult({
    required String matchId,
    required String winnerTeamId,
    Map<String, dynamic>? payload,
  }) async {
    final res = await supabase.rpc('reportar_resultado_partida_externa', params: {
      'p_juego_nombre': 'Tetris Now',
      'p_match_id': matchId,
      'p_winner_team_id': winnerTeamId,
      'p_payload': payload ?? {},
    });

    return Map<String, dynamic>.from(res as Map);
  }
}
