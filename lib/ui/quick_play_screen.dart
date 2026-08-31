import 'dart:async';
import 'package:flutter/material.dart';
import '../core/supabase_config.dart';
import '../game/tetris_types.dart';
import '../services/tetris_match_service.dart';
import '../services/tetris_realtime_service.dart';
import '../services/gameros_profile_service.dart';
import 'tetris_game_screen.dart';
import 'create_duel_screen.dart';
import 'browse_rooms_screen.dart';

/// Pantalla detrás del botón único "JUGAR" (decisión 30/08/2026): activa
/// la búsqueda de matchmaking automático y, al encontrar rival, entra
/// directo a la partida. La sala 1c1 por invitación (crear/buscar por
/// código) queda accesible desde acá como alternativa, no como modo
/// aparte en el menú principal.
class QuickPlayScreen extends StatefulWidget {
  const QuickPlayScreen({Key? key}) : super(key: key);

  @override
  State<QuickPlayScreen> createState() => _QuickPlayScreenState();
}

class _QuickPlayScreenState extends State<QuickPlayScreen> {
  final TetrisMatchService _matchService = TetrisMatchService();
  final GamerosProfileService _profileService = GamerosProfileService();

  bool _buscando = false;
  String? _error;
  Timer? _pollTimer;
  int _segundosBuscando = 0;

  @override
  void dispose() {
    _pollTimer?.cancel();
    if (_buscando) {
      _matchService.cancelarBusqueda();
    }
    super.dispose();
  }

  Future<void> _buscarRival() async {
    final user = SupabaseConfig.client.auth.currentUser;
    if (user == null) {
      setState(() => _error = 'Necesitás iniciar sesión con tu cuenta de Gameros para jugar.');
      return;
    }

    setState(() {
      _buscando = true;
      _error = null;
      _segundosBuscando = 0;
    });

    try {
      final p = await _profileService.getFullProfile();
      final tag = p?.displayName ?? 'Rey-ToRuS';

      final matchId = await _matchService.buscarPartidaAutomatica(tag);
      if (matchId != null) {
        await _entrarAPartidaEncontrada(matchId, tag);
        return;
      }

      // Nadie esperando: queda en cola y hace polling hasta que otro
      // jugador lo empareje a él.
      _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
        if (!mounted) return;
        setState(() => _segundosBuscando += 2);
        try {
          final found = await _matchService.miEstadoMatchmaking();
          if (found != null) {
            _pollTimer?.cancel();
            await _entrarAPartidaEncontrada(found, tag);
          }
        } catch (_) {}
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _buscando = false;
        _error = 'No se pudo iniciar la búsqueda: $e';
      });
    }
  }

  Future<void> _entrarAPartidaEncontrada(String matchId, String tag) async {
    _pollTimer?.cancel();
    try {
      final match = await _matchService.getMatch(matchId);
      final userId = SupabaseConfig.client.auth.currentUser!.id;

      // Averiguar cuál de los dos equipos ya tiene asignado este user_id
      // (tetris.buscar_partida_automatica ya inscribió a ambos jugadores
      // en match_tetris_players al armar la partida).
      final players = await _matchService.getMatchPlayers(matchId);
      final propio = players.firstWhere((p) => p.userId == userId);
      final rival = players.firstWhere((p) => p.userId != userId);

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => TetrisGameScreen(
            matchId: match.id,
            myTeamId: propio.teamId,
            opponentTeamId: rival.teamId,
            realtimeService: TetrisRealtimeService(
              matchId: match.id,
              myTeamId: propio.teamId,
              opponentTeamId: rival.teamId,
              currentUserId: userId,
            )..connect(),
            mode: GameMode.duel1v1,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _buscando = false;
        _error = 'No se pudo entrar a la partida: $e';
      });
    }
  }

  Future<void> _cancelar() async {
    _pollTimer?.cancel();
    try {
      await _matchService.cancelarBusqueda();
    } catch (_) {}
    if (mounted) setState(() => _buscando = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF07090E),
      appBar: AppBar(title: const Text('JUGAR')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_buscando) ...[
                const CircularProgressIndicator(color: Color(0xFF5865F2)),
                const SizedBox(height: 20),
                Text(
                  'Buscando rival... (${_segundosBuscando}s)',
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),
                OutlinedButton(
                  onPressed: _cancelar,
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFFDA3633))),
                  child: const Text('CANCELAR BÚSQUEDA', style: TextStyle(color: Color(0xFFDA3633))),
                ),
              ] else ...[
                if (_error != null) ...[
                  Text(_error!, style: const TextStyle(color: Color(0xFFDA3633)), textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                ],
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _buscarRival,
                    icon: const Icon(Icons.play_arrow_rounded, size: 26),
                    label: const Text('JUGAR', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF238636),
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Row(children: const [
                  Expanded(child: Divider(color: Color(0xFF30363D))),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: Text('O', style: TextStyle(color: Color(0xFF8B949E), fontSize: 11)),
                  ),
                  Expanded(child: Divider(color: Color(0xFF30363D))),
                ]),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const CreateDuelScreen()),
                  ),
                  icon: const Icon(Icons.person_add_alt_1_rounded, color: Color(0xFF38BDF8)),
                  label: const Text('INVITAR A UN AMIGO (SALA PRIVADA)', style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF38BDF8)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const BrowseRoomsScreen()),
                  ),
                  icon: const Icon(Icons.meeting_room_rounded, color: Color(0xFF94A3B8)),
                  label: const Text('TENGO UN CÓDIGO DE SALA', style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF30363D)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
