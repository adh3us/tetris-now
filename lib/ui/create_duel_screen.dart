import 'package:flutter/material.dart';
import '../services/tetris_match_service.dart';
import '../services/gameros_profile_service.dart';
import 'match_lobby_screen.dart';

class CreateDuelScreen extends StatefulWidget {
  const CreateDuelScreen({Key? key}) : super(key: key);

  @override
  State<CreateDuelScreen> createState() => _CreateDuelScreenState();
}

class _CreateDuelScreenState extends State<CreateDuelScreen> {
  final TetrisMatchService _matchService = TetrisMatchService();
  final GamerosProfileService _profileService = GamerosProfileService();
  bool _isLoading = false;

  final TextEditingController _roomNameController = TextEditingController(text: 'Duelo 1c1 de Rey-ToRuS');
  final TextEditingController _passwordController = TextEditingController();
  bool _allowSpectators = true;
  bool _isPasswordProtected = false;

  @override
  void initState() {
    super.initState();
    _loadDefaultName();
  }

  Future<void> _loadDefaultName() async {
    try {
      final p = await _profileService.getFullProfile();
      if (p != null && mounted) {
        setState(() {
          _roomNameController.text = 'Duelo 1c1 de ${p.displayName}';
        });
      }
    } catch (_) {}
  }

  void _showCreate1v1Dialog() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          backgroundColor: const Color(0xFF161B22),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF5865F2), width: 1.5),
          ),
          title: const Row(
            children: [
              Icon(Icons.sports_esports, color: Color(0xFF5865F2), size: 24),
              SizedBox(width: 10),
              Text('CONFIGURAR SALA 1c1', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Nombre de la Sala:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                TextField(
                  controller: _roomNameController,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFF0D1117),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF30363D))),
                  ),
                ),
                const SizedBox(height: 14),

                // Switch Contraseña / Sala Privada
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Sala Privada (con Contraseña):', style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600)),
                    Switch(
                      value: _isPasswordProtected,
                      activeColor: const Color(0xFF5865F2),
                      onChanged: (val) {
                        setModalState(() => _isPasswordProtected = val);
                      },
                    ),
                  ],
                ),
                if (_isPasswordProtected) ...[
                  const SizedBox(height: 4),
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Ingresa la contraseña de la sala',
                      hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
                      filled: true,
                      fillColor: const Color(0xFF0D1117),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF30363D))),
                    ),
                  ),
                ],
                const SizedBox(height: 10),

                // Switch Espectador / Árbitro / Juez
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Permitir Espectadores / Árbitros:', style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600)),
                          Text('Veedores de Gameros pueden observar', style: TextStyle(color: Color(0xFF8B949E), fontSize: 9.5)),
                        ],
                      ),
                    ),
                    Switch(
                      value: _allowSpectators,
                      activeColor: const Color(0xFF00D26A),
                      onChanged: (val) {
                        setModalState(() => _allowSpectators = val);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('CANCELAR', style: TextStyle(color: Color(0xFF8B949E))),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                _createAndEnterRoom();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF5865F2),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('CREAR Y ENTRAR', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createAndEnterRoom() async {
    setState(() => _isLoading = true);
    final user = _matchService.supabase.auth.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Necesitás iniciar sesión con tu cuenta de Gameros para crear una sala.'),
          backgroundColor: Color(0xFFDA3633),
        ));
      }
      return;
    }

    try {
      final p = await _profileService.getFullProfile();
      final tag = p?.displayName ?? 'Rey-ToRuS';

      // team1Id/team2Id quedan null: createMatch genera UUIDs válidos
      // (las columnas team_1_id/team_2_id son UUID en la base; pasar
      // strings como "team_alpha_<id>" rompía el insert).
      final match = await _matchService.createMatch(
        format: '1v1',
        roomName: _roomNameController.text.trim(),
        password: _isPasswordProtected ? _passwordController.text.trim() : null,
        allowSpectators: _allowSpectators,
      );

      await _matchService.joinMatch(
        matchId: match.id,
        teamId: match.team1Id,
        gamerTag: tag,
      );

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => MatchLobbyScreen(
              initialMatchId: match.id,
              isHost: true,
              hostTeamId: match.team1Id,
              hostOpponentTeamId: match.team2Id,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al crear sala: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080A0F),
      appBar: AppBar(
        title: const Text('CREAR DUELOS', style: TextStyle(letterSpacing: 1.5, fontWeight: FontWeight.w900, fontSize: 13.5)),
        backgroundColor: const Color(0xFF0F141C),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF5865F2)))
          : Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.flash_on_rounded, size: 54, color: Color(0xFF5865F2)),
                  const SizedBox(height: 10),
                  const Text(
                    'MODALIDADES DE DUELO',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: 1),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Crea tu sala personalizada y desafía a rivales de Gameros',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF8B949E), fontSize: 11),
                  ),
                  const SizedBox(height: 24),

                  // 1. Duelo Individual 1c1
                  _buildOptionCard(
                    title: 'DUELO INDIVIDUAL 1c1',
                    subtitle: 'Configura nombre, contraseña y árbitros/espectadores',
                    icon: Icons.person_rounded,
                    color: const Color(0xFF5865F2),
                    badgeText: 'DISPONIBLE',
                    badgeColor: const Color(0xFF00D26A),
                    onTap: _showCreate1v1Dialog,
                  ),
                  const SizedBox(height: 14),

                  // 2. Duelo 2c2 (Próximamente)
                  _buildOptionCard(
                    title: 'DUELO EN EQUIPO 2c2',
                    subtitle: 'Combate en parejas (Modo en desarrollo y optimización)',
                    icon: Icons.group_rounded,
                    color: const Color(0xFF161B22),
                    borderColor: const Color(0xFF30363D),
                    badgeText: 'PRÓXIMAMENTE',
                    badgeColor: const Color(0xFFD29922),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('El modo 2c2 se encuentra actualmente en fase de optimización y pruebas.'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildOptionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    Color? borderColor,
    required String badgeText,
    required Color badgeColor,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
        border: borderColor != null ? Border.all(color: borderColor) : null,
        boxShadow: [
          BoxShadow(color: color.withOpacity(0.25), blurRadius: 10, offset: const Offset(0, 3)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Icon(icon, color: Colors.white, size: 26),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12.5)),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: badgeColor.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: badgeColor, width: 0.8),
                            ),
                            child: Text(badgeText, style: TextStyle(color: badgeColor, fontSize: 8, fontWeight: FontWeight.w900)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(subtitle, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10)),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 14),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
