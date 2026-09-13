import 'package:flutter/material.dart';
import '../core/supabase_config.dart';
import '../services/tetris_match_service.dart';
import '../services/tetris_realtime_service.dart';
import '../services/tournament_service.dart';
import 'tetris_game_screen.dart';

class TournamentBracketsScreen extends StatefulWidget {
  final String tournamentId;

  const TournamentBracketsScreen({Key? key, required this.tournamentId}) : super(key: key);

  @override
  State<TournamentBracketsScreen> createState() => _TournamentBracketsScreenState();
}

class _TournamentBracketsScreenState extends State<TournamentBracketsScreen> {
  final TournamentService _tournamentService = TournamentService();
  List<TetrisMatchModel> _matches = [];
  MyTournamentMatch? _myPendingMatch;
  bool _isLoading = true;
  bool _isLaunching = false;

  @override
  void initState() {
    super.initState();
    _fetchMatches();
  }

  Future<void> _fetchMatches() async {
    setState(() => _isLoading = true);
    try {
      final matchesFuture = _tournamentService
          .getTournamentMatches(widget.tournamentId)
          .timeout(const Duration(seconds: 4), onTimeout: () => []);

      final myMatchFuture = _tournamentService
          .getMyPendingTournamentMatch(widget.tournamentId)
          .timeout(const Duration(seconds: 4), onTimeout: () => null);

      final results = await Future.wait([matchesFuture, myMatchFuture]);
      final list = results[0] as List<TetrisMatchModel>;
      final myMatch = results[1] as MyTournamentMatch?;

      if (mounted) {
        setState(() {
          _matches = list.isNotEmpty ? list : _generateDemoBrackets();
          _myPendingMatch = myMatch;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _matches = _generateDemoBrackets();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _jugarCruce(MyTournamentMatch cruce) async {
    if (_isLaunching) return;
    setState(() => _isLaunching = true);

    try {
      final res = await _tournamentService.prepararOUnirseACruceTorneo(cruce);
      final currentUserId = SupabaseConfig.client.auth.currentUser?.id ?? 'guest_player';

      final realtime = TetrisRealtimeService(
        matchId: res['match_id'] as String,
        myTeamId: res['my_team_id'] as String,
        opponentTeamId: res['opponent_team_id'] as String,
        currentUserId: currentUserId,
      );

      if (!mounted) return;
      setState(() => _isLaunching = false);

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TetrisGameScreen(
            mode: GameMode.duel1v1,
            matchId: res['match_id'] as String,
            myTeamId: res['my_team_id'] as String,
            opponentTeamId: res['opponent_team_id'] as String,
            tournamentId: cruce.tournamentId,
            torneoPartidaId: res['torneo_partida_id'] as String?,
            myInscripcionId: res['my_inscripcion_id'] as String?,
            opponentInscripcionId: res['opponent_inscripcion_id'] as String?,
            realtimeService: realtime,
          ),
        ),
      );

      _fetchMatches();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLaunching = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al entrar al cruce: $e'),
          backgroundColor: const Color(0xFFDA3633),
        ),
      );
    }
  }

  List<TetrisMatchModel> _generateDemoBrackets() {
    return [
      TetrisMatchModel(
        id: 'qf_1',
        roundNumber: 1,
        format: '1v1',
        status: 'finished',
        team1Id: 'Rey-ToRuS',
        team2Id: 'ShadowGamer',
        winnerTeamId: 'Rey-ToRuS',
        team1LinesSent: 24,
        team2LinesSent: 18,
      ),
      TetrisMatchModel(
        id: 'qf_2',
        roundNumber: 1,
        format: '1v1',
        status: 'finished',
        team1Id: 'Lucas (Gameros)',
        team2Id: 'Vortex_99',
        winnerTeamId: 'Lucas (Gameros)',
        team1LinesSent: 20,
        team2LinesSent: 14,
      ),
      TetrisMatchModel(
        id: 'sf_1',
        roundNumber: 2,
        format: '1v1',
        status: 'pending',
        team1Id: 'Rey-ToRuS',
        team2Id: 'Lucas (Gameros)',
      ),
      TetrisMatchModel(
        id: 'final_match',
        roundNumber: 3,
        format: '1v1',
        status: 'pending',
        team1Id: 'Por definir',
        team2Id: 'Por definir',
      ),
    ];
  }

  String _getRoundTitle(int round, List<int> allRounds) {
    if (allRounds.isEmpty) return 'RONDA $round';
    if (round == allRounds.last) return 'GRAN FINAL';
    if (allRounds.length >= 2 && round == allRounds[allRounds.length - 2]) return 'SEMIFINAL';
    if (round == 1) return 'CUARTOS DE FINAL';
    return 'RONDA $round';
  }

  Color _getRoundColor(int round, List<int> allRounds) {
    if (round == allRounds.last) return const Color(0xFF00D26A);
    if (allRounds.length >= 2 && round == allRounds[allRounds.length - 2]) return const Color(0xFFE3B341);
    return const Color(0xFF58A6FF);
  }

  @override
  Widget build(BuildContext context) {
    final roundNumbers = _matches.map((m) => m.roundNumber).toSet().toList()..sort();

    return Scaffold(
      backgroundColor: const Color(0xFF080A0F),
      appBar: AppBar(
        title: const Text('ÁRBOL DE TORNEO (BRACKETS)', style: TextStyle(letterSpacing: 1.5, fontWeight: FontWeight.w900, fontSize: 13.5)),
        backgroundColor: const Color(0xFF0F141C),
        centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.refresh, color: Color(0xFF5865F2)), onPressed: _fetchMatches),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF5865F2)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Banner informativo del torneo
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF1E1B4B), Color(0xFF0F172A)]),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF6366F1)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.emoji_events_rounded, color: Color(0xFFFFD700), size: 32),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('TORNEO OFICIAL GAMEROS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13)),
                              Text('Doble eliminación • Físicas The New Tetris • ELO K=32', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // TU PRÓXIMO CRUCE (si existe partida pendiente para el usuario)
                  if (_myPendingMatch != null) ...[
                    const SizedBox(height: 16),
                    _buildMyPendingMatchBanner(_myPendingMatch!),
                  ],

                  const SizedBox(height: 20),

                  // Secciones de Rondas
                  for (final r in roundNumbers) ...[
                    Text(
                      _getRoundTitle(r, roundNumbers),
                      style: TextStyle(
                        color: _getRoundColor(r, roundNumbers),
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ..._matches.where((m) => m.roundNumber == r).map(_buildMatchCard),
                    const SizedBox(height: 16),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildMyPendingMatchBanner(MyTournamentMatch match) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E3A8A), Color(0xFF064E3B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF10B981), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF10B981).withOpacity(0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF10B981)),
                ),
                child: Text(
                  '⚔️ TU PRÓXIMO CRUCE • RONDA ${match.roundNumber}',
                  style: const TextStyle(
                    color: Color(0xFF6EE7B7),
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              const Spacer(),
              const Icon(Icons.flash_on_rounded, color: Color(0xFFFFD700), size: 20),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Rival: ${match.opponentGamerTag}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'El resultado se auto-reportará automáticamente al bracket de Gameros al finalizar la partida.',
            style: TextStyle(color: Color(0xFFD1D5DB), fontSize: 11),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              onPressed: _isLaunching ? null : () => _jugarCruce(match),
              icon: _isLaunching
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.sports_esports_rounded, size: 22),
              label: Text(
                _isLaunching ? 'CONECTANDO AL CRUCE...' : '🎮 JUGAR MI CRUCE AHORA',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  letterSpacing: 1,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF059669),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMatchCard(TetrisMatchModel m) {
    final isFinished = m.status == 'finished';
    final isMyMatch = _myPendingMatch != null &&
        (_myPendingMatch!.matchId == m.id ||
            (_myPendingMatch!.torneoPartidaId != null &&
                _myPendingMatch!.torneoPartidaId == m.torneoPartidaId));

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isMyMatch ? const Color(0xFF172554) : const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isMyMatch
              ? const Color(0xFF3B82F6)
              : (isFinished ? const Color(0xFF238636) : const Color(0xFF30363D)),
          width: isMyMatch ? 1.8 : 1.0,
        ),
      ),
      child: Column(
        children: [
          if (isMyMatch) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B82F6).withOpacity(0.25),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    '🎯 TU PARTIDA',
                    style: TextStyle(color: Color(0xFF93C5FD), fontSize: 9.5, fontWeight: FontWeight.bold),
                  ),
                ),
                if (!isFinished)
                  TextButton.icon(
                    onPressed: _isLaunching ? null : () => _jugarCruce(_myPendingMatch!),
                    icon: const Icon(Icons.play_arrow_rounded, size: 16, color: Color(0xFF60A5FA)),
                    label: const Text('JUGAR', style: TextStyle(color: Color(0xFF60A5FA), fontSize: 11, fontWeight: FontWeight.bold)),
                    style: TextButton.styleToFlat(),
                  ),
              ],
            ),
            const SizedBox(height: 6),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  m.team1Id,
                  style: TextStyle(
                    color: m.winnerTeamId == m.team1Id ? const Color(0xFF00D26A) : Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isFinished)
                Text('${m.team1LinesSent} L', style: const TextStyle(color: Color(0xFF58A6FF), fontSize: 11, fontWeight: FontWeight.bold)),
            ],
          ),
          const Divider(color: Color(0xFF30363D), height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  m.team2Id,
                  style: TextStyle(
                    color: m.winnerTeamId == m.team2Id ? const Color(0xFF00D26A) : Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isFinished)
                Text('${m.team2LinesSent} L', style: const TextStyle(color: Color(0xFF58A6FF), fontSize: 11, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }
}

extension on TextButton {
  static ButtonStyle styleToFlat() {
    return TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
      minimumSize: const Size(0, 24),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

