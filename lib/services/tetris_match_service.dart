import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase_config.dart';

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
      password: map['password'] as String?,
      isPrivate: (map['password'] != null && (map['password'] as String).isNotEmpty) || (map['is_private'] as bool? ?? false),
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
    final code = '${Random().nextInt(89999) + 10000}';
    final isPriv = password != null && password.trim().isNotEmpty;

    final response = await supabase
        .schema('tetris')
        .from('match_tetris')
        .insert({
          'room_code': code,
          'room_name': roomName,
          'password': isPriv ? password.trim() : null,
          'allow_spectators': allowSpectators,
          'format': format,
          'team_1_id': team1Id,
          'team_2_id': team2Id,
          'tournament_id': tournamentId,
          'round_number': roundNumber,
          'status': 'pending',
        })
        .select()
        .single();

    return TetrisMatchModel.fromMap(response);
  }

  Future<void> joinMatch({
    required String matchId,
    required String teamId,
    required String gamerTag,
  }) async {
    final userId = supabase.auth.currentUser?.id ?? 'guest_user';
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
    if (match.isPrivate && match.password != null && match.password!.isNotEmpty) {
      if (password == null || password.trim() != match.password) {
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
      return [
        TetrisMatchModel(
          id: 'demo_1',
          roomCode: '90960',
          roomName: 'Duelo de Lucas (Gameros)',
          format: '1v1',
          status: 'pending',
          team1Id: 't1',
          team2Id: 't2',
          isPrivate: false,
        ),
        TetrisMatchModel(
          id: 'demo_2',
          roomCode: '45812',
          roomName: 'Torneo Privado Alpha',
          password: '123',
          format: '1v1',
          status: 'pending',
          team1Id: 't1',
          team2Id: 't2',
          isPrivate: true,
        ),
      ];
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
}
