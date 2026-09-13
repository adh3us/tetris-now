import 'dart:async';
import 'package:flutter/material.dart';
import 'package:gameros_auth_ui/gameros_auth_ui.dart';
import '../core/supabase_config.dart';
import '../game/tetris_types.dart';
import '../services/desafio_service.dart';
import '../services/gameros_profile_service.dart';
import '../services/tetris_match_service.dart';
import '../services/tetris_realtime_service.dart';
import 'amigos_tab.dart';
import 'jugar_tab.dart';
import 'salas_tab.dart';
import 'tetris_game_screen.dart';
import 'tienda_tab.dart';
import 'torneos_tab.dart';

/// Shell de navegación por bloques: Amigos, Jugar, Salas, Torneos, Tienda.
class HomeShell extends StatefulWidget {
  final bool isGuest;
  final VoidCallback? onGuestExit;

  const HomeShell({Key? key, this.isGuest = false, this.onGuestExit}) : super(key: key);

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _currentIndex = 2; // Arranca en "Jugar"

  static const _titles = ['AMIGOS', 'SALAS', 'JUGAR', 'TORNEOS', 'TIENDA'];

  final DesafioService _desafioService = DesafioService();
  final GamerosProfileService _profileService = GamerosProfileService();
  final TetrisMatchService _matchService = TetrisMatchService();
  Timer? _desafioPollTimer;
  final Set<String> _desafiosVistos = {};
  bool _mostrandoDesafio = false;

  @override
  void initState() {
    super.initState();
    if (!widget.isGuest) {
      _desafioPollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _checkIncomingDesafios());
    }
  }

  @override
  void dispose() {
    _desafioPollTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkIncomingDesafios() async {
    if (_mostrandoDesafio) return;
    final myId = SupabaseConfig.client.auth.currentUser?.id;
    if (myId == null) return;

    final desafios = await _desafioService.misDesafios();
    final nuevo = desafios.where((d) => !d.soyRetador && !_desafiosVistos.contains(d.id)).toList();
    if (nuevo.isEmpty) return;

    final d = nuevo.first;
    _desafiosVistos.add(d.id);
    _mostrandoDesafio = true;
    await _showDesafioModal(d);
    _mostrandoDesafio = false;
  }

  Future<void> _showDesafioModal(DesafioModel d) async {
    if (!mounted) return;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      builder: (ctx) => _DesafioIncomingDialog(desafio: d),
    );

    if (result == null) return; // expiró solo
    final gamerTag = (await _profileService.getFullProfile())?.displayName ?? 'Gamer';
    final res = await _desafioService.responderDesafio(d.id, result, gamerTag: gamerTag);
    if (!mounted) return;
    if (result == true && res != null && res['match_id'] != null) {
      final matchId = res['match_id'] as String;
      final myTeamId = res['team_id'] as String;
      final match = await _matchService.getMatch(matchId);
      final opponentTeamId = myTeamId == match.team1Id ? match.team2Id : match.team1Id;
      final userId = SupabaseConfig.client.auth.currentUser?.id ?? 'guest_player';

      final realtime = TetrisRealtimeService(
        matchId: matchId,
        myTeamId: myTeamId,
        opponentTeamId: opponentTeamId,
        currentUserId: userId,
      );

      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TetrisGameScreen(mode: GameMode.duel1v1, matchId: matchId, realtimeService: realtime),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabs = <Widget>[
      AmigosTab(isGuest: widget.isGuest),
      const SalasTab(),
      JugarTab(isGuest: widget.isGuest),
      const TorneosTab(),
      const TiendaTab(),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF07090E),
      appBar: AppBar(
        title: Text(
          _titles[_currentIndex],
          style: const TextStyle(letterSpacing: 2.0, fontWeight: FontWeight.w900, fontSize: 13.5, color: Color(0xFFF1F5F9)),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded, size: 20, color: Color(0xFF94A3B8)),
            tooltip: 'Cerrar Sesión',
            onPressed: () async {
              if (widget.isGuest) {
                widget.onGuestExit?.call();
              } else {
                await GamerosAuthService(supabase: SupabaseConfig.client).signOut();
              }
            },
          ),
        ],
      ),
      body: IndexedStack(index: _currentIndex, children: tabs),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: const Color(0xFF0D111A),
        selectedItemColor: const Color(0xFF818CF8),
        unselectedItemColor: const Color(0xFF64748B),
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.people_alt_rounded), label: 'Amigos'),
          BottomNavigationBarItem(icon: Icon(Icons.meeting_room_rounded), label: 'Salas'),
          BottomNavigationBarItem(icon: Icon(Icons.flash_on_rounded), label: 'Jugar'),
          BottomNavigationBarItem(icon: Icon(Icons.emoji_events_rounded), label: 'Torneos'),
          BottomNavigationBarItem(icon: Icon(Icons.storefront_rounded), label: 'Tienda'),
        ],
      ),
    );
  }
}

/// Modal a pantalla completa (fondo oscurecido, no descartable tocando
/// afuera) que se dispara solo apenas llega un desafío, desde cualquier
/// pantalla de la app. Se cierra sola al vencer los 20 segundos (cuenta
/// como rechazo).
class _DesafioIncomingDialog extends StatefulWidget {
  final DesafioModel desafio;
  const _DesafioIncomingDialog({required this.desafio});

  @override
  State<_DesafioIncomingDialog> createState() => _DesafioIncomingDialogState();
}

class _DesafioIncomingDialogState extends State<_DesafioIncomingDialog> {
  late Timer _timer;
  Duration _restante = Duration.zero;

  @override
  void initState() {
    super.initState();
    _restante = widget.desafio.tiempoRestante;
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      final r = widget.desafio.tiempoRestante;
      if (mounted) setState(() => _restante = r);
      if (r == Duration.zero) {
        _timer.cancel();
        Navigator.of(context).pop(false);
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_restante.inMilliseconds / 20000).clamp(0.0, 1.0);
    return Dialog(
      backgroundColor: const Color(0xFF161B22),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Color(0xFFE3B341), width: 1.5)),
      child: Padding(
        padding: const EdgeInsets.all(22.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.flash_on_rounded, color: Color(0xFFE3B341), size: 42),
            const SizedBox(height: 10),
            const Text('¡TE DESAFIARON A UN 1v1!', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15)),
            const SizedBox(height: 6),
            Text('${_restante.inSeconds}s para responder', style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12)),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: const Color(0xFF30363D),
                valueColor: AlwaysStoppedAnimation(progress > 0.3 ? const Color(0xFF00D26A) : const Color(0xFFDA3633)),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDA3633), padding: const EdgeInsets.symmetric(vertical: 12)),
                    child: const Text('RECHAZAR', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00D26A), padding: const EdgeInsets.symmetric(vertical: 12)),
                    child: const Text('ACEPTAR', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
