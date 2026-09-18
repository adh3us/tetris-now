import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/friends_service.dart';
import '../services/desafio_service.dart';
import '../services/gameros_profile_service.dart';
import '../services/tetris_match_service.dart';
import '../services/tetris_realtime_service.dart';
import '../core/supabase_config.dart';
import '../game/tetris_types.dart';
import 'profile_modal.dart';
import 'tetris_game_screen.dart';

class FriendsScreen extends StatefulWidget {
  /// Si es true, se muestra sin su propio Scaffold/AppBar (para usarse
  /// embebido dentro de la pestaña "Amigos" del shell de navegación).
  final bool embedded;

  const FriendsScreen({Key? key, this.embedded = false}) : super(key: key);

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> with SingleTickerProviderStateMixin {
  final FriendsService _friendsService = FriendsService();
  final DesafioService _desafioService = DesafioService();
  final GamerosProfileService _profileService = GamerosProfileService();
  final TetrisMatchService _matchService = TetrisMatchService();
  late TabController _tabController;

  List<FriendModel> _friends = [];
  List<FriendRequestModel> _requests = [];
  List<DesafioModel> _desafios = [];
  GamerosUserProfile? _profile;
  bool _isLoading = true;
  Timer? _desafiosPollTimer;
  Timer? _esperandoRivalTimer;
  bool _isEnteringMatch = false;
  bool _isPollingMatch = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
    if (widget.embedded) _loadProfile();
    _desafiosPollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _loadDesafios());
  }

  @override
  void dispose() {
    _desafiosPollTimer?.cancel();
    _esperandoRivalTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final p = await _profileService.getFullProfile();
      if (p != null && mounted) setState(() => _profile = p);
    } catch (_) {}
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final f = await _friendsService.getFriends();
      final r = await _friendsService.getPendingRequests();
      final d = await _desafioService.misDesafios();
      if (mounted) {
        setState(() {
          _friends = f;
          _requests = r;
          _desafios = d;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadDesafios() async {
    final d = await _desafioService.misDesafios();
    if (mounted) setState(() => _desafios = d);
  }

  Future<void> _desafiar(FriendModel friend) async {
    final gamerTag = _profile?.displayName ?? 'Gamer';
    final res = await _desafioService.crearDesafio(friend.userId, gamerTag);
    if (!mounted) return;
    if (res == null || res['match_id'] == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo enviar el desafío')),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('¡Desafío enviado a ${friend.gamerTag}! Tiene 20 segundos para aceptar.')),
    );

    final matchId = res['match_id'] as String;
    final myTeamId = res['team_id'] as String;
    _esperarRivalYEntrar(matchId, myTeamId);
  }

  /// El retador espera a que el retado acepte (o expire), sondeando el
  /// estado real del match — igual que hace CreateDuelScreen con el
  /// matchmaking automático. No usa MatchLobbyScreen porque esa pantalla
  /// siempre te trata como invitado (team_2), y acá el retador ya es team_1.
  void _esperarRivalYEntrar(String matchId, String myTeamId) {
    _esperandoRivalTimer?.cancel();
    _isPollingMatch = false;
    _esperandoRivalTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (_isEnteringMatch) {
        timer.cancel();
        return;
      }
      if (_isPollingMatch) return;
      _isPollingMatch = true;

      try {
        final estado = await _matchService.consultarEstadoMatch(matchId, myTeamId);
        if (estado['status'] == 'matched') {
          timer.cancel();
          _esperandoRivalTimer?.cancel();
          await _entrarAPartida(matchId, myTeamId);
        }
      } finally {
        _isPollingMatch = false;
      }
    });
  }

  Future<void> _entrarAPartida(String matchId, String myTeamId) async {
    if (!mounted || _isEnteringMatch) return;
    _isEnteringMatch = true;
    _esperandoRivalTimer?.cancel();

    try {
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
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TetrisGameScreen(
            mode: GameMode.duel1v1,
            matchId: matchId,
            myTeamId: myTeamId,
            opponentTeamId: opponentTeamId,
            realtimeService: realtime,
          ),
        ),
      );
    } finally {
      if (mounted) {
        _isEnteringMatch = false;
      }
    }
  }

  Future<void> _responderDesafio(DesafioModel d, bool aceptar) async {
    final gamerTag = _profile?.displayName ?? 'Gamer';
    final res = await _desafioService.responderDesafio(d.id, aceptar, gamerTag: gamerTag);
    if (!mounted) return;
    if (res != null && aceptar && res['match_id'] != null) {
      await _entrarAPartida(res['match_id'] as String, res['team_id'] as String);
    }
    _loadDesafios();
  }

  void _showAddFriendDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _AddFriendDialog(friendsService: _friendsService, onSent: _loadData),
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = Column(
      children: [
        _buildEloHeader(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'AMIGOS Y SOCIAL',
                  style: TextStyle(
                    letterSpacing: 2.0,
                    fontWeight: FontWeight.w900,
                    fontSize: 13.5,
                    color: Colors.white,
                    shadows: [
                      Shadow(
                        color: const Color(0xFF00E5FF).withOpacity(0.55),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.4)),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00E5FF).withOpacity(0.12),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: IconButton(
                  icon: const Icon(Icons.person_add_rounded, color: Color(0xFF00E5FF), size: 20),
                  onPressed: _showAddFriendDialog,
                  tooltip: 'Agregar Amigo',
                ),
              ),
            ],
          ),
        ),
        Material(color: Colors.transparent, child: _buildTabBar()),
        Expanded(child: _buildTabView()),
      ],
    );

    if (widget.embedded) {
      return Container(
        color: const Color(0xFF070B19),
        child: CustomPaint(
          painter: const TetrisGridPainter(),
          child: content,
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF070B19),
      appBar: AppBar(
        title: Text(
          'AMIGOS Y SOCIAL',
          style: TextStyle(
            letterSpacing: 2.0,
            fontWeight: FontWeight.w900,
            fontSize: 14,
            color: Colors.white,
            shadows: [
              Shadow(
                color: const Color(0xFF00E5FF).withOpacity(0.6),
                blurRadius: 8,
              ),
            ],
          ),
        ),
        backgroundColor: const Color(0xFF0B1024),
        centerTitle: true,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_rounded, color: Color(0xFF00E5FF)),
            onPressed: _showAddFriendDialog,
          )
        ],
        bottom: _buildTabBar(),
      ),
      body: CustomPaint(
        painter: const TetrisGridPainter(),
        child: _buildTabView(),
      ),
    );
  }

  Widget _buildEloHeader() {
    if (_profile == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1024),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF00E5FF).withOpacity(0.35),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00E5FF).withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Avatar interactivo estilo Tetrimino con acento cian neón
          GestureDetector(
            onTap: () => HybridProfileModal.show(context, profile: _profile),
            child: Tooltip(
              message: 'Ver perfil y logros',
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF101735),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFF00E5FF).withOpacity(0.8),
                    width: 1.8,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00E5FF).withOpacity(0.3),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(Icons.person_rounded, size: 26, color: Color(0xFF00E5FF)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Nombre en cian vibrante
                Text(
                  '${_profile!.clanTag != null ? '[${_profile!.clanTag}] ' : ''}${_profile!.displayName}',
                  style: const TextStyle(
                    color: Color(0xFF00E5FF),
                    fontWeight: FontWeight.w900,
                    fontSize: 13.5,
                    letterSpacing: 0.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (_profile!.username != null)
                  Text(
                    '@${_profile!.username!}',
                    style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 10.5, fontWeight: FontWeight.w500),
                  ),
                // Código en Amarillo Citrino brillante (tocar para copiar)
                if (_profile!.codigoJugador != null)
                  InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: _profile!.codigoJugador!));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('¡Código #${_profile!.codigoJugador} copiado al portapapeles!'),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '#${_profile!.codigoJugador}',
                          style: const TextStyle(
                            color: Color(0xFFFACC15),
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.6,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.copy_rounded, size: 12, color: Color(0xFFFACC15)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          // Badge Rango en Amarillo Citrino brillante con resplandor
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0x22FACC15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: const Color(0xFFFACC15).withOpacity(0.8),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFACC15).withOpacity(0.18),
                  blurRadius: 8,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.flash_on_rounded, size: 14, color: Color(0xFFFACC15)),
                const SizedBox(width: 4),
                Text(
                  'RANGO ${_profile!.tetrisElo}',
                  style: const TextStyle(
                    color: Color(0xFFFACC15),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildTabBar() {
    return TabBar(
      controller: _tabController,
      indicatorColor: const Color(0xFF00E5FF),
      indicatorWeight: 3.0,
      labelColor: const Color(0xFF00E5FF),
      unselectedLabelColor: const Color(0xFF64748B),
      labelStyle: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.0,
      ),
      unselectedLabelStyle: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
      isScrollable: true,
      tabs: [
        Tab(text: 'MIS AMIGOS (${_friends.length})'),
        Tab(text: 'SOLICITUDES (${_requests.length})'),
        Tab(text: 'DESAFÍOS (${_desafios.length})'),
      ],
    );
  }

  Widget _buildTabView() {
    return _isLoading
        ? const Center(child: CircularProgressIndicator(color: Color(0xFF5865F2)))
        : TabBarView(
            controller: _tabController,
            children: [
              _buildFriendsList(),
              _buildRequestsList(),
              _buildDesafiosList(),
            ],
          );
  }

  Widget _buildFriendsList() {
    if (_friends.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFF0B1024),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.2)),
              ),
              child: const Icon(Icons.group_outlined, size: 36, color: Color(0xFF00E5FF)),
            ),
            const SizedBox(height: 14),
            const Text(
              'Aún no tienes amigos agregados en Gameros',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: _showAddFriendDialog,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF2A85), Color(0xFFD80064)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFF6EB4), width: 1.0),
                  boxShadow: [
                    const BoxShadow(color: Color(0xFF88003E), offset: Offset(0, 3)),
                    BoxShadow(color: const Color(0xFFFF2A85).withOpacity(0.35), blurRadius: 8),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.person_add_rounded, size: 16, color: Colors.white),
                    SizedBox(width: 6),
                    Text(
                      'AGREGAR AMIGO',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1.0),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(14),
      itemCount: _friends.length,
      itemBuilder: (context, index) {
        final f = _friends[index];

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF0B1024),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFF00E5FF).withOpacity(0.35),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00E5FF).withOpacity(0.08),
                blurRadius: 12,
                spreadRadius: 0,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              // Avatar cuadrado tipo bloque Tetrimino
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFF101735),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFF00E5FF).withOpacity(0.5),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00E5FF).withOpacity(0.18),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(
                    Icons.sports_esports_rounded,
                    size: 26,
                    color: Color(0xFF00E5FF),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Nombre de usuario en cian vibrante
                    Text(
                      f.gamerTag,
                      style: const TextStyle(
                        color: Color(0xFF00E5FF),
                        fontWeight: FontWeight.w900,
                        fontSize: 13.5,
                        letterSpacing: 0.5,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (f.username != null) ...[
                      const SizedBox(height: 1),
                      Text(
                        '@${f.username}',
                        style: const TextStyle(
                          color: Color(0xFF38BDF8),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    // Rango en Amarillo Citrino brillante
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0x22FACC15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: const Color(0xFFFACC15).withOpacity(0.7),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.flash_on_rounded, size: 11, color: Color(0xFFFACC15)),
                          const SizedBox(width: 3),
                          Text(
                            'RANGO ${f.tetrisElo}',
                            style: const TextStyle(
                              color: Color(0xFFFACC15),
                              fontSize: 9.5,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Botón Arcade "DESAFIAR" en Neón Magenta con bisel 3D
              GestureDetector(
                onTap: () => _desafiar(f),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF2A85), Color(0xFFD80064)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFFFF6EB4),
                      width: 1.0,
                    ),
                    boxShadow: [
                      // Sombra inferior biselada para relieve 3D arcade
                      const BoxShadow(
                        color: Color(0xFF88003E),
                        offset: Offset(0, 3),
                        blurRadius: 0,
                      ),
                      // Resplandor neón magenta
                      BoxShadow(
                        color: const Color(0xFFFF2A85).withOpacity(0.35),
                        blurRadius: 8,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bolt_rounded, size: 14, color: Colors.white),
                      SizedBox(width: 4),
                      Text(
                        'DESAFIAR',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRequestsList() {
    if (_requests.isEmpty) {
      return const Center(
        child: Text(
          'No tienes solicitudes pendientes de Gameros',
          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(14),
      itemCount: _requests.length,
      itemBuilder: (context, index) {
        final r = _requests[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF0B1024),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFF00E5FF).withOpacity(0.35),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00E5FF).withOpacity(0.08),
                blurRadius: 12,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF101735),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFF00E5FF).withOpacity(0.5),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00E5FF).withOpacity(0.15),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.person_add_alt_1_rounded, size: 22, color: Color(0xFF00E5FF)),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.senderGamerTag,
                        style: const TextStyle(
                          color: Color(0xFF00E5FF),
                          fontWeight: FontWeight.w900,
                          fontSize: 13.5,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text('Solicitud de amistad de Gameros', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10)),
                    ],
                  ),
                ],
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.check_circle_rounded, color: Color(0xFF00E5FF), size: 28),
                    onPressed: () async {
                      await _friendsService.respondToRequest(r.requestId, true);
                      _loadData();
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.cancel_rounded, color: Color(0xFFFF2A85), size: 28),
                    onPressed: () async {
                      await _friendsService.respondToRequest(r.requestId, false);
                      _loadData();
                    },
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDesafiosList() {
    if (_desafios.isEmpty) {
      return const Center(
        child: Text('No tienes desafíos activos', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5)),
      );
    }
    final myId = SupabaseConfig.client.auth.currentUser?.id;
    return ListView.builder(
      padding: const EdgeInsets.all(14),
      itemCount: _desafios.length,
      itemBuilder: (context, index) {
        final d = _desafios[index];
        return _DesafioCard(
          desafio: d,
          isMine: d.retadorId == myId,
          onAceptar: () => _responderDesafio(d, true),
          onRechazar: () => _responderDesafio(d, false),
          onExpirado: _loadDesafios,
        );
      },
    );
  }
}

