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

  List<TournamentModel> _misRegistrados = [];
  List<TournamentModel> _individuales = [];
  List<TournamentModel> _equipos = [];
  List<TournamentInvitationModel> _invitaciones = [];
  Map<String, dynamic>? _clanLiderazgo;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final all = await _service.getTournaments();
      final invites = await _service.getMyInvitations();
      final clan = await _service.getClanLiderazgo();
      final registered = await _service.getMyRegisteredTournaments();
      if (!mounted) return;
      setState(() {
        _misRegistrados = registered;
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

  Future<void> _confirmarSalir(TournamentModel t) async {
    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0B1024),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFFF2A85), width: 1.5),
        ),
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFFF2A85), size: 24),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                '¿Salir del torneo?',
                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: 0.5),
              ),
            ),
          ],
        ),
        content: Text(
          '¿Estás seguro de que deseas salir de "${t.nombre}"?\nSe cancelará tu inscripción en este torneo.',
          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('CANCELAR', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF2A85),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('SALIR DEL TORNEO', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11)),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      final ok = await _service.cancelarInscripcion(t.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok
              ? 'Has salido de "${t.nombre}" exitosamente.'
              : 'No se pudo cancelar la inscripción. Inténtalo de nuevo.'),
          backgroundColor: ok ? const Color(0xFF00D26A) : const Color(0xFFDA3633),
        ),
      );
      _loadData();
    }
  }

  bool _isRegistered(String tournamentId) {
    return _misRegistrados.any((t) => t.id == tournamentId);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF070B19),
      child: Stack(
        children: [
          // Cuadrícula sutil tipo matriz de Tetris (5% opacidad)
          Positioned.fill(
            child: CustomPaint(
              painter: const _TetrisGridPainter(),
            ),
          ),
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          const Icon(Icons.emoji_events_rounded, color: Color(0xFFFACC15), size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'TORNEOS',
                            style: TextStyle(
                              letterSpacing: 1.5,
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                              color: Colors.white,
                              shadows: [
                                Shadow(
                                  color: const Color(0xFF00E5FF).withOpacity(0.5),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: _isLoading
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00E5FF)))
                          : const Icon(Icons.refresh_rounded, color: Color(0xFF00E5FF)),
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
                    color: const Color(0x33DA3633),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFF2A85)),
                  ),
                  child: Text(_error!, style: const TextStyle(color: Color(0xFFFFA198), fontSize: 11)),
                ),
              if (_invitaciones.isNotEmpty) _buildInvitationsBanner(),
              // TabBar con línea de luz neón activa (sombra con blur en el borde inferior)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: Color(0x1A00E5FF),
                      width: 1.5,
                    ),
                  ),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicator: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: Color(0xFF00E5FF),
                        width: 3.0,
                      ),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x9900E5FF),
                        blurRadius: 10,
                        spreadRadius: 1,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  indicatorColor: const Color(0xFF00E5FF),
                  labelColor: const Color(0xFF00E5FF),
                  unselectedLabelColor: const Color(0xFF64748B),
                  labelStyle: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                    shadows: [
                      Shadow(
                        color: Color(0x6600E5FF),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                  tabs: [
                    Tab(text: 'MIS TORNEOS (${_misRegistrados.length})'),
                    Tab(text: 'INDIVIDUAL (${_individuales.length})'),
                    Tab(text: 'EQUIPOS (${_equipos.length})'),
                  ],
                ),
              ),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF)))
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          _buildRegisteredList(_misRegistrados),
                          _buildList(_individuales),
                          _buildList(_equipos),
                        ],
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInvitationsBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1024),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFACC15).withOpacity(0.6), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFACC15).withOpacity(0.14),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.mail_rounded, color: Color(0xFFFACC15), size: 16),
              SizedBox(width: 6),
              Text(
                'INVITACIONES A TORNEO',
                style: TextStyle(
                  color: Color(0xFFFACC15),
                  fontWeight: FontWeight.w900,
                  fontSize: 11.5,
                  letterSpacing: 0.8,
                ),
              ),
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
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.check_circle_rounded, color: Color(0xFF00E5FF), size: 22),
                      onPressed: () => _responderInvitacion(inv, true),
                    ),
                    IconButton(
                      icon: const Icon(Icons.cancel_rounded, color: Color(0xFFFF2A85), size: 22),
                      onPressed: () => _responderInvitacion(inv, false),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildRegisteredList(List<TournamentModel> list) {
    if (list.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          children: const [
            SizedBox(height: 100),
            Icon(Icons.emoji_events_outlined, color: Color(0xFF1E293B), size: 48),
            SizedBox(height: 12),
            Center(
              child: Text(
                'No estás registrado en ningún torneo por ahora',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
            SizedBox(height: 6),
            Center(
              child: Text(
                'Explora las pestañas INDIVIDUAL y EQUIPOS para inscribirte.',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
              ),
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
          final isEnCurso = t.estado == 'en_curso';

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0B1024),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isEnCurso
                    ? const Color(0xFFFACC15).withOpacity(0.8)
                    : const Color(0xFF00E5FF).withOpacity(0.4),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: (isEnCurso ? const Color(0xFFFACC15) : const Color(0xFF00E5FF)).withOpacity(0.12),
                  blurRadius: 12,
                  spreadRadius: 0,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Icono en bloque Tetrimino
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFF101735),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: (isEnCurso ? const Color(0xFFFACC15) : const Color(0xFF00E5FF)).withOpacity(0.5),
                          width: 1.4,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (isEnCurso ? const Color(0xFFFACC15) : const Color(0xFF00E5FF)).withOpacity(0.18),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Icon(
                          Icons.emoji_events_rounded,
                          color: isEnCurso ? const Color(0xFFFACC15) : const Color(0xFF00E5FF),
                          size: 24,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.nombre,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13.5),
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isEnCurso ? const Color(0x22FACC15) : const Color(0x2200E5FF),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: isEnCurso ? const Color(0xFFFACC15).withOpacity(0.7) : const Color(0xFF00E5FF).withOpacity(0.6),
                                    width: 0.8,
                                  ),
                                ),
                                child: Text(
                                  isEnCurso ? 'EN CURSO' : 'INSCRIPCIÓN ACTIVA',
                                  style: TextStyle(
                                    color: isEnCurso ? const Color(0xFFFACC15) : const Color(0xFF00E5FF),
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                t.tipo == 'equipo' ? '• Clan' : '• Individual',
                                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (isEnCurso) ...[
                      GestureDetector(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => TournamentBracketsScreen(tournamentId: t.id)),
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF00E5FF), Color(0xFF00B4D8)],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF38BDF8), width: 1),
                            boxShadow: const [
                              BoxShadow(color: Color(0xFF007799), offset: Offset(0, 3)),
                              BoxShadow(color: Color(0x4400E5FF), blurRadius: 6),
                            ],
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.account_tree_rounded, size: 13, color: Color(0xFF070B19)),
                              SizedBox(width: 4),
                              Text(
                                'VER BRACKET',
                                style: TextStyle(
                                  color: Color(0xFF070B19),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    GestureDetector(
                      onTap: () => _confirmarSalir(t),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0x22DA3633),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFFF2A85).withOpacity(0.7), width: 1),
                          boxShadow: const [
                            BoxShadow(color: Color(0xFF551010), offset: Offset(0, 2)),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.logout_rounded, size: 13, color: Color(0xFFFFA198)),
                            SizedBox(width: 4),
                            Text(
                              'SALIR DEL TORNEO',
                              style: TextStyle(
                                color: Color(0xFFFFA198),
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
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
              child: Text(
                'No hay torneos abiertos de Tetris Now por ahora',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5),
              ),
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
          final bool registered = _isRegistered(t.id);

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0B1024),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: registered
                    ? const Color(0xFF00E5FF).withOpacity(0.6)
                    : const Color(0xFF00E5FF).withOpacity(0.25),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: (registered ? const Color(0xFF00E5FF) : const Color(0xFF38BDF8)).withOpacity(0.10),
                  blurRadius: 10,
                  spreadRadius: 0,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                // Icono bloque Tetrimino
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFF101735),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: (registered ? const Color(0xFF00E5FF) : const Color(0xFFFACC15)).withOpacity(0.5),
                      width: 1.4,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: (registered ? const Color(0xFF00E5FF) : const Color(0xFFFACC15)).withOpacity(0.16),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Icon(
                      Icons.emoji_events_rounded,
                      color: registered ? const Color(0xFF00E5FF) : const Color(0xFFFACC15),
                      size: 24,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.nombre, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13)),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Text(
                            t.estado == 'en_curso' ? 'En curso' : 'Inscripción abierta',
                            style: TextStyle(
                              color: t.estado == 'en_curso' ? const Color(0xFFFACC15) : const Color(0xFF00E5FF),
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (registered) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0x2200E5FF),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.6), width: 0.8),
                              ),
                              child: const Text(
                                '✓ INSCRITO',
                                style: TextStyle(color: Color(0xFF00E5FF), fontSize: 8.5, fontWeight: FontWeight.w900),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (registered)
                  GestureDetector(
                    onTap: () => _confirmarSalir(t),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: const Color(0x22DA3633),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFFF2A85).withOpacity(0.6), width: 1),
                        boxShadow: const [
                          BoxShadow(color: Color(0xFF551010), offset: Offset(0, 2)),
                        ],
                      ),
                      child: const Text(
                        'SALIR',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Color(0xFFFFA198)),
                      ),
                    ),
                  )
                else if (t.estado == 'en_curso')
                  GestureDetector(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => TournamentBracketsScreen(tournamentId: t.id)),
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF00E5FF), Color(0xFF00B4D8)],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF38BDF8), width: 1),
                        boxShadow: const [
                          BoxShadow(color: Color(0xFF007799), offset: Offset(0, 3)),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.account_tree_rounded, size: 12, color: Color(0xFF070B19)),
                          SizedBox(width: 3),
                          Text(
                            'BRACKET',
                            style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: Color(0xFF070B19)),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (t.tipo == 'individual')
                  GestureDetector(
                    onTap: () => _inscribirse(t),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFF2A85), Color(0xFFD80064)],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFFF6EB4), width: 1),
                        boxShadow: const [
                          BoxShadow(color: Color(0xFF88003E), offset: Offset(0, 3)),
                          BoxShadow(color: Color(0x44FF2A85), blurRadius: 6),
                        ],
                      ),
                      child: const Text(
                        'INSCRIBIRME',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  )
                else if (_clanLiderazgo != null)
                  GestureDetector(
                    onTap: () => _inscribirEquipo(t),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFF2A85), Color(0xFF9333EA)],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFFF6EB4), width: 1),
                        boxShadow: const [
                          BoxShadow(color: Color(0xFF6B008A), offset: Offset(0, 3)),
                        ],
                      ),
                      child: Text(
                        'INSCRIBIR (${_clanLiderazgo!['clan_nombre']})',
                        style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: Colors.white),
                      ),
                    ),
                  )
                else
                  const Text('Solo líder/co-líder\npuede inscribir',
                      textAlign: TextAlign.right,
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 9.5)),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Pintor para patrón sutil de matriz de Tetris estilo Arcade Neón (5% opacidad)
class _TetrisGridPainter extends CustomPainter {
  final Color gridColor;
  final double cellSize;

  const _TetrisGridPainter({
    this.gridColor = const Color(0x0E00E5FF),
    this.cellSize = 24.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = gridColor
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    for (double x = 0; x <= size.width; x += cellSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += cellSize) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
