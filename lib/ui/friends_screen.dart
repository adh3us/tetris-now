import 'dart:async';
import 'package:flutter/material.dart';
import '../services/friends_service.dart';
import '../services/desafio_service.dart';
import '../services/gameros_profile_service.dart';
import '../services/tetris_match_service.dart';
import '../services/tetris_realtime_service.dart';
import '../core/supabase_config.dart';
import '../game/tetris_types.dart';
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
    _esperandoRivalTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      final estado = await _matchService.consultarEstadoMatch(matchId, myTeamId);
      if (estado['status'] == 'matched') {
        timer.cancel();
        await _entrarAPartida(matchId, myTeamId);
      }
    });
  }

  Future<void> _entrarAPartida(String matchId, String myTeamId) async {
    if (!mounted) return;
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
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TetrisGameScreen(mode: GameMode.duel1v1, matchId: matchId, realtimeService: realtime),
      ),
    );
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
    if (widget.embedded) {
      return Column(
        children: [
          _buildEloHeader(),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Row(
              children: [
                const Expanded(child: Text('AMIGOS Y SOCIAL', style: TextStyle(letterSpacing: 1.2, fontWeight: FontWeight.w900, fontSize: 13, color: Colors.white))),
                IconButton(
                  icon: const Icon(Icons.person_add_rounded, color: Color(0xFF5865F2)),
                  onPressed: _showAddFriendDialog,
                ),
              ],
            ),
          ),
          Material(color: const Color(0xFF080A0F), child: _buildTabBar()),
          Expanded(child: _buildTabView()),
        ],
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF080A0F),
      appBar: AppBar(
        title: const Text('AMIGOS Y SOCIAL (GAMEROS)', style: TextStyle(letterSpacing: 1.5, fontWeight: FontWeight.w900, fontSize: 13.5)),
        backgroundColor: const Color(0xFF0F141C),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_rounded, color: Color(0xFF5865F2)),
            onPressed: _showAddFriendDialog,
          )
        ],
        bottom: _buildTabBar(),
      ),
      body: _buildTabView(),
    );
  }

  Widget _buildEloHeader() {
    if (_profile == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF4F46E5).withOpacity(0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.account_circle, size: 32, color: Color(0xFF818CF8)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_profile!.clanTag != null ? '[${_profile!.clanTag}] ' : ''}${_profile!.displayName}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
                if (_profile!.username != null)
                  Text(_profile!.username!, style: const TextStyle(color: Color(0xFF818CF8), fontSize: 10.5)),
                if (_profile!.codigoJugador != null)
                  Text('#${_profile!.codigoJugador}', style: const TextStyle(color: Color(0xFF64748B), fontSize: 10)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF4F46E5).withOpacity(0.35),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF6366F1)),
            ),
            child: Text(
              'RANGO ${_profile!.tetrisElo}',
              style: const TextStyle(color: Color(0xFFC7D2FE), fontSize: 12, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildTabBar() {
    return TabBar(
      controller: _tabController,
      indicatorColor: const Color(0xFF5865F2),
      labelColor: Colors.white,
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
            const Icon(Icons.group_outlined, size: 54, color: Colors.white24),
            const SizedBox(height: 12),
            const Text('Aún no tienes amigos agregados en Gameros', style: TextStyle(color: Color(0xFF8B949E), fontSize: 13)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _showAddFriendDialog,
              icon: const Icon(Icons.person_add_rounded, size: 16),
              label: const Text('AGREGAR AMIGO'),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF5865F2)),
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
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF30363D)),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF21262D)),
                child: const Icon(Icons.account_circle, size: 34, color: Colors.white70),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(f.gamerTag, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13)),
                    if (f.username != null)
                      Text(f.username!, style: const TextStyle(color: Color(0xFF818CF8), fontSize: 10.5)),
                    Text('RANGO ${f.tetrisElo}', style: const TextStyle(color: Color(0xFF8B949E), fontSize: 10)),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: () => _desafiar(f),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF5865F2),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('DESAFIAR', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
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
        child: Text('No tienes solicitudes pendientes de Gameros', style: TextStyle(color: Color(0xFF8B949E), fontSize: 12.5)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(14),
      itemCount: _requests.length,
      itemBuilder: (context, index) {
        final r = _requests[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF5865F2)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.account_circle, size: 36, color: Color(0xFF5865F2)),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.senderGamerTag, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 2),
                      const Text('Solicitud de amistad de Gameros', style: TextStyle(color: Color(0xFF8B949E), fontSize: 10)),
                    ],
                  ),
                ],
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.check_circle_rounded, color: Color(0xFF00D26A), size: 28),
                    onPressed: () async {
                      await _friendsService.respondToRequest(r.requestId, true);
                      _loadData();
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.cancel_rounded, color: Color(0xFFDA3633), size: 28),
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
        child: Text('No tienes desafíos activos', style: TextStyle(color: Color(0xFF8B949E), fontSize: 12.5)),
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
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE3B341)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.flash_on_rounded, color: Color(0xFFE3B341), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.isMine ? 'Esperando respuesta...' : '¡Te desafiaron a un 1v1!',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12.5),
                ),
              ),
              Text('${_restante.inSeconds}s', style: const TextStyle(color: Color(0xFFE3B341), fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: const Color(0xFF30363D),
              valueColor: AlwaysStoppedAnimation(progress > 0.3 ? const Color(0xFF00D26A) : const Color(0xFFDA3633)),
            ),
          ),
          if (!widget.isMine) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: widget.onAceptar,
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00D26A)),
                    child: const Text('ACEPTAR', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: widget.onRechazar,
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDA3633)),
                    child: const Text('RECHAZAR', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
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
            final q = _controller.text.trim();
            if (q.isNotEmpty) _sendTo(q, q);
          },
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF5865F2)),
          child: const Text('ENVIAR POR CÓDIGO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
        ),
      ],
    );
  }
}
