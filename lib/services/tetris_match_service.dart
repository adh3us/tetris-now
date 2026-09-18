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
  final String? torneoPartidaId;
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
    this.torneoPartidaId,
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
      torneoPartidaId: map['torneo_partida_id'] as String? ?? map['tournament_id'] as String?,
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
          .select('id, team_1_id, team_2_id, status, created_at')
          .eq('status', 'pending')
          .eq('format', '1v1')
          .gte('created_at', since)
          .order('created_at', ascending: false)
          .limit(5);

      if (pendingMatches is List && pendingMatches.isNotEmpty) {
        for (final m in pendingMatches) {
          final matchId = m['id'] as String;
          // Verificar si yo ya soy el creador de esta sala
          final myPlayer = await supabase
              .schema('tetris')
              .from('match_tetris_players')
              .select('id')
              .eq('match_id', matchId)
              .eq('user_id', userId)
              .maybeSingle();

          if (myPlayer == null) {
            // Es la sala de un rival real en espera: nos unimos como team_2
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
          } else {
            // Ya estoy en esta sala; si ya cambió a in_progress iniciamos
            if (m['status'] == 'in_progress') {
              return {
                'status': 'matched',
                'match_id': matchId,
                'team_id': m['team_1_id'],
                'is_host': true,
              };
            }
            return {
              'status': 'waiting',
              'match_id': matchId,
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

  /// Consulta el estado del emparejamiento automático:
  /// Verifica la cola mediante mi_estado_matchmaking y la sala en match_tetris.
  Future<Map<String, dynamic>> consultarEstadoMatchmaking(String? matchId, String myTeamId) async {
    final user = supabase.auth.currentUser;
    if (user == null) return {'status': 'idle'};

    // 1. Consultar RPC oficial de cola
    try {
      final res = await supabase.schema('tetris').rpc('mi_estado_matchmaking');
      if (res != null && res is Map) {
        final st = res['status'] as String?;
        final mId = res['match_id'] as String?;
        final tId = res['team_id'] as String?;
        if (st == 'matched' && mId != null) {
          return {
            'status': 'matched',
            'match_id': mId,
            'team_id': tId ?? myTeamId,
          };
        } else if (st == 'waiting') {
          return {
            'status': 'waiting',
            'match_id': mId ?? matchId,
            'team_id': tId ?? myTeamId,
          };
        }
      }
    } catch (_) {}

    // 2. Si hay matchId concreto, verificar en tabla match_tetris
    if (matchId != null && matchId.isNotEmpty) {
      return await consultarEstadoMatch(matchId, myTeamId);
    }

    return {'status': 'waiting', 'match_id': matchId, 'team_id': myTeamId};
  }

  Future<Map<String, dynamic>> consultarEstadoMatch(String matchId, String myTeamId) async {
    try {
      final res = await supabase
          .schema('tetris')
          .from('match_tetris')
          .select('status, match_tetris_players(id, user_id)')
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

  Future<void> cancelarBusqueda([String? matchId]) async {
    try {
      await supabase.schema('tetris').rpc('cancelar_busqueda');
    } catch (_) {}
    if (matchId != null && matchId.isNotEmpty) {
      try {
        await supabase.schema('tetris').from('match_tetris').delete().eq('id', matchId).eq('status', 'pending');
      } catch (_) {}
    }
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


  /// Reporte automático directo para Torneos Gameros (Contrato oficial Gameros ↔ Tetris Now)
  /// Dispara el RPC 'reportar_resultado_cruce_torneo' para avanzar el bracket,
  /// actualizar posiciones y notificar en Gameros sin requerir doble confirmación.
  Future<Map<String, dynamic>> reportarResultadoCruceTorneo({
    required String partidaId, // ID de public.partidas (el cruce del bracket de Gameros)
    String? ganadorInscripcionId, // ID de inscripciones_torneo (o se resuelve dinámicamente)
    bool empate = false,
    required String matchId,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      String? inscripcionGanadora = ganadorInscripcionId;

      // Si no se pasó explícitamente la inscripción ganadora y no es empate,
      // intentamos resolverla desde public.partidas e inscripciones_torneo.
      if (!empate && (inscripcionGanadora == null || inscripcionGanadora.isEmpty)) {
        try {
          final partidaRow = await supabase
              .from('partidas')
              .select('inscripcion_a_id, inscripcion_b_id')
              .eq('id', partidaId)
              .maybeSingle();

          if (partidaRow != null) {
            final inscA = partidaRow['inscripcion_a_id'] as String?;
            final inscB = partidaRow['inscripcion_b_id'] as String?;
            final currentUserId = supabase.auth.currentUser?.id;

            if (inscA != null && currentUserId != null) {
              final inscRow = await supabase
                  .from('inscripciones_torneo')
                  .select('id, usuario_id')
                  .eq('id', inscA)
                  .maybeSingle();

              if (inscRow != null && inscRow['usuario_id'] == currentUserId) {
                inscripcionGanadora = inscA;
              } else if (inscB != null) {
                inscripcionGanadora = inscB;
              }
            }
          }
        } catch (_) {}
      }

      final res = await supabase.rpc('reportar_resultado_cruce_torneo', params: {
        'p_partida_id': partidaId,
        'p_ganador_inscripcion_id': empate ? null : inscripcionGanadora,
        'p_empate': empate,
        'p_metadata': {
          'juego': 'Tetris Now',
          'tetris_match_id': matchId,
          'fecha': DateTime.now().toIso8601String(),
          if (metadata != null) ...metadata,
        },
      });

      if (res != null && res is Map) {
        return Map<String, dynamic>.from(res);
      }
      return {'status': 'reported', 'result': res};
    } catch (_) {
      return await reportMatchResult(
        matchId: matchId,
        winnerTeamId: ganadorInscripcionId ?? 'winner',
        payload: metadata,
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

  /// Calcula el cambio de ELO dinámico:
  /// - Victoria: entre +60 y +100 puntos según rapidez e intensidad.
  /// - Derrota: entre -50 y -90 puntos bajo el mismo criterio.
  /// - Abandono: -90 puntos directos.
  static int calcularEloDeltaGanador({
    required double durationSeconds,
    required int linesSent,
    required int maxCombo,
    required int linesCleared,
  }) {
    final speedFactor = ((180.0 - durationSeconds.clamp(30.0, 180.0)) / 150.0).clamp(0.0, 1.0);
    final intensityFactor = ((linesSent / 12.0 * 0.5) + (maxCombo / 5.0 * 0.3) + (linesCleared / 20.0 * 0.2)).clamp(0.0, 1.0);
    final bonus = (speedFactor * 20.0 + intensityFactor * 20.0).round();
    return (60 + bonus).clamp(60, 100);
  }

  static int calcularEloDeltaPerdedor({
    required double durationSeconds,
    required int linesSent,
    required int maxCombo,
    required int linesCleared,
    bool isSurrender = false,
  }) {
    if (isSurrender) return -90;
    final speedFactor = ((180.0 - durationSeconds.clamp(30.0, 180.0)) / 150.0).clamp(0.0, 1.0);
    final intensityFactor = ((linesSent / 12.0 * 0.5) + (maxCombo / 5.0 * 0.3) + (linesCleared / 20.0 * 0.2)).clamp(0.0, 1.0);
    final penalty = (speedFactor * 20.0 + (1.0 - intensityFactor) * 20.0).round();
    return -(50 + penalty).clamp(50, 90);
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
