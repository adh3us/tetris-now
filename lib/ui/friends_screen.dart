import 'package:flutter/material.dart';
import '../services/friends_service.dart';
import 'create_duel_screen.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({Key? key}) : super(key: key);

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> with SingleTickerProviderStateMixin {
  final FriendsService _friendsService = FriendsService();
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _chatMsgController = TextEditingController();

  List<FriendModel> _friends = [];
  List<FriendRequestModel> _requests = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final f = await _friendsService.getFriends();
      final r = await _friendsService.getPendingRequests();
      if (mounted) {
        setState(() {
          _friends = f;
          _requests = r;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showAddFriendDialog() {
    _searchController.clear();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Color(0xFF5865F2))),
        title: const Row(
          children: [
            Icon(Icons.person_add_rounded, color: Color(0xFF5865F2)),
            SizedBox(width: 8),
            Text('AGREGAR AMIGO GAMEROS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Busca un usuario real por GamerTag, @usuario o Email:', style: TextStyle(color: Color(0xFF8B949E), fontSize: 11.5)),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Ej: Lucas o @Lucas',
                hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
                filled: true,
                fillColor: const Color(0xFF0D1117),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF30363D))),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('CANCELAR', style: TextStyle(color: Color(0xFF8B949E)))),
          ElevatedButton(
            onPressed: () async {
              final q = _searchController.text.trim();
              if (q.isNotEmpty) {
                Navigator.of(ctx).pop();
                final ok = await _friendsService.sendFriendRequest(q);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(ok ? '¡Solicitud enviada a "$q"!' : 'Solicitud enviada a "$q"')),
                  );
                  _loadData();
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF5865F2)),
            child: const Text('ENVIAR SOLICITUD', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _openChatDialog(FriendModel friend) async {
    final messages = await _friendsService.getDirectMessages(friend.userId);
    _chatMsgController.clear();
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setChatState) => AlertDialog(
          backgroundColor: const Color(0xFF161B22),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFF5865F2))),
          title: Row(
            children: [
              const Icon(Icons.chat_bubble_outline_rounded, color: Color(0xFF38BDF8), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text('MENSAJES CON ${friend.gamerTag.toUpperCase()}', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900), overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 280,
            child: Column(
              children: [
                Expanded(
                  child: messages.isEmpty
                      ? const Center(
                          child: Text('No hay mensajes previos. ¡Escríbele a tu amigo!', style: TextStyle(color: Colors.white38, fontSize: 11.5)),
                        )
                      : ListView.builder(
                          itemCount: messages.length,
                          itemBuilder: (context, idx) {
                            final m = messages[idx];
                            final isMe = m.senderGamerTag == 'Tú';
                            return Align(
                              alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 6),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: isMe ? const Color(0xFF4F46E5) : const Color(0xFF21262D),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(m.message, style: const TextStyle(color: Colors.white, fontSize: 11.5)),
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _chatMsgController,
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                        decoration: InputDecoration(
                          hintText: 'Escribe un mensaje o reto...',
                          hintStyle: const TextStyle(color: Colors.white24, fontSize: 11),
                          filled: true,
                          fillColor: const Color(0xFF0D1117),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF30363D))),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      icon: const Icon(Icons.send_rounded, color: Color(0xFF38BDF8), size: 22),
                      onPressed: () async {
                        final t = _chatMsgController.text.trim();
                        if (t.isNotEmpty) {
                          await _friendsService.sendDirectMessage(friend.userId, t);
                          _chatMsgController.clear();
                          final updated = await _friendsService.getDirectMessages(friend.userId);
                          setChatState(() {
                            messages.clear();
                            messages.addAll(updated);
                          });
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('CERRAR', style: TextStyle(color: Color(0xFF8B949E)))),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF5865F2),
          tabs: [
            Tab(text: 'MIS AMIGOS (${_friends.length})'),
            Tab(text: 'SOLICITUDES (${_requests.length})'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF5865F2)))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildFriendsList(),
                _buildRequestsList(),
              ],
            ),
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
        final isOnline = f.status == 'en_linea';

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isOnline ? const Color(0xFF5865F2).withOpacity(0.4) : const Color(0xFF30363D)),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF21262D),
                  border: Border.all(color: isOnline ? const Color(0xFF00D26A) : const Color(0xFF8B949E), width: 1.8),
                ),
                child: const Icon(Icons.account_circle, size: 34, color: Colors.white70),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(f.gamerTag, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13)),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isOnline ? const Color(0xFF00D26A) : Colors.grey,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            f.currentGame, // e.g. "Jugando Tetris Now", "Jugando TrucoArg", "Jugando Chess in Time"
                            style: TextStyle(
                              color: isOnline ? const Color(0xFF38BDF8) : const Color(0xFF8B949E),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.mail_outline_rounded, color: Color(0xFF38BDF8), size: 20),
                    tooltip: 'Enviar Mensaje / Buzón',
                    onPressed: () => _openChatDialog(f),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CreateDuelScreen()));
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF5865F2),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('INVITAR', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ],
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
}
