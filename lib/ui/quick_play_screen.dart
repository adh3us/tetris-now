import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../game/tetris_types.dart';
import '../services/gameros_profile_service.dart';
import '../services/tetris_match_service.dart';
import '../services/tetris_realtime_service.dart';
import '../services/presence_service.dart';
import 'tetris_game_screen.dart';

class QuickPlayScreen extends StatefulWidget {
  const QuickPlayScreen({Key? key}) : super(key: key);

  @override
  State<QuickPlayScreen> createState() => _QuickPlayScreenState();
}

class _QuickPlayScreenState extends State<QuickPlayScreen> with SingleTickerProviderStateMixin {
  final TetrisMatchService _matchService = TetrisMatchService();
  final GamerosProfileService _profileService = GamerosProfileService();

  late AnimationController _radarController;
  Timer? _searchTimer;
  Timer? _pollTimer;
  RealtimeChannel? _matchChannel;

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

  void _suscribirCanalMatch(String matchId) {
    if (_matchChannel != null) return;
    try {
      _matchChannel = _matchService.supabase.channel('match:$matchId');
      _matchChannel!.onBroadcast(event: 'match_start', callback: (payload) {
        if (!_isCancelled && mounted) {
          final t1 = payload['team_1_id'] as String?;
          final t2 = payload['team_2_id'] as String?;
          final myT = _myTeamId ?? t1 ?? 'team_1';
          final oppT = myT == t1 ? t2 : t1;
          _entrarAPartida(matchId, myT, opponentTeamId: oppT);
        }
      });
      _matchChannel!.subscribe();
    } catch (_) {}
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
      final oppTeamId = res['opponent_team_id'] as String?;

      _currentMatchId = matchId;
      _myTeamId = teamId;

      if (matchId != null && matchId.isNotEmpty) {
        _suscribirCanalMatch(matchId);
      }

      if (status == 'matched' && matchId != null) {
        _entrarAPartida(matchId, teamId ?? 'team_1', opponentTeamId: oppTeamId);
      } else if (status == 'waiting') {
        _pollTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
          if (_isCancelled) {
            timer.cancel();
            return;
          }
          final pollRes = await _matchService.consultarEstadoMatchmaking(_currentMatchId, _myTeamId ?? 'team_1');
          if (pollRes['status'] == 'matched' && pollRes['match_id'] != null) {
            timer.cancel();
            _entrarAPartida(
              pollRes['match_id'] as String,
              pollRes['team_id'] as String? ?? _myTeamId ?? 'team_1',
              opponentTeamId: pollRes['opponent_team_id'] as String?,
            );
          } else if (pollRes['status'] == 'waiting' && pollRes['match_id'] != null && _currentMatchId == null) {
            _currentMatchId = pollRes['match_id'] as String?;
            if (_currentMatchId != null) {
              _suscribirCanalMatch(_currentMatchId!);
            }
          }
        });
      }
    } catch (e) {
      if (mounted && !_isCancelled) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al conectar con la cola: $e')),
        );
      }
    }
  }

  Future<void> _entrarAPartida(String matchId, String teamId, {String? opponentTeamId}) async {
    _searchTimer?.cancel();
    _pollTimer?.cancel();
    _radarController.stop();
    try {
      _matchChannel?.unsubscribe();
    } catch (_) {}

    _matchService.limpiarMiColaMatchmaking();

    final user = _matchService.supabase.auth.currentUser;
    final userId = user?.id ?? 'guest_player';

    String resolvedOpponentTeam = opponentTeamId ?? '';
    if (resolvedOpponentTeam.isEmpty || resolvedOpponentTeam == teamId) {
      try {
        final matchRow = await _matchService.supabase
            .schema('tetris')
            .from('match_tetris')
            .select('team_1_id, team_2_id')
            .eq('id', matchId)
            .maybeSingle();
        if (matchRow != null) {
          final t1 = matchRow['team_1_id'] as String?;
          final t2 = matchRow['team_2_id'] as String?;
          resolvedOpponentTeam = (teamId == t1 ? t2 : t1) ?? '';
        }
      } catch (_) {}
    }
    if (resolvedOpponentTeam.isEmpty) {
      resolvedOpponentTeam = teamId == 'team_1' ? 'team_2' : 'team_1';
    }

    final realtime = TetrisRealtimeService(
      matchId: matchId,
      myTeamId: teamId,
      opponentTeamId: resolvedOpponentTeam,
      currentUserId: userId,
    );

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => TetrisGameScreen(
            mode: GameMode.duel1v1,
            matchId: matchId,
            myTeamId: teamId,
            opponentTeamId: resolvedOpponentTeam,
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
    try {
      _matchChannel?.unsubscribe();
    } catch (_) {}

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
    try {
      _matchChannel?.unsubscribe();
    } catch (_) {}
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
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Jugador: $_gamerTag',
                    style: const TextStyle(color: Color(0xFF818CF8), fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 6),
                  const UserStatusDot(status: UserPresenceStatus.online, size: 8),
                ],
              ),
              const SizedBox(height: 14),
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