class _DesafioCard extends StatefulWidget {
  final DesafioModel desafio;
  final bool isMine;
  final VoidCallback onAceptar;
  final VoidCallback onRechazar;
  final VoidCallback onExpirado;

  const _DesafioCard({
    required this.desafio,
    required this.isMine,
    required this.onAceptar,
    required this.onRechazar,
    required this.onExpirado,
  });

  @override
  State<_DesafioCard> createState() => _DesafioCardState();
}

class _DesafioCardState extends State<_DesafioCard> {
  late Timer _timer;
  Duration _restante = Duration.zero;

  @override
  void initState() {
    super.initState();
    _restante = widget.desafio.tiempoRestante;
    _timer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      final r = widget.desafio.tiempoRestante;
      if (mounted) setState(() => _restante = r);
      if (r == Duration.zero) {
        _timer.cancel();
        widget.onExpirado();
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
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1024),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFFACC15).withOpacity(0.55),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFACC15).withOpacity(0.14),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.flash_on_rounded, color: Color(0xFFFACC15), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.isMine ? 'Esperando respuesta...' : '¡Te desafiaron a un 1v1!',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12.5),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0x28FACC15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFFFACC15).withOpacity(0.5)),
                ),
                child: Text(
                  '${_restante.inSeconds}s',
                  style: const TextStyle(
                    color: Color(0xFFFACC15),
                    fontWeight: FontWeight.w900,
                    fontSize: 11.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: const Color(0xFF101735),
              valueColor: AlwaysStoppedAnimation(progress > 0.3 ? const Color(0xFF00E5FF) : const Color(0xFFFF2A85)),
            ),
          ),
          if (!widget.isMine) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: widget.onAceptar,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 9),
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
                          BoxShadow(color: Color(0x5500E5FF), blurRadius: 8),
                        ],
                      ),
                      child: const Center(
                        child: Text(
                          'ACEPTAR',
                          style: TextStyle(
                            color: Color(0xFF070B19),
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: widget.onRechazar,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 9),
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
                          BoxShadow(color: Color(0x55FF2A85), blurRadius: 8),
                        ],
                      ),
                      child: const Center(
                        child: Text(
                          'RECHAZAR',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _AddFriendDialog extends StatefulWidget {
  final FriendsService friendsService;
  final VoidCallback onSent;

  const _AddFriendDialog({required this.friendsService, required this.onSent});

  @override
  State<_AddFriendDialog> createState() => _AddFriendDialogState();
}

class _AddFriendDialogState extends State<_AddFriendDialog> {
  final TextEditingController _controller = TextEditingController();
  List<UserSearchResult> _results = [];
  Timer? _debounce;
  bool _isSearching = false;

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      if (value.trim().length < 2) {
        setState(() => _results = []);
        return;
      }
      setState(() => _isSearching = true);
      final r = await widget.friendsService.searchUsers(value);
      if (mounted) setState(() { _results = r; _isSearching = false; });
    });
  }

  Future<void> _sendTo(String targetId, String label) async {
    Navigator.of(context).pop();
    try {
      await widget.friendsService.sendFriendRequest(targetId);
      widget.onSent();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('¡Solicitud enviada a $label!')),
      );
    } catch (e) {
      widget.onSent();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al enviar: $e'), backgroundColor: const Color(0xFF3A1414)),
      );
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF161B22),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Color(0xFF5865F2))),
      title: const Row(
        children: [
          Icon(Icons.person_add_rounded, color: Color(0xFF5865F2)),
          SizedBox(width: 8),
          Text('AGREGAR AMIGO GAMEROS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5)),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Escribí un nombre, @usuario o el código de jugador:', style: TextStyle(color: Color(0xFF8B949E), fontSize: 11.5)),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              autofocus: true,
              onChanged: _onChanged,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Ej: Lucas, @Lucas o A1B2C3',
                hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
                filled: true,
                fillColor: const Color(0xFF0D1117),
                suffixIcon: _isSearching ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 8, height: 8, child: CircularProgressIndicator(strokeWidth: 2))) : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF30363D))),
              ),
            ),
            const SizedBox(height: 10),
            if (_results.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _results.length,
                  itemBuilder: (context, i) {
                    final r = _results[i];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.account_circle, color: Color(0xFF818CF8)),
                      title: Text(r.displayName, style: const TextStyle(color: Colors.white, fontSize: 13)),
                      subtitle: r.username != null ? Text(r.username!, style: const TextStyle(color: Color(0xFF818CF8), fontSize: 11)) : null,
                      trailing: IconButton(
                        icon: const Icon(Icons.person_add_alt_1_rounded, color: Color(0xFF5865F2)),
                        onPressed: () => _sendTo(r.id, r.displayName),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('CANCELAR', style: TextStyle(color: Color(0xFF8B949E)))),
        ElevatedButton(
          onPressed: () {
            final raw = _controller.text.trim();
            final q = raw.replaceAll('#', '').trim().toUpperCase();
            if (q.isNotEmpty) _sendTo(q, '#$q');
          },
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF5865F2)),
          child: const Text('ENVIAR POR CÓDIGO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
        ),
      ],
    );
  }
}

/// Pintor para patrón sutil de matriz de Tetris estilo Arcade Neón (5% opacidad)
class TetrisGridPainter extends CustomPainter {
  final Color gridColor;
  final double cellSize;

  const TetrisGridPainter({
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

