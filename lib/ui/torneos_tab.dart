import 'package:flutter/material.dart';
import '../services/tournament_service.dart';
import 'tournament_brackets_screen.dart';

class TorneosTab extends StatefulWidget {
  const TorneosTab({Key? key}) : super(key: key);

  @override
  State<TorneosTab> createState() => _TorneosTabState();
}

class _TorneosTabState extends State<TorneosTab> with SingleTickerProviderStateMixin {
  final TournamentService _service = TournamentService();
  late TabController _tabController;

  List<TournamentModel> _individuales = [];
  List<TournamentModel> _equipos = [];
  List<TournamentInvitationModel> _invitaciones = [];
  Map<String, dynamic>? _clanLiderazgo;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final all = await _service.getTournaments();
      final invites = await _service.getMyInvitations();
      final clan = await _service.getClanLiderazgo();
      if (!mounted) return;
      setState(() {
        _individuales = all.where((t) => t.tipo == 'individual').toList();
        _equipos = all.where((t) => t.tipo == 'equipo').toList();
        _invitaciones = invites;
        _clanLiderazgo = clan;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  Future<void> _inscribirse(TournamentModel t) async {
    final ok = await _service.inscribirseIndividual(t.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok
          ? '¡Inscripción enviada a "${t.nombre}"!'
          : 'No se pudo inscribir (¿ya llegaste al límite de 2 torneos activos?)')),
    );
    _loadData();
  }

  Future<void> _inscribirEquipo(TournamentModel t) async {
    if (_clanLiderazgo == null) return;
    final clanId = _clanLiderazgo!['clan_id'] as String;
    final clanNombre = _clanLiderazgo!['clan_nombre'] as String;
    final res = await _service.inscribirseEquipo(
      tournamentId: t.id,
      clanId: clanId,
      tamanoEquipo: t.tamanoEquipo,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(res['success'] == true
            ? '¡Equipo "$clanNombre" inscrito con éxito en "${t.nombre}"!'
            : 'No se pudo inscribir al equipo: ${res['error'] ?? 'Error desconocido'}'),
        backgroundColor: res['success'] == true ? const Color(0xFF00D26A) : const Color(0xFFDA3633),
      ),
    );
    _loadData();
  }

  Future<void> _responderInvitacion(TournamentInvitationModel inv, bool aceptar) async {
    final ok = await _service.respondToInvitation(inv.id, aceptar);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? (aceptar ? 'Invitación aceptada' : 'Invitación rechazada') : 'No se pudo procesar la invitación')),
    );
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
          child: Row(
            children: [
              const Expanded(
                child: Text('TORNEOS', style: TextStyle(letterSpacing: 1.2, fontWeight: FontWeight.w900, fontSize: 15, color: Colors.white)),
              ),
              IconButton(
                icon: _isLoading
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF5865F2)))
                    : const Icon(Icons.refresh_rounded, color: Color(0xFF5865F2)),
                tooltip: 'Refrescar',
                onPressed: _isLoading ? null : _loadData,
              ),
            ],
          ),
        ),
        if (_error != null)
          Container(
            margin: const EdgeInsets.fromLTRB(14, 4, 14, 0),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF3A1414),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFDA3633)),
            ),
            child: Text(_error!, style: const TextStyle(color: Color(0xFFFFA198), fontSize: 11)),
          ),
        if (_invitaciones.isNotEmpty) _buildInvitationsBanner(),
        Material(
          color: const Color(0xFF080A0F),
          child: TabBar(
            controller: _tabController,
            indicatorColor: const Color(0xFF5865F2),
            labelColor: Colors.white,
            tabs: [
              Tab(text: 'INDIVIDUAL (${_individuales.length})'),
              Tab(text: 'EQUIPOS (${_equipos.length})'),
            ],
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF5865F2)))
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildList(_individuales),
                    _buildList(_equipos),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildInvitationsBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF3A2E12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE3B341)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.mail_rounded, color: Color(0xFFE3B341), size: 16),
              SizedBox(width: 6),
              Text('INVITACIONES A TORNEO', style: TextStyle(color: Color(0xFFE3B341), fontWeight: FontWeight.bold, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 6),
          ..._invitaciones.map((inv) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${inv.torneoNombre ?? 'Torneo'} (${inv.tipo})',
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.check_circle_rounded, color: Color(0xFF00D26A), size: 22),
                      onPressed: () => _responderInvitacion(inv, true),
                    ),
                    IconButton(
                      icon: const Icon(Icons.cancel_rounded, color: Color(0xFFDA3633), size: 22),
                      onPressed: () => _responderInvitacion(inv, false),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildList(List<TournamentModel> list) {
    if (list.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          children: const [
            SizedBox(height: 120),
            Center(
              child: Text('No hay torneos abiertos de Tetris Now por ahora', style: TextStyle(color: Color(0xFF8B949E), fontSize: 12.5)),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(14),
        itemCount: list.length,
        itemBuilder: (context, index) {
          final t = list[index];
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF161B22),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF30363D)),
            ),
            child: Row(
              children: [
                const Icon(Icons.emoji_events_rounded, color: Color(0xFFFFD700), size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.nombre, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13)),
                      const SizedBox(height: 2),
                      Text(t.estado == 'en_curso' ? 'En curso' : 'Inscripción abierta',
                          style: TextStyle(color: t.estado == 'en_curso' ? const Color(0xFF00D26A) : const Color(0xFF38BDF8), fontSize: 10.5)),
                    ],
                  ),
                ),
                if (t.estado == 'en_curso')
                  ElevatedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => TournamentBracketsScreen(tournamentId: t.id)),
                    ),
                    icon: const Icon(Icons.account_tree_rounded, size: 14),
                    label: const Text('VER BRACKET', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E293B),
                      foregroundColor: const Color(0xFF38BDF8),
                      side: const BorderSide(color: Color(0xFF0284C7)),
                    ),
                  )
                else if (t.tipo == 'individual')
                  ElevatedButton(
                    onPressed: () => _inscribirse(t),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF5865F2)),
                    child: const Text('INSCRIBIRME', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  )
                else if (_clanLiderazgo != null)
                  ElevatedButton(
                    onPressed: () => _inscribirEquipo(t),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1)),
                    child: Text('INSCRIBIR (${_clanLiderazgo!['clan_nombre']})',
                        style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold)),
                  )
                else
                  const Text('Solo el líder/co-líder\nde un clan puede inscribir',
                      textAlign: TextAlign.right,
                      style: TextStyle(color: Color(0xFF8B949E), fontSize: 9.5)),
              ],
            ),
          );
        },
      ),
    );
  }
}
