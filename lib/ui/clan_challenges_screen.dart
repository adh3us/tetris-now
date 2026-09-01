import 'package:flutter/material.dart';
import 'match_lobby_screen.dart';

class ClanChallengesScreen extends StatefulWidget {
  const ClanChallengesScreen({Key? key}) : super(key: key);

  @override
  State<ClanChallengesScreen> createState() => _ClanChallengesScreenState();
}

class _ClanChallengesScreenState extends State<ClanChallengesScreen> {
  final List<Map<String, dynamic>> _clanWars = [
    {
      'id': 'war_1',
      'myClan': 'CLAN CYBERPUNK',
      'rivalClan': 'TITANES GAMEROS',
      'score': '3 - 2',
      'status': 'EN CURSO',
      'format': '2v2 CO-OP',
    },
    {
      'id': 'war_2',
      'myClan': 'CLAN CYBERPUNK',
      'rivalClan': 'TEAM APEX',
      'score': '5 - 0',
      'status': 'VICTORIA',
      'format': '1v1 DUEL',
    },
    {
      'id': 'war_3',
      'myClan': 'CLAN CYBERPUNK',
      'rivalClan': 'VORTEX ESPORTS',
      'score': '0 - 0',
      'status': 'PENDIENTE',
      'format': '2v2 WIDE MATRIX',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080A0F),
      appBar: AppBar(
        title: const Text('DESAFÍOS DE CLANES (GAMEROS)', style: TextStyle(letterSpacing: 1.2, fontWeight: FontWeight.w900, fontSize: 13)),
        backgroundColor: const Color(0xFF0F141C),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Banner de Clan del Jugador
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1E1B4B), Color(0xFF0F172A)],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF6366F1), width: 1.5),
                boxShadow: const [
                  BoxShadow(color: Color(0x336366F1), blurRadius: 12),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF6366F1)),
                    ),
                    child: const Icon(Icons.shield, color: Color(0xFF818CF8), size: 28),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('TU CLAN: CYBERPUNK', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14)),
                        SizedBox(height: 2),
                        Text('Rango #3 Gameros • 2,450 PTS Clan ELO', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('GUERRAS Y RETOS ACTIVOS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                ElevatedButton.icon(
                  onPressed: _showCreateChallengeDialog,
                  icon: const Icon(Icons.add, size: 14),
                  label: const Text('NUEVO RETO', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
                ),
              ],
            ),
            const SizedBox(height: 12),

            Expanded(
              child: ListView.builder(
                itemCount: _clanWars.length,
                itemBuilder: (context, index) {
                  final war = _clanWars[index];
                  final isLive = war['status'] == 'EN CURSO';
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF161B22),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: isLive ? const Color(0xFF58A6FF) : const Color(0xFF30363D)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('VS ${war['rivalClan']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                            const SizedBox(height: 4),
                            Text('Formato: ${war['format']} • Marcador: ${war['score']}', style: const TextStyle(color: Color(0xFF8B949E), fontSize: 11)),
                          ],
                        ),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const MatchLobbyScreen()),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isLive ? const Color(0xFF238636) : const Color(0xFF21262D),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          child: Text(
                            isLive ? 'JUGAR EN VIVO' : 'VER DETALLES',
                            style: TextStyle(color: isLive ? Colors.white : const Color(0xFF8B949E), fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCreateChallengeDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        title: const Text('LANZAR RETO DE CLAN', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Selecciona el formato de guerra de clanes:', style: TextStyle(color: Color(0xFF8B949E), fontSize: 12)),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MatchLobbyScreen()));
              },
              icon: const Icon(Icons.handshake),
              label: const Text('GUERRA 2v2 CO-OP (TABLERO ANCHO)'),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD29922), foregroundColor: Colors.black),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MatchLobbyScreen()));
              },
              icon: const Icon(Icons.sports_esports),
              label: const Text('DUELO 1v1 MEJOR DE 5', style: TextStyle(color: Colors.white)),
              style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFF30363D))),
            ),
          ],
        ),
      ),
    );
  }
}
