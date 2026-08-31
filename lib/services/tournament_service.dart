import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase_config.dart';
import 'tetris_match_service.dart';

class TournamentModel {
  final String id;
  final String title;
  final String format; // '1v1' | '2v2'
  final String status; // 'registration' | 'in_progress' | 'completed'
  final int maxTeams;
  final int currentTeams;

  TournamentModel({
    required this.id,
    required this.title,
    required this.format,
    required this.status,
    required this.maxTeams,
    this.currentTeams = 0,
  });

  factory TournamentModel.fromMap(Map<String, dynamic> map) {
    return TournamentModel(
      id: map['id'] as String,
      title: map['title'] as String? ?? 'Torneo Tetris VS',
      format: map['format'] as String? ?? '1v1',
      status: map['status'] as String? ?? 'registration',
      maxTeams: map['max_teams'] as int? ?? 8,
      currentTeams: map['current_teams'] as int? ?? 0,
    );
  }
}

class TournamentService {
  final SupabaseClient supabase = SupabaseConfig.client;

  /// Obtiene los torneos activos de Tetris
  Future<List<TournamentModel>> getActiveTournaments() async {
    try {
      final res = await supabase
          .schema('tetris')
          .from('match_tetris')
          .select('tournament_id')
          .not('tournament_id', 'is', null);

      // Agrupar torneos unicos
      final tournamentIds = (res as List).map((e) => e['tournament_id'] as String).toSet().toList();
      
      return tournamentIds.map((id) => TournamentModel(
        id: id,
        title: 'Copa Gameros Tetris #$id',
        format: '1v1',
        status: 'in_progress',
        maxTeams: 8,
        currentTeams: 8,
      )).toList();
    } catch (e) {
      return [];
    }
  }

  /// Obtiene las partidas y rondas del bracket de un torneo
  Future<List<TetrisMatchModel>> getTournamentMatches(String tournamentId) async {
    final res = await supabase
        .schema('tetris')
        .from('match_tetris')
        .select()
        .eq('tournament_id', tournamentId)
        .order('round_number', ascending: true);

    return (res as List).map((e) => TetrisMatchModel.fromMap(e)).toList();
  }
}
