import 'package:flutter/material.dart';
import '../core/supabase_config.dart';
import '../game/tetris_types.dart';
import '../services/gameros_profile_service.dart';
import 'create_duel_screen.dart';
import 'tetris_game_screen.dart';

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
    return Center(
      child: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Perfil + Rango centrados arriba (spec: "Jugar" muestra el
            // rango centrado).
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF6366F1).withOpacity(0.2),
                border: Border.all(color: const Color(0xFF818CF8), width: 2),
              ),
              child: _profile?.avatarUrl != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(32),
                      child: Image.network(
                        _profile!.avatarUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(Icons.account_circle, size: 44, color: Color(0xFF818CF8)),
                      ),
                    )
                  : const Icon(Icons.account_circle, size: 44, color: Color(0xFF818CF8)),
            ),
            const SizedBox(height: 8),
            if (!widget.isGuest && _profile != null)
              Text(
                _profile!.displayName,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13),
              ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF4F46E5).withOpacity(0.25),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: const Color(0xFF6366F1)),
              ),
              child: Text(
                widget.isGuest ? 'MODO INVITADO' : 'RANGO ${_profile?.tetrisElo ?? 1000}',
                style: const TextStyle(color: Color(0xFFC7D2FE), fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1),
              ),
            ),
            const SizedBox(height: 20),

            // BOTÓN PRINCIPAL: BUSCAR PARTIDA 1v1
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF6366F1), Color(0xFF4338CA)],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFA5B4FC), width: 1.5),
                boxShadow: const [BoxShadow(color: Color(0x666366F1), blurRadius: 20, offset: Offset(0, 6))],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CreateDuelScreen()));
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20.0, vertical: 18.0),
                    child: Row(
                      children: [
                        Icon(Icons.flash_on_rounded, color: Colors.white, size: 28),
                        SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('BUSCAR PARTIDA 1v1 RÁPIDA',
                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 1.1)),
                              SizedBox(height: 3),
                              Text('Matchmaking automático entre clientes de Gameros',
                                  style: TextStyle(color: Color(0xFFE0E7FF), fontSize: 11, fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                        Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 18),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // BOTÓN SECUNDARIO: MODO SOLITARIO
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF334155), width: 1.2),
                boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 10, offset: Offset(0, 3))],
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
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 18.0, vertical: 14.0),
                    child: Row(
                      children: [
                        Icon(Icons.videogame_asset_rounded, color: Color(0xFF38BDF8), size: 24),
                        SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('MODO SOLITARIO (PRÁCTICA)',
                                  style: TextStyle(color: Color(0xFFF1F5F9), fontWeight: FontWeight.w800, fontSize: 13, letterSpacing: 0.8)),
                              SizedBox(height: 2),
                              Text('Prueba libre con sonido, cubos dorados y plata',
                                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10)),
                            ],
                          ),
                        ),
                        Icon(Icons.play_arrow_rounded, color: Color(0xFF38BDF8), size: 20),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 28),

            // TOP 10 GLOBAL (solo Tetris Now, tetris.ratings)
            Align(
              alignment: Alignment.centerLeft,
              child: Text('TOP 10 GLOBAL', style: TextStyle(color: Color(0xFF58A6FF), fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1)),
            ),
            const SizedBox(height: 10),
            _isLoadingRanking
                ? const Padding(
                    padding: EdgeInsets.all(20.0),
                    child: CircularProgressIndicator(color: Color(0xFF5865F2)),
                  )
                : _top10.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text('Todavía no hay partidas registradas', style: TextStyle(color: Color(0xFF8B949E), fontSize: 12)),
                      )
                    : Column(
                        children: _top10.asMap().entries.map((e) {
                          final i = e.key;
                          final entry = e.value;
                          final isMe = entry.userId == SupabaseConfig.client.auth.currentUser?.id;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: isMe ? const Color(0xFF1E1B4B) : const Color(0xFF161B22),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: isMe ? const Color(0xFF6366F1) : const Color(0xFF30363D)),
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 24,
                                  child: Text('#${i + 1}', style: const TextStyle(color: Color(0xFF8B949E), fontWeight: FontWeight.bold, fontSize: 12)),
                                ),
                                Expanded(
                                  child: Text(entry.displayName, style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                                ),
                                Text('${entry.rating} RG', style: const TextStyle(color: Color(0xFFC7D2FE), fontSize: 12, fontWeight: FontWeight.w900)),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
          ],
        ),
      ),
      ),
    );
  }
}
