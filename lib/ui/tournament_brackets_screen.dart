import 'package:flutter/material.dart';
import '../services/tetris_match_service.dart';
import '../services/tournament_service.dart';

class TournamentBracketsScreen extends StatefulWidget {
  final String tournamentId;

  const TournamentBracketsScreen({Key? key, required this.tournamentId}) : super(key: key);

  @override
  State<TournamentBracketsScreen> createState() => _TournamentBracketsScreenState();
}

class _TournamentBracketsScreenState extends State<TournamentBracketsScreen> {
  final TournamentService _tournamentService = TournamentService();
  List<TetrisMatchModel> _matches = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchMatches();
  }

  Future<void> _fetchMatches() async {
    setState(() => _isLoading = true);
    try {
      final list = await _tournamentService
          .getTournamentMatches(widget.tournamentId)
          .timeout(const Duration(seconds: 3), onTimeout: () => _generateDemoBrackets());

      if (mounted) {
        setState(() {
          _matches = list.isNotEmpty ? list : _generateDemoBrackets();
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

  @override
  Widget build(BuildContext context) {
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
                  const SizedBox(height: 20),

                  const Text('CUARTOS DE FINAL', style: TextStyle(color: Color(0xFF58A6FF), fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1)),
                  const SizedBox(height: 8),
                  ..._matches.where((m) => m.roundNumber == 1).map(_buildMatchCard),
                  const SizedBox(height: 16),

                  const Text('SEMIFINAL', style: TextStyle(color: Color(0xFFE3B341), fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1)),
                  const SizedBox(height: 8),
                  ..._matches.where((m) => m.roundNumber == 2).map(_buildMatchCard),
                  const SizedBox(height: 16),

                  const Text('GRAN FINAL', style: TextStyle(color: Color(0xFF00D26A), fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1)),
                  const SizedBox(height: 8),
                  ..._matches.where((m) => m.roundNumber == 3).map(_buildMatchCard),
                ],
              ),
            ),
    );
  }

  Widget _buildMatchCard(TetrisMatchModel m) {
    final isFinished = m.status == 'finished';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isFinished ? const Color(0xFF238636) : const Color(0xFF30363D)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                m.team1Id,
                style: TextStyle(
                  color: m.winnerTeamId == m.team1Id ? const Color(0xFF00D26A) : Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12.5,
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
              Text(
                m.team2Id,
                style: TextStyle(
                  color: m.winnerTeamId == m.team2Id ? const Color(0xFF00D26A) : Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12.5,
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
