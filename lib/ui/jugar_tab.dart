import 'package:flutter/material.dart';
import '../core/supabase_config.dart';
import '../game/tetris_types.dart';
import '../services/gameros_profile_service.dart';
import 'create_duel_screen.dart';
import 'profile_modal.dart';
import 'tetris_game_screen.dart';
import 'tutorial_screen.dart';

class JugarTab extends StatefulWidget {
  final bool isGuest;

  const JugarTab({Key? key, this.isGuest = false}) : super(key: key);

  @override
  State<JugarTab> createState() => _JugarTabState();
}

class _RankingEntry {
  final String userId;
  final String displayName;
  final int rating;
  _RankingEntry({required this.userId, required this.displayName, required this.rating});
}

class _JugarTabState extends State<JugarTab> {
  final GamerosProfileService _profileService = GamerosProfileService();
  GamerosUserProfile? _profile;
  List<_RankingEntry> _top10 = [];
  bool _isLoadingRanking = true;

  @override
  void initState() {
    super.initState();
    if (!widget.isGuest) _loadProfile();
    _loadRanking();
  }

  Future<void> _loadProfile() async {
    try {
      final p = await _profileService.getFullProfile();
      if (p != null && mounted) setState(() => _profile = p);
    } catch (_) {}
  }

  Future<void> _loadRanking() async {
    setState(() => _isLoadingRanking = true);
    try {
      final supabase = SupabaseConfig.client;
      final ratings = await supabase
          .schema('tetris')
          .from('ratings')
          .select('user_id, rating')
          .order('rating', ascending: false)
          .limit(10);

      final entries = <_RankingEntry>[];
      for (final row in (ratings as List)) {
        final userId = row['user_id'] as String;
        String name = 'Jugador Gameros';
        try {
          final uRow = await supabase.from('usuarios').select('nombre_display').eq('id', userId).maybeSingle();
          if (uRow != null) name = uRow['nombre_display'] as String? ?? name;
        } catch (_) {}
        entries.add(_RankingEntry(userId: userId, displayName: name, rating: row['rating'] as int? ?? 1000));
      }

      if (mounted) setState(() { _top10 = entries; _isLoadingRanking = false; });
    } catch (_) {
      if (mounted) setState(() => _isLoadingRanking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF070B19),
      child: Stack(
        children: [
          // Cuadrícula sutil tipo matriz de Tetris (5% opacidad)
          Positioned.fill(
            child: CustomPaint(
              painter: const _TetrisGridPainter(),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Avatar interactivo estilo bloque Tetrimino
                    GestureDetector(
                      onTap: () => HybridProfileModal.show(context, profile: _profile),
                      child: Tooltip(
                        message: 'Toca para ver tu perfil y logros',
                        child: Column(
                          children: [
                            Container(
                              width: 68,
                              height: 68,
                              decoration: BoxDecoration(
                                color: const Color(0xFF101735),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: const Color(0xFF00E5FF).withOpacity(0.8),
                                  width: 2.0,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF00E5FF).withOpacity(0.35),
                                    blurRadius: 14,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: _profile?.avatarUrl != null
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.network(
                                        _profile!.avatarUrl!,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => const Icon(
                                          Icons.sports_esports_rounded,
                                          size: 38,
                                          color: Color(0xFF00E5FF),
                                        ),
                                      ),
                                    )
                                  : const Icon(
                                      Icons.sports_esports_rounded,
                                      size: 38,
                                      color: Color(0xFF00E5FF),
                                    ),
                            ),
                            const SizedBox(height: 10),
                            if (!widget.isGuest && _profile != null) ...[
                              Text(
                                _profile!.displayName,
                                style: const TextStyle(
                                  color: Color(0xFF00E5FF),
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                  letterSpacing: 0.8,
                                  shadows: [
                                    Shadow(
                                      color: Color(0x6600E5FF),
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.touch_app_rounded, size: 12, color: Color(0xFF94A3B8)),
                                  const SizedBox(width: 4),
                                  Text(
                                    'VER PERFIL & LOGROS',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.6),
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Badge Rango en Amarillo Citrino brillante con resplandor neón
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
                      decoration: BoxDecoration(
                        color: const Color(0x22FACC15),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: const Color(0xFFFACC15).withOpacity(0.8),
                          width: 1.4,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFACC15).withOpacity(0.2),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.flash_on_rounded, size: 18, color: Color(0xFFFACC15)),
                          const SizedBox(width: 6),
                          Text(
                            widget.isGuest ? 'MODO INVITADO' : 'RANGO ${_profile?.tetrisElo ?? 1000}',
                            style: const TextStyle(
                              color: Color(0xFFFACC15),
                              fontSize: 14.5,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // BOTÓN PRINCIPAL: BUSCAR PARTIDA 1v1 (Gradiente diagonal Cian -> Magenta con bisel 3D arcade)
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFF00E5FF), // Cian vibrante
                            Color(0xFFFF2A85), // Magenta intenso
                          ],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE0F2FE), width: 1.2),
                        boxShadow: [
                          // Relieve 3D arcade: sombra inferior sólida desplazada
                          const BoxShadow(
                            color: Color(0xFF6B003A),
                            offset: Offset(0, 4),
                            blurRadius: 0,
                          ),
                          // Resplandor neón magenta
                          BoxShadow(
                            color: const Color(0xFFFF2A85).withOpacity(0.4),
                            blurRadius: 16,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CreateDuelScreen()));
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 18.0),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.flash_on_rounded, color: Colors.white, size: 28),
                                ),
                                const SizedBox(width: 16),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'BUSCAR PARTIDA 1v1 RÁPIDA',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 14.5,
                                          letterSpacing: 1.1,
                                          shadows: [
                                            Shadow(
                                              color: Colors.black45,
                                              offset: Offset(0, 1),
                                              blurRadius: 3,
                                            ),
                                          ],
                                        ),
                                      ),
                                      SizedBox(height: 3),
                                      Text(
                                        'Matchmaking automático entre clientes de Gameros',
                                        style: TextStyle(
                                          color: Color(0xFFF1F5F9),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 18),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // BOTÓN SECUNDARIO: MODO SOLITARIO (Fondo azul noche muy oscuro + Borde Neón Cian)
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0B1024),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: const Color(0xFF00E5FF).withOpacity(0.8),
                          width: 1.4,
                        ),
                        boxShadow: [
                          // Sombra inferior 3D arcade
                          const BoxShadow(
                            color: Color(0xFF03050C),
                            offset: Offset(0, 3),
                            blurRadius: 0,
                          ),
                          // Resplandor neón cian
                          BoxShadow(
                            color: const Color(0xFF00E5FF).withOpacity(0.2),
                            blurRadius: 10,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const TetrisGameScreen(mode: GameMode.solo)),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 14.0),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(7),
                                  decoration: BoxDecoration(
                                    color: const Color(0x1F00E5FF),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.3)),
                                  ),
                                  child: const Icon(Icons.videogame_asset_rounded, color: Color(0xFF00E5FF), size: 24),
                                ),
                                const SizedBox(width: 14),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'MODO SOLITARIO (PRÁCTICA)',
                                        style: TextStyle(
                                          color: Color(0xFFF1F5F9),
                                          fontWeight: FontWeight.w900,
                                          fontSize: 13,
                                          letterSpacing: 0.8,
                                        ),
                                      ),
                                      SizedBox(height: 2),
                                      Text(
                                        'Prueba libre con sonido, cubos dorados y plata',
                                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10.5),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.play_arrow_rounded, color: Color(0xFF00E5FF), size: 22),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // BOTÓN TERCIARIO: GUÍA / TUTORIAL ARCADE (Fondo oscuro + Borde Neón Púrpura)
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: const Color(0xFF090D21),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: const Color(0xFFB388FF).withOpacity(0.75),
                          width: 1.3,
                        ),
                        boxShadow: [
                          const BoxShadow(
                            color: Color(0xFF02040A),
                            offset: Offset(0, 3),
                            blurRadius: 0,
                          ),
                          BoxShadow(
                            color: const Color(0xFFB388FF).withOpacity(0.18),
                            blurRadius: 10,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const TutorialScreen()),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 13.0),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(7),
                                  decoration: BoxDecoration(
                                    color: const Color(0x1FB388FF),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFFB388FF).withOpacity(0.3)),
                                  ),
                                  child: const Icon(Icons.school_rounded, color: Color(0xFFB388FF), size: 22),
                                ),
                                const SizedBox(width: 14),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'GUÍA & ENTRENAMIENTO ARCADE',
                                        style: TextStyle(
                                          color: Color(0xFFF1F5F9),
                                          fontWeight: FontWeight.w900,
                                          fontSize: 12.5,
                                          letterSpacing: 0.8,
                                        ),
                                      ),
                                      SizedBox(height: 2),
                                      Text(
                                        'Aprende SRS, combos, botón Drop y cubos 4x4',
                                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10.5),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFFB388FF), size: 16),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // HEADER HIGH SCORES ARCADE
                    Row(
                      children: [
                        const Icon(Icons.emoji_events_rounded, color: Color(0xFFFACC15), size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'TOP 10 GLOBAL // HIGH SCORES',
                          style: TextStyle(
                            color: const Color(0xFF00E5FF),
                            fontWeight: FontWeight.w900,
                            fontSize: 12.5,
                            letterSpacing: 1.5,
                            shadows: [
                              Shadow(
                                color: const Color(0xFF00E5FF).withOpacity(0.6),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _isLoadingRanking
                        ? const Padding(
                            padding: EdgeInsets.all(24.0),
                            child: CircularProgressIndicator(color: Color(0xFF00E5FF)),
                          )
                        : _top10.isEmpty
                            ? Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16.0),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0B1024),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0xFF1E293B)),
                                ),
                                child: const Center(
                                  child: Text(
                                    'TODAVÍA NO HAY PARTIDAS REGISTRADAS',
                                    style: TextStyle(
                                      color: Color(0xFF94A3B8),
                                      fontSize: 11,
                                      letterSpacing: 1.0,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              )
                            : Column(
                                children: _top10.asMap().entries.map((e) {
                                  final i = e.key;
                                  final entry = e.value;
                                  final isMe = entry.userId == SupabaseConfig.client.auth.currentUser?.id;

                                  // Color de puesto arcade
                                  final rankColor = i == 0
                                      ? const Color(0xFFFACC15) // Oro neón
                                      : i == 1
                                          ? const Color(0xFFE2E8F0) // Plata
                                          : i == 2
                                              ? const Color(0xFFF97316) // Bronce
                                              : const Color(0xFF64748B);

                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 7),
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    decoration: BoxDecoration(
                                      // Fondo translúcido diferenciado para el usuario local
                                      color: isMe
                                          ? const Color(0xFF131D42)
                                          : const Color(0xFF0B1024),
                                      borderRadius: BorderRadius.circular(10),
                                      // Borde neón destacado para el usuario local
                                      border: Border.all(
                                        color: isMe
                                            ? const Color(0xFF00E5FF)
                                            : const Color(0xFF00E5FF).withOpacity(0.18),
                                        width: isMe ? 1.4 : 1.0,
                                      ),
                                      boxShadow: isMe
                                          ? [
                                              BoxShadow(
                                                color: const Color(0xFF00E5FF).withOpacity(0.25),
                                                blurRadius: 10,
                                                offset: const Offset(0, 2),
                                              ),
                                            ]
                                          : [
                                              const BoxShadow(
                                                color: Color(0x33000000),
                                                blurRadius: 4,
                                                offset: Offset(0, 1),
                                              ),
                                            ],
                                    ),
                                    child: Row(
                                      children: [
                                        // Puesto arcade
                                        SizedBox(
                                          width: 32,
                                          child: Text(
                                            '#${(i + 1).toString().padLeft(2, '0')}',
                                            style: TextStyle(
                                              color: rankColor,
                                              fontWeight: FontWeight.w900,
                                              fontSize: 12,
                                              letterSpacing: 0.8,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        // Nombre del jugador en mayúsculas estilo arcade
                                        Expanded(
                                          child: Row(
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  entry.displayName.toUpperCase(),
                                                  style: TextStyle(
                                                    color: isMe ? const Color(0xFF00E5FF) : Colors.white,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w800,
                                                    letterSpacing: 0.8,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              if (isMe) ...[
                                                const SizedBox(width: 6),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFF00E5FF).withOpacity(0.2),
                                                    borderRadius: BorderRadius.circular(4),
                                                    border: Border.all(
                                                      color: const Color(0xFF00E5FF).withOpacity(0.8),
                                                      width: 0.8,
                                                    ),
                                                  ),
                                                  child: const Text(
                                                    'TÚ',
                                                    style: TextStyle(
                                                      color: Color(0xFF00E5FF),
                                                      fontSize: 8.5,
                                                      fontWeight: FontWeight.w900,
                                                      letterSpacing: 0.5,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        // Puntaje en Amarillo Brillante estilo High Score
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: const Color(0x18FACC15),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(
                                              color: const Color(0xFFFACC15).withOpacity(0.4),
                                              width: 0.8,
                                            ),
                                          ),
                                          child: Text(
                                            '${entry.rating} PTS',
                                            style: const TextStyle(
                                              color: Color(0xFFFACC15),
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: 1.0,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pintor para patrón sutil de matriz de Tetris estilo Arcade Neón (5% opacidad)
class _TetrisGridPainter extends CustomPainter {
  final Color gridColor;
  final double cellSize;

  const _TetrisGridPainter({
    this.gridColor = const Color(0x0E00E5FF),
    this.cellSize = 24.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = gridColor
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    for (double x = 0; x <= size.width; x += cellSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += cellSize) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
