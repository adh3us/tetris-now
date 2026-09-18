import 'dart:async';
import 'package:flutter/material.dart';
import '../game/tetris_types.dart';
import '../services/gameros_profile_service.dart';
import '../services/tetris_match_service.dart';
import '../services/tetris_realtime_service.dart';
import 'tetris_game_screen.dart';

/// Pantalla Oficial de Búsqueda Rápida 1v1 (Matchmaking Automático Gameros)
class CreateDuelScreen extends StatefulWidget {
  const CreateDuelScreen({Key? key}) : super(key: key);

  @override
  State<CreateDuelScreen> createState() => _CreateDuelScreenState();
}

/// Alias para compatibilidad de rutas
class QuickPlayScreen extends CreateDuelScreen {
  const QuickPlayScreen({Key? key}) : super(key: key);
}

class _CreateDuelScreenState extends State<CreateDuelScreen> with SingleTickerProviderStateMixin {
  final TetrisMatchService _matchService = TetrisMatchService();
  final GamerosProfileService _profileService = GamerosProfileService();

  late AnimationController _radarController;
  Timer? _searchTimer;
  Timer? _pollTimer;

  int _searchSeconds = 0;
  String? _currentMatchId;
  String? _myTeamId;
  String _gamerTag = 'Gamer';
  String? _avatarUrl;
  bool _isCancelled = false;

  @override
  void initState() {
    super.initState();
    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _iniciarBusqueda();
  }

  Future<void> _iniciarBusqueda() async {
    final profile = await _profileService.getFullProfile();
    if (profile != null) {
      _gamerTag = profile.displayName;
      _avatarUrl = profile.avatarUrl;
      if (mounted) setState(() {});
    }

    _searchTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (mounted) setState(() => _searchSeconds++);
    });

    try {
      final res = await _matchService.buscarPartidaRapida(_gamerTag);
      if (_isCancelled) return;

      final status = res['status'] as String?;
      final matchId = res['match_id'] as String?;
      final teamId = res['team_id'] as String?;

      _currentMatchId = matchId;
      _myTeamId = teamId;

      if (status == 'matched' && matchId != null) {
        _entrarAPartida(matchId, teamId ?? 'team_1');
      } else if (status == 'waiting') {
        // Polling cada 2 segundos esperando a que ingrese el rival
        _pollTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
          if (_isCancelled) {
            timer.cancel();
            return;
          }
          final pollRes = await _matchService.consultarEstadoMatchmaking(_currentMatchId, _myTeamId ?? 'team_1');
          if (pollRes['status'] == 'matched' && pollRes['match_id'] != null) {
            timer.cancel();
            _entrarAPartida(pollRes['match_id'] as String, pollRes['team_id'] as String? ?? _myTeamId ?? 'team_1');
          }
        });
      }
    } catch (e) {
      if (mounted && !_isCancelled) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error en la cola de emparejamiento: $e')),
        );
      }
    }
  }

  void _entrarAPartida(String matchId, String teamId) {
    _searchTimer?.cancel();
    _pollTimer?.cancel();
    _radarController.stop();

    final user = _matchService.supabase.auth.currentUser;
    final userId = user?.id ?? 'guest_player';

    final realtime = TetrisRealtimeService(
      matchId: matchId,
      myTeamId: teamId,
      opponentTeamId: teamId == 'team_1' ? 'team_2' : 'team_1',
      currentUserId: userId,
    );

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => TetrisGameScreen(
            mode: GameMode.duel1v1,
            matchId: matchId,
            realtimeService: realtime,
          ),
        ),
      );
    }
  }

  void _cancelarYSalir() async {
    _isCancelled = true;
    _searchTimer?.cancel();
    _pollTimer?.cancel();
    _radarController.stop();

    await _matchService.cancelarBusqueda(_currentMatchId);

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _isCancelled = true;
    _searchTimer?.cancel();
    _pollTimer?.cancel();
    _radarController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final minutes = (_searchSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_searchSeconds % 60).toString().padLeft(2, '0');

    return Scaffold(
      backgroundColor: const Color(0xFF080A0F),
      appBar: AppBar(
        title: const Text(
          'MATCHMAKING 1v1 GAMEROS',
          style: TextStyle(letterSpacing: 2.0, fontWeight: FontWeight.w900, fontSize: 13),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF0D111A),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Radar Animado Neón
              RotationTransition(
                turns: _radarController,
                child: Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: SweepGradient(
                      colors: [
                        const Color(0xFF6366F1).withOpacity(0.0),
                        const Color(0xFF6366F1).withOpacity(0.25),
                        const Color(0xFF38BDF8).withOpacity(0.85),
                      ],
                    ),
                  ),
                  child: Center(
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF0F172A),
                        border: Border.all(color: const Color(0xFF818CF8), width: 2),
                        boxShadow: const [
                          BoxShadow(color: Color(0x556366F1), blurRadius: 16),
                        ],
                      ),
                      child: _avatarUrl != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(40),
                              child: Image.network(
                                _avatarUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(Icons.person, color: Color(0xFF818CF8), size: 44),
                              ),
                            )
                          : const Icon(Icons.person, color: Color(0xFF818CF8), size: 44),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),

              // Texto Estado
              const Text(
                'BUSCANDO RIVAL EN GAMEROS...',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Jugador: $_gamerTag',
                style: const TextStyle(color: Color(0xFF818CF8), fontSize: 13, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 14),

              // Contador de Tiempo en cola
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1B4B).withOpacity(0.5),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF6366F1)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.timer_outlined, size: 16, color: Color(0xFF38BDF8)),
                    const SizedBox(width: 8),
                    Text(
                      'Tiempo en cola: $minutes:$seconds',
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 36),

              // Botón Cancelar Búsqueda
              OutlinedButton.icon(
                onPressed: _cancelarYSalir,
                icon: const Icon(Icons.close_rounded, color: Color(0xFFEF4444)),
                label: const Text(
                  'CANCELAR BÚSQUEDA',
                  style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold, letterSpacing: 1),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
