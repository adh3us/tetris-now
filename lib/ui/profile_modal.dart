import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/gameros_profile_service.dart';
import '../services/logros_service.dart';

class HybridProfileModal extends StatefulWidget {
  final GamerosUserProfile? initialProfile;

  const HybridProfileModal({Key? key, this.initialProfile}) : super(key: key);

  static Future<void> show(BuildContext context, {GamerosUserProfile? profile}) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => HybridProfileModal(initialProfile: profile),
    );
  }

  @override
  State<HybridProfileModal> createState() => _HybridProfileModalState();
}

class _HybridProfileModalState extends State<HybridProfileModal> {
  final GamerosProfileService _profileService = GamerosProfileService();
  final LogrosService _logrosService = LogrosService();

  bool _isGamerosView = false;
  bool _isLoading = true;
  GamerosUserProfile? _profile;
  List<LogroItem> _logros = [];

  @override
  void initState() {
    super.initState();
    _profile = widget.initialProfile;
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    setState(() => _isLoading = true);
    try {
      final p = await _profileService.getFullProfile();
      final l = await _logrosService.getLogrosConEstadoUsuario(p?.id);
      if (mounted) {
        setState(() {
          _profile = p ?? _profile;
          _logros = l;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _copiarCodigoAmigo(String code) {
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Color(0xFF00E5FF)),
            const SizedBox(width: 8),
            Text('¡Código #$code copiado al portapapeles!'),
          ],
        ),
        backgroundColor: const Color(0xFF0D1226),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 680),
        decoration: BoxDecoration(
          color: const Color(0xFF070B19),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _isGamerosView ? const Color(0xFFFF007F) : const Color(0xFF00E5FF),
            width: 2.0,
          ),
          boxShadow: [
            BoxShadow(
              color: (_isGamerosView ? const Color(0xFFFF007F) : const Color(0xFF00E5FF)).withOpacity(0.3),
              blurRadius: 24,
              spreadRadius: 2,
            ),
            const BoxShadow(
              color: Color(0xFF000000),
              blurRadius: 30,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            // Cabecera Neón con pestaña / selector de vista
            _buildHeader(),

            // Contenido dinámico con scroll
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: Color(0xFF00E5FF)),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(18),
                      child: _isGamerosView ? _buildGamerosView() : _buildTetrisView(),
                    ),
            ),

            // Pie de modal con botón de cambio de vista
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF0D142E),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        border: Border(
          bottom: BorderSide(
            color: (_isGamerosView ? const Color(0xFFFF007F) : const Color(0xFF00E5FF)).withOpacity(0.4),
            width: 1.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            _isGamerosView ? Icons.hub_rounded : Icons.videogame_asset_rounded,
            color: _isGamerosView ? const Color(0xFFFF007F) : const Color(0xFF00E5FF),
            size: 24,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _isGamerosView ? 'PERFIL DE GAMEROS CORE' : 'PERFIL DE JUGADOR TETRIS',
              style: TextStyle(
                color: _isGamerosView ? const Color(0xFFFF007F) : const Color(0xFF00E5FF),
                fontWeight: FontWeight.w900,
                fontSize: 14,
                letterSpacing: 1.2,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 22),
            onPressed: () => Navigator.of(context).pop(),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // VISTA 1: TETRIS COMPETITIVO (MMR, Stats y Logros)
  // =========================================================================
  Widget _buildTetrisView() {
    final wins = _profile?.tetrisWins ?? 0;
    final losses = _profile?.tetrisLosses ?? 0;
    final total = _profile?.tetrisMatches ?? (wins + losses);
    final winrate = total > 0 ? ((wins / total) * 100).toStringAsFixed(1) : '0.0';
    final elo = _profile?.tetrisElo ?? 1000;

    final logrosDesbloqueados = _logros.where((l) => l.desbloqueado).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Avatar + Gamertag
        Center(
          child: Column(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: const Color(0xFF101735),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF00E5FF), width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00E5FF).withOpacity(0.35),
                      blurRadius: 14,
                    ),
                  ],
                ),
                child: _profile?.avatarUrl != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(_profile!.avatarUrl!, fit: BoxFit.cover),
                      )
                    : const Icon(Icons.sports_esports_rounded, color: Color(0xFF00E5FF), size: 40),
              ),
              const SizedBox(height: 10),
              Text(
                _profile?.displayName ?? 'Jugador',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  letterSpacing: 0.8,
                ),
              ),
              if (_profile?.username != null)
                Text(
                  '@${_profile!.username}',
                  style: const TextStyle(
                    color: Color(0xFF00E5FF),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // Tarjeta principal de MMR
        Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF141E46), Color(0xFF0B1024)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFFFD700), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFFD700).withOpacity(0.2),
                blurRadius: 10,
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Row(
                children: [
                  const Icon(Icons.emoji_events_rounded, color: Color(0xFFFFD700), size: 30),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'RATING ELO / MMR',
                        style: TextStyle(
                          color: Colors.white60,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                        ),
                      ),
                      Text(
                        '$elo PTS',
                        style: const TextStyle(
                          color: Color(0xFFFFD700),
                          fontWeight: FontWeight.w900,
                          fontSize: 20,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                height: 36,
                width: 1,
                color: Colors.white24,
              ),
              Column(
                children: [
                  const Text(
                    'WIN RATE',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                  Text(
                    '$winrate%',
                    style: TextStyle(
                      color: double.tryParse(winrate) != null && double.parse(winrate) >= 50
                          ? const Color(0xFF00E676)
                          : const Color(0xFFFF5252),
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Fila de estadísticas (Partidas, Victorias, Derrotas)
        Row(
          children: [
            _buildStatCard('PARTIDAS', '$total', Colors.white70, const Color(0xFF1A2346)),
            const SizedBox(width: 8),
            _buildStatCard('VICTORIAS', '$wins', const Color(0xFF00E676), const Color(0xFF0A2E1A)),
            const SizedBox(width: 8),
            _buildStatCard('DERROTAS', '$losses', const Color(0xFFFF5252), const Color(0xFF331018)),
          ],
        ),
        const SizedBox(height: 20),

        // Cabecera de Logros
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.military_tech_rounded, color: Color(0xFF00E5FF), size: 20),
                const SizedBox(width: 6),
                const Text(
                  'LOGROS INTERNOS',
                  style: TextStyle(
                    color: Color(0xFF00E5FF),
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
            Text(
              '$logrosDesbloqueados / ${_logros.length}',
              style: const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Lista compacta de logros
        if (_logros.isEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF0E1328),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'No hay logros disponibles en este momento.',
              style: TextStyle(color: Colors.white60, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          )
        else
          ..._logros.map((logro) => _buildLogroTile(logro)).toList(),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, Color textColor, Color bgColor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: textColor.withOpacity(0.3), width: 1),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.white60, fontSize: 9, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(color: textColor, fontWeight: FontWeight.w900, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogroTile(LogroItem logro) {
    final unlocked = logro.desbloqueado;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: unlocked ? const Color(0xFF111B3D) : const Color(0xFF0A0E1F),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: unlocked ? const Color(0xFF00E5FF).withOpacity(0.6) : Colors.white12,
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: unlocked ? const Color(0xFF00E5FF).withOpacity(0.15) : Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: unlocked ? const Color(0xFF00E5FF) : Colors.white24,
                width: 1,
              ),
            ),
            child: Icon(
              _getIconData(logro.icono),
              color: unlocked ? const Color(0xFF00E5FF) : Colors.white24,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        logro.titulo,
                        style: TextStyle(
                          color: unlocked ? Colors.white : Colors.white38,
                          fontWeight: FontWeight.bold,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                    Text(
                      '+${logro.puntos} PTS',
                      style: TextStyle(
                        color: unlocked ? const Color(0xFFFFD700) : Colors.white24,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  logro.descripcion,
                  style: TextStyle(
                    color: unlocked ? Colors.white70 : Colors.white24,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // VISTA 2: PERFIL DE GAMEROS CORE (Soberano en public.usuarios)
  // =========================================================================
  Widget _buildGamerosView() {
    final code = _profile?.codigoJugador ?? 'SIN-CODIGO';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Avatar Gameros con marco Magenta Neón
        Center(
          child: Column(
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: const Color(0xFF2B0A20),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFFF007F), width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF007F).withOpacity(0.4),
                      blurRadius: 18,
                    ),
                  ],
                ),
                child: _profile?.avatarUrl != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.network(_profile!.avatarUrl!, fit: BoxFit.cover),
                      )
                    : const Icon(Icons.person_rounded, color: Color(0xFFFF007F), size: 44),
              ),
              const SizedBox(height: 12),
              Text(
                _profile?.displayName ?? 'Usuario Gameros',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '@${_profile?.username ?? 'jugador'}',
                style: const TextStyle(
                  color: Color(0xFFFF007F),
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Tarjeta Código de Amigo GamerOS con botón para copiar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF180E24),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFF007F).withOpacity(0.6), width: 1.5),
          ),
          child: Row(
            children: [
              const Icon(Icons.qr_code_rounded, color: Color(0xFFFF007F), size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'CÓDIGO DE AMIGO GAMEROS',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                    Text(
                      '#$code',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _copiarCodigoAmigo(code),
                icon: const Icon(Icons.copy_rounded, size: 14, color: Colors.white),
                label: const Text('COPIAR', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF007F),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Información de Clan y Reputación en Gameros Core
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF0F152E),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12, width: 1),
          ),
          child: Column(
            children: [
              _buildGamerosDetailRow(
                Icons.groups_rounded,
                'CLAN OFICIAL',
                _profile?.clanName != null ? '${_profile!.clanName} [${_profile?.clanTag ?? ''}]' : 'Sin clan asignado',
                const Color(0xFF00E5FF),
              ),
              const Divider(color: Colors.white10, height: 20),
              _buildGamerosDetailRow(
                Icons.verified_user_rounded,
                'REPUTACIÓN',
                '${_profile?.reputacion ?? 100}% Juego Limpio',
                const Color(0xFF00E676),
              ),
              const Divider(color: Colors.white10, height: 20),
              _buildGamerosDetailRow(
                Icons.star_rounded,
                'NIVEL DE CUENTA',
                'Nivel ${_profile?.nivel ?? 1}',
                const Color(0xFFFFD700),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Mensaje de aclaración de interoperabilidad
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline_rounded, color: Colors.white38, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Datos sincronizados directamente desde la base central de Gameros (public.usuarios).',
                  style: TextStyle(color: Colors.white38, fontSize: 10),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGamerosDetailRow(IconData icon, String label, String value, Color accentColor) {
    return Row(
      children: [
        Icon(icon, color: accentColor, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold),
              ),
              Text(
                value,
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // =========================================================================
  // BOTÓN INFERIOR: ALTERNAR ENTRE VISTA TETRIS Y VISTA GAMEROS
  // =========================================================================
  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF090E21),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(18)),
        border: Border(
          top: BorderSide(
            color: (_isGamerosView ? const Color(0xFFFF007F) : const Color(0xFF00E5FF)).withOpacity(0.3),
            width: 1.5,
          ),
        ),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 46,
        child: ElevatedButton.icon(
          onPressed: () {
            setState(() {
              _isGamerosView = !_isGamerosView;
            });
          },
          icon: Icon(
            _isGamerosView ? Icons.videogame_asset_rounded : Icons.hub_rounded,
            color: Colors.white,
            size: 18,
          ),
          label: Text(
            _isGamerosView ? 'VOLVER A ESTADÍSTICAS TETRIS' : 'VER PERFIL DE GAMEROS CORE',
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.0,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: _isGamerosView ? const Color(0xFF00E5FF) : const Color(0xFFFF007F),
            foregroundColor: _isGamerosView ? Colors.black : Colors.white,
            elevation: 8,
            shadowColor: (_isGamerosView ? const Color(0xFF00E5FF) : const Color(0xFFFF007F)).withOpacity(0.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ),
    );
  }

  IconData _getIconData(String name) {
    switch (name) {
      case 'flash_on':
        return Icons.flash_on_rounded;
      case 'bolt':
        return Icons.bolt_rounded;
      case 'whatshot':
        return Icons.whatshot_rounded;
      case 'star':
        return Icons.star_rounded;
      case 'shield':
        return Icons.shield_rounded;
      case 'sports_esports':
        return Icons.sports_esports_rounded;
      case 'emoji_events':
        return Icons.emoji_events_rounded;
      case 'military_tech':
        return Icons.military_tech_rounded;
      case 'health_and_safety':
        return Icons.health_and_safety_rounded;
      case 'autorenew':
        return Icons.autorenew_rounded;
      default:
        return Icons.military_tech_rounded;
    }
  }
}
