import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase_config.dart';

class TetrisMatchModel {
  final String id;
  final String roomCode;
  final String roomName;
  final bool isPrivate;
  final bool allowSpectators;
  final String? tournamentId;
  final int roundNumber;
  final String format; // '1v1'
  final String status; // 'pending', 'ready_check', 'in_progress', 'finished', 'en_disputa'
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
      isPrivate: map['is_private'] as bool? ?? false,
      allowSpectators: map['allow_spectators'] as bool? ?? true,
      tournamentId: map['tournament_id'] as String?,
      roundNumber: map['round_number'] as int? ?? 1,
      format: map['format'] as String? ?? '1v1',
      status: map['status'] as String? ?? 'pending',
      team1Id: map['team_1_id'] as String? ?? 'team_1',
      team2Id: map['team_2_id'] as String? ?? 'team_2',
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

  /// Genera un UUID v4 sin depender de un paquete extra (ya que
  /// `team_1_id`/`team_2_id`/`team_id` son columnas UUID en la base:
  /// pasar strings como "team_alpha_<id>" rompe el insert).
  String _uuidV4() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int start, int end) =>
        bytes.sublist(start, end).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
  }

  Future<TetrisMatchModel> createMatch({
    required String format,
    String? team1Id,
    String? team2Id,
    String roomName = 'Duelo 1c1',
    String? password,
    bool allowSpectators = true,
    String? tournamentId,
    int roundNumber = 1,
  }) async {
    final code = '${Random().nextInt(89999) + 10000}';
    final isPriv = password != null && password.trim().isNotEmpty;

    final response = await supabase
        .schema('tetris')
        .from('match_tetris')
        .insert({
          'room_code': code,
          'room_name': roomName,
          'allow_spectators': allowSpectators,
          'format': format,
          'team_1_id': team1Id ?? _uuidV4(),
          'team_2_id': team2Id ?? _uuidV4(),
          'tournament_id': tournamentId,
          'round_number': roundNumber,
          'status': 'pending',
        })
        .select()
        .single();

    final match = TetrisMatchModel.fromMap(response);

    // La contraseña nunca viaja en texto plano a la tabla: se hashea
    // server-side vía tetris.crear_sala_privada (bcrypt/pgcrypto).
    if (isPriv) {
      await supabase.schema('tetris').rpc('crear_sala_privada', params: {
        'p_match_id': match.id,
        'p_password': password.trim(),
      });
    }

    return match;
  }

  Future<void> joinMatch({
    required String matchId,
    required String teamId,
    required String gamerTag,
  }) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('Necesitás iniciar sesión con tu cuenta de Gameros para unirte a una sala.');
    }
    await supabase.schema('tetris').from('match_tetris_players').upsert({
      'match_id': matchId,
      'team_id': teamId,
      'user_id': userId,
      'gamer_tag': gamerTag,
    });
  }

  Future<TetrisMatchModel> getMatch(String matchIdOrCode, [String? password]) async {
    final cleanInput = matchIdOrCode.trim();
    final isUuid = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$').hasMatch(cleanInput);

    Map<String, dynamic> res;
    if (isUuid) {
      res = await supabase
          .schema('tetris')
          .from('match_tetris')
          .select()
          .eq('id', cleanInput)
          .single();
    } else {
      final numericCode = cleanInput.replaceAll('room_', '').replaceAll('#', '').trim();
      res = await supabase
          .schema('tetris')
          .from('match_tetris')
          .select()
          .or('room_code.eq.$numericCode,room_code.eq.$cleanInput')
          .order('created_at', ascending: false)
          .limit(1)
          .single();
    }

    final match = TetrisMatchModel.fromMap(res);
    if (match.isPrivate) {
      // La verificación real la hace tetris.verificar_password_sala
      // (compara el hash server-side); acá solo se corta temprano si
      // ni siquiera mandaron contraseña.
      if (password == null || password.trim().isEmpty) {
        throw Exception('Esta sala requiere contraseña.');
      }
      final ok = await supabase.schema('tetris').rpc('verificar_password_sala', params: {
        'p_match_id': match.id,
        'p_password': password.trim(),
      }) as bool;
      if (!ok) {
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

  /// Botón único "Jugar": entra a la cola de matchmaking automático y,
  /// si ya había un rival esperando, devuelve el match_id recién creado.
  /// Si devuelve null, hay que seguir esperando (ver [miEstadoMatchmaking]).
  Future<String?> buscarPartidaAutomatica(String gamerTag) async {
    final res = await supabase.schema('tetris').rpc('buscar_partida_automatica', params: {
      'p_gamer_tag': gamerTag,
    });
    return res as String?;
  }

  /// Polling mientras se espera en cola: si otro jugador ya nos
  /// emparejó, devuelve el match_id de la partida recién creada.
  Future<String?> miEstadoMatchmaking() async {
    final res = await supabase.schema('tetris').rpc('mi_estado_matchmaking');
    return res as String?;
  }

  Future<void> cancelarBusqueda() async {
    await supabase.schema('tetris').rpc('cancelar_busqueda');
  }

  /// La llama el jugador que sigue conectado cuando el rival no volvió
  /// a aparecer tras el timeout de reconexión (30s, ver
  /// TetrisRealtimeService). Penaliza el ELO del que abandonó.
  Future<void> penalizarAbandono({
    required String matchId,
    required String userIdAbandono,
  }) async {
    await supabase.schema('tetris').rpc('penalizar_abandono', params: {
      'p_match_id': matchId,
      'p_user_id': userIdAbandono,
    });
  }
}
