import 'package:flutter/material.dart';
import '../services/tetris_match_service.dart';
import 'match_lobby_screen.dart';

class BrowseRoomsScreen extends StatefulWidget {
  const BrowseRoomsScreen({Key? key}) : super(key: key);

  @override
  State<BrowseRoomsScreen> createState() => _BrowseRoomsScreenState();
}

class _BrowseRoomsScreenState extends State<BrowseRoomsScreen> {
  final TetrisMatchService _matchService = TetrisMatchService();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _pwdInputController = TextEditingController();

  List<TetrisMatchModel> _rooms = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchRooms();
  }

  Future<void> _fetchRooms() async {
    setState(() => _isLoading = true);
    try {
      final list = await _matchService.getActivePublicRooms();
      if (mounted) setState(() => _rooms = list);
    } catch (_) {} finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _tryJoinRoom(TetrisMatchModel room) {
    if (room.isPrivate) {
      _pwdInputController.clear();
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF161B22),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0xFF5865F2))),
          title: Text('SALA PRIVADA: ${room.roomName}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Esta sala requiere contraseña para ingresar:', style: TextStyle(color: Color(0xFF8B949E), fontSize: 11.5)),
              const SizedBox(height: 10),
              TextField(
                controller: _pwdInputController,
                obscureText: true,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Contraseña de la sala',
                  hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
                  filled: true,
                  fillColor: const Color(0xFF0D1117),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('CANCELAR', style: TextStyle(color: Color(0xFF8B949E)))),
            ElevatedButton(
              onPressed: () {
                final pwd = _pwdInputController.text.trim();
                Navigator.of(ctx).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => MatchLobbyScreen(initialMatchId: room.id)),
                );
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF5865F2)),
              child: const Text('INGRESAR', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => MatchLobbyScreen(initialMatchId: room.id)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = _rooms.where((r) {
      return r.roomName.toLowerCase().contains(query) || r.roomCode.contains(query);
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF080A0F),
      appBar: AppBar(
        title: const Text('ENCONTRAR SALAS (LOBBY)', style: TextStyle(letterSpacing: 1.5, fontWeight: FontWeight.w900, fontSize: 13.5)),
        backgroundColor: const Color(0xFF0F141C),
        centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.refresh, color: Color(0xFF5865F2)), onPressed: _fetchRooms),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Barra de Búsqueda
            TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Buscar por nombre o código (ej: 90960)',
                hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
                prefixIcon: const Icon(Icons.search, color: Color(0xFF5865F2), size: 20),
                filled: true,
                fillColor: const Color(0xFF161B22),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF30363D))),
              ),
            ),
            const SizedBox(height: 14),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('SALAS EN VIVO (${filtered.length})', style: const TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold, fontSize: 11)),
                const Text('Actualizado en Realtime', style: TextStyle(color: Color(0xFF00D26A), fontSize: 9.5, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 10),

            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF5865F2)))
                  : filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.meeting_room_outlined, size: 54, color: Colors.white24),
                              const SizedBox(height: 12),
                              const Text('No hay salas activas en este momento', style: TextStyle(color: Color(0xFF8B949E), fontSize: 12.5)),
                              const SizedBox(height: 14),
                              ElevatedButton(
                                onPressed: _fetchRooms,
                                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF5865F2)),
                                child: const Text('ACTUALIZAR LISTA'),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final r = filtered[index];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFF161B22),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: r.isPrivate ? const Color(0xFFD29922).withOpacity(0.5) : const Color(0xFF30363D)),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color: r.isPrivate ? const Color(0xFFD29922).withOpacity(0.15) : const Color(0xFF5865F2).withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(r.isPrivate ? Icons.lock : Icons.lock_open, color: r.isPrivate ? const Color(0xFFD29922) : const Color(0xFF5865F2), size: 22),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(r.roomName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                                        const SizedBox(height: 3),
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                              decoration: BoxDecoration(color: const Color(0xFF21262D), borderRadius: BorderRadius.circular(4)),
                                              child: Text('CÓDIGO: #${r.roomCode}', style: const TextStyle(color: Color(0xFF58A6FF), fontSize: 9.5, fontWeight: FontWeight.w900)),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              r.isPrivate ? 'Privada' : 'Pública',
                                              style: TextStyle(color: r.isPrivate ? const Color(0xFFD29922) : const Color(0xFF00D26A), fontSize: 10, fontWeight: FontWeight.bold),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              r.allowSpectators ? '👁️ Árbitro ON' : '🚫 Sin Árbitros',
                                              style: const TextStyle(color: Color(0xFF8B949E), fontSize: 9.5),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  ElevatedButton(
                                    onPressed: () => _tryJoinRoom(r),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF238636),
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    child: const Text('UNIRSE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
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
}
