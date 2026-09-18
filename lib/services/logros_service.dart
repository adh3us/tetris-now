import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase_config.dart';

class LogroItem {
  final String id;
  final String titulo;
  final String descripcion;
  final String icono;
  final String categoria;
  final int puntos;
  final int orden;
  final bool desbloqueado;
  final DateTime? desbloqueadoEn;

  LogroItem({
    required this.id,
    required this.titulo,
    required this.descripcion,
    required this.icono,
    required this.categoria,
    required this.puntos,
    required this.orden,
    this.desbloqueado = false,
    this.desbloqueadoEn,
  });

  factory LogroItem.fromMap(Map<String, dynamic> map, {bool desbloqueado = false, DateTime? desbloqueadoEn}) {
    return LogroItem(
      id: map['id']?.toString() ?? '',
      titulo: map['titulo']?.toString() ?? '',
      descripcion: map['descripcion']?.toString() ?? '',
      icono: map['icono']?.toString() ?? 'trophy',
      categoria: map['categoria']?.toString() ?? 'combate',
      puntos: map['puntos'] as int? ?? 10,
      orden: map['orden'] as int? ?? 0,
      desbloqueado: desbloqueado,
      desbloqueadoEn: desbloqueadoEn,
    );
  }
}

class LogrosService {
  SupabaseClient get _client => SupabaseConfig.client;

  /// Obtiene la lista completa del catálogo de logros combinada con el estado de desbloqueo del usuario
  Future<List<LogroItem>> getLogrosConEstadoUsuario([String? targetUserId]) async {
    final user = _client.auth.currentUser;
    final uid = targetUserId ?? user?.id;

    List<Map<String, dynamic>> catalogo = [];
    try {
      final res = await _client
          .schema('tetris')
          .from('logros')
          .select()
          .order('orden', ascending: true);
      catalogo = List<Map<String, dynamic>>.from(res as List);
    } catch (_) {
      // Fallback con catálogo local si las tablas en Supabase aún están recién creadas
      catalogo = _catalogoFallback;
    }

    // Consultar desbloqueados
    final Map<String, DateTime> desbloqueadosMap = {};
    if (uid != null) {
      try {
        final res = await _client
            .schema('tetris')
            .from('logros_desbloqueados')
            .select('logro_id, desbloqueado_en')
            .eq('user_id', uid);
        for (final row in (res as List)) {
          final lid = row['logro_id']?.toString() ?? '';
          final dtStr = row['desbloqueado_en']?.toString();
          if (lid.isNotEmpty) {
            desbloqueadosMap[lid] = dtStr != null ? DateTime.tryParse(dtStr) ?? DateTime.now() : DateTime.now();
          }
        }
      } catch (_) {}
    }

    return catalogo.map((m) {
      final id = m['id']?.toString() ?? '';
      final isUnlocked = desbloqueadosMap.containsKey(id);
      return LogroItem.fromMap(m, desbloqueado: isUnlocked, desbloqueadoEn: desbloqueadosMap[id]);
    }).toList();
  }

  /// Desbloquea un logro para el usuario autenticado actual
  Future<bool> desbloquearLogro(String logroId) async {
    final user = _client.auth.currentUser;
    if (user == null) return false;

    try {
      await _client.schema('tetris').from('logros_desbloqueados').upsert(
        {
          'user_id': user.id,
          'logro_id': logroId,
          'completado': true,
          'desbloqueado_en': DateTime.now().toIso8601String(),
        },
        onConflict: 'user_id,logro_id',
        ignoreDuplicates: true,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Verifica y desbloquea automáticamente logros basados en las métricas de una partida
  Future<void> evaluarLogrosDePartida({
    required int linesCleared,
    required int maxCombo,
    required int currentHp,
    required bool isWinner,
    required bool hasGoldCube,
    required bool hasSilverCube,
    required bool isDuel,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    if (linesCleared >= 4) {
      await desbloquearLogro('primer_tetris');
    }
    if (maxCombo >= 3) {
      await desbloquearLogro('combo_x3');
    }
    if (maxCombo >= 5) {
      await desbloquearLogro('combo_x5');
    }
    if (hasGoldCube) {
      await desbloquearLogro('cubo_dorado');
    }
    if (hasSilverCube) {
      await desbloquearLogro('cubo_plata');
    }
    if (isDuel) {
      await desbloquearLogro('primer_duelo');
      if (isWinner) {
        await desbloquearLogro('primera_victoria');
        if (currentHp > 0 && currentHp <= 20) {
          await desbloquearLogro('pared_de_hierro');
        }
      }
    }
  }

  static const List<Map<String, dynamic>> _catalogoFallback = [
    {
      'id': 'primer_tetris',
      'titulo': '¡Tetris Limpio!',
      'descripcion': 'Limpia 4 líneas simultáneas con una sola pieza I.',
      'icono': 'flash_on',
      'categoria': 'habilidad',
      'puntos': 10,
      'orden': 1,
    },
    {
      'id': 'combo_x3',
      'titulo': 'Cadena de Reacción',
      'descripcion': 'Alcanza una racha de combo de x3 o superior.',
      'icono': 'bolt',
      'categoria': 'habilidad',
      'puntos': 15,
      'orden': 2,
    },
    {
      'id': 'combo_x5',
      'titulo': 'Tormenta de Bloques',
      'descripcion': 'Alcanza una racha de combo de x5 o superior en partida activa.',
      'icono': 'whatshot',
      'categoria': 'habilidad',
      'puntos': 25,
      'orden': 3,
    },
    {
      'id': 'cubo_dorado',
      'titulo': 'Toque de Midas',
      'descripcion': 'Construye un Cubo Dorado (Monocube 4x4) de una sola pieza.',
      'icono': 'star',
      'categoria': 'alquimia',
      'puntos': 20,
      'orden': 4,
    },
    {
      'id': 'cubo_plata',
      'titulo': 'Alquimia Metálica',
      'descripcion': 'Construye un Cubo Plateado (Multicube 4x4) combinando piezas.',
      'icono': 'shield',
      'categoria': 'alquimia',
      'puntos': 20,
      'orden': 5,
    },
    {
      'id': 'primer_duelo',
      'titulo': 'Bautismo de Fuego',
      'descripcion': 'Completa tu primera partida en el radar 1v1 rápido.',
      'icono': 'sports_esports',
      'categoria': 'combate',
      'puntos': 10,
      'orden': 6,
    },
    {
      'id': 'primera_victoria',
      'titulo': 'Primera Sangre',
      'descripcion': 'Gana tu primer duelo 1v1 contra un rival en tiempo real.',
      'icono': 'emoji_events',
      'categoria': 'combate',
      'puntos': 20,
      'orden': 7,
    },
    {
      'id': 'racha_3_victorias',
      'titulo': 'Imparable',
      'descripcion': 'Gana 3 partidas 1v1 de forma consecutiva.',
      'icono': 'military_tech',
      'categoria': 'combate',
      'puntos': 30,
      'orden': 8,
    },
    {
      'id': 'pared_de_hierro',
      'titulo': 'Superviviente Crítico',
      'descripcion': 'Recupérate y gana una partida tras haber tenido menos de 20 HP.',
      'icono': 'health_and_safety',
      'categoria': 'combate',
      'puntos': 25,
      'orden': 9,
    },
    {
      'id': 'maestro_srs',
      'titulo': 'Giro Fantasma',
      'descripcion': 'Ejecuta una rotación SRS avanzada para encajar una pieza bloqueada.',
      'icono': 'autorenew',
      'categoria': 'habilidad',
      'puntos': 15,
      'orden': 10,
    },
  ];
}
