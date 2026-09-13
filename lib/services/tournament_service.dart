import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase_config.dart';
import 'tetris_match_service.dart';

/// Torneo real de public.torneos (no una tabla propia de Tetris).
class TournamentModel {
  final String id;
  final String nombre;
  final String tipo; // 'individual' | 'equipo'
  final String estado; // 'inscripcion' | 'en_curso' | 'finalizado' | 'cancelado'
  final DateTime? createdAt;

  TournamentModel({
    required this.id,
    required this.nombre,
    required this.tipo,
    required this.estado,
    this.createdAt,
  });

  factory TournamentModel.fromMap(Map<String, dynamic> map) {
    return TournamentModel(
      id: map['id'] as String,
      nombre: map['nombre'] as String? ?? 'Torneo Tetris Now',
      tipo: map['tipo'] as String? ?? map['formato'] as String? ?? 'individual',
      estado: map['estado'] as String? ?? 'inscripcion',
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? ''),
    );
  }
}

class TournamentInvitationModel {
  final String id;
  final String torneoId;
  final String tipo; // 'individual' | 'equipo'
  final String? torneoNombre;

  TournamentInvitationModel({
    required this.id,
    required this.torneoId,
    required this.tipo,
    this.torneoNombre,
  });

  factory TournamentInvitationModel.fromMap(Map<String, dynamic> map) {
    // La forma exacta de mis_invitaciones_torneo() puede traer el torneo
    // embebido (map['torneos']) o aplanado (map['torneo_nombre']) según la
    // versión del RPC en Gameros — se contemplan ambas variantes.
    String? nombre;
    final nested = map['torneos'];
    if (nested is Map) {
      nombre = nested['nombre'] as String?;
    }
    nombre ??= map['torneo_nombre'] as String?;

    return TournamentInvitationModel(
      id: map['id'] as String,
      torneoId: map['torneo_id'] as String,
      tipo: map['tipo'] as String? ?? 'individual',
      torneoNombre: nombre,
    );
  }
}

class TournamentService {
  final SupabaseClient supabase = SupabaseConfig.client;

  String? _tetrisGameId;

  /// Resuelve el id de "Tetris Now" en public.juegos (no está hardcodeado).
  Future<String?> _getTetrisGameId() async {
    if (_tetrisGameId != null) return _tetrisGameId;
    try {
      final row = await supabase
          .from('juegos')
          .select('id')
          .ilike('nombre', '%tetris%')
          .maybeSingle();
      _tetrisGameId = row?['id'] as String?;
    } catch (_) {}
    return _tetrisGameId;
  }

  /// Torneos de Tetris Now abiertos a inscripción o en curso.
  Future<List<TournamentModel>> getTournaments() async {
    final gameId = await _getTetrisGameId();
    if (gameId == null) return [];

    try {
      final res = await supabase
          .from('torneos')
          .select()
          .eq('juego_id', gameId)
          .inFilter('estado', ['inscripcion', 'en_curso'])
          .order('created_at', ascending: false);

      return (res as List)
          .map((e) => TournamentModel.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Invitaciones directas pendientes del usuario logueado (individuales o
  /// de cualquier clan donde sea líder/co-líder).
  Future<List<TournamentInvitationModel>> getMyInvitations() async {
    try {
      final res = await supabase.rpc('mis_invitaciones_torneo');
      if (res is List) {
        return res
            .map((e) => TournamentInvitationModel.fromMap(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Future<bool> respondToInvitation(String invitationId, bool accept) async {
    try {
      await supabase.rpc('responder_invitacion_torneo', params: {
        'p_invitacion_id': invitationId,
        'p_aceptar': accept,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Inscripción individual directa (no vía invitación). El límite de 2
  /// torneos simultáneos y la validación de admite_individual corren
  /// server-side dentro de esta función.
  Future<bool> inscribirseIndividual(String tournamentId) async {
    try {
      await supabase.rpc('inscribirse_torneo', params: {
        'p_torneo_id': tournamentId,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> cancelarInscripcion(String tournamentId) async {
    try {
      await supabase.rpc('cancelar_inscripcion', params: {
        'p_torneo_id': tournamentId,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Cruces/partidas de Tetris ya jugados o programados para este torneo
  /// (tetris.match_tetris.tournament_id, ver supabase/fase0_init.sql).
  Future<List<TetrisMatchModel>> getTournamentMatches(String tournamentId) async {
    try {
      final res = await supabase
          .schema('tetris')
          .from('match_tetris')
          .select()
          .eq('tournament_id', tournamentId)
          .order('round_number', ascending: true);

      return (res as List).map((e) => TetrisMatchModel.fromMap(Map<String, dynamic>.from(e))).toList();
    } catch (_) {
      return [];
    }
  }
}
