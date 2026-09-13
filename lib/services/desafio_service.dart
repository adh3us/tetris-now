import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase_config.dart';

class DesafioModel {
  final String id;
  final String retadorId;
  final String retadoId;
  final String? matchId;
  final String estado;
  final DateTime expiraAt;
  final bool soyRetador;

  DesafioModel({
    required this.id,
    required this.retadorId,
    required this.retadoId,
    this.matchId,
    required this.estado,
    required this.expiraAt,
    required this.soyRetador,
  });

  Duration get tiempoRestante {
    final r = expiraAt.difference(DateTime.now());
    return r.isNegative ? Duration.zero : r;
  }

  factory DesafioModel.fromMap(Map<String, dynamic> map) {
    return DesafioModel(
      id: map['id'] as String,
      retadorId: map['retador_id'] as String,
      retadoId: map['retado_id'] as String,
      matchId: map['match_id'] as String?,
      estado: map['estado'] as String? ?? 'pendiente',
      expiraAt: DateTime.tryParse(map['expira_at']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
      soyRetador: map['soy_retador'] as bool? ?? false,
    );
  }
}

class DesafioService {
  SupabaseClient get supabase => SupabaseConfig.client;

  Future<Map<String, dynamic>?> crearDesafio(String retadoId, String gamerTag) async {
    try {
      final res = await supabase.schema('tetris').rpc('crear_desafio', params: {
        'p_retado_id': retadoId,
        'p_gamer_tag': gamerTag,
      });
      if (res is Map) return Map<String, dynamic>.from(res);
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> responderDesafio(String desafioId, bool aceptar, {String? gamerTag}) async {
    try {
      final res = await supabase.schema('tetris').rpc('responder_desafio', params: {
        'p_desafio_id': desafioId,
        'p_aceptar': aceptar,
        if (gamerTag != null) 'p_gamer_tag': gamerTag,
      });
      if (res is Map) return Map<String, dynamic>.from(res);
    } catch (_) {}
    return null;
  }

  Future<List<DesafioModel>> misDesafios() async {
    try {
      final res = await supabase.schema('tetris').rpc('mis_desafios');
      if (res is List) {
        return res.map((e) => DesafioModel.fromMap(Map<String, dynamic>.from(e))).toList();
      }
    } catch (_) {}
    return [];
  }
}
