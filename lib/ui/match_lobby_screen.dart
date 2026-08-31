import 'dart:math';
import 'package:flutter/material.dart';
import '../core/supabase_config.dart';
import '../game/tetris_types.dart';
import '../services/tetris_match_service.dart';
import '../services/tetris_realtime_service.dart';
import '../services/gameros_profile_service.dart';
import '../services/friends_service.dart';
import 'tetris_game_screen.dart';

class MatchLobbyScreen extends StatefulWidget {
  final String? initialMatchId;

  /// true cuando quien entra a esta pantalla es quien CREÓ la sala
  /// (viene de CreateDuelScreen, ya está unido con [hostTeamId]). En
  /// ese caso no hay que volver a llamar joinMatch, y es quien dispara
  /// el auto-lanzamiento apenas se conecta el invitado.
  final bool isHost;
  final String? hostTeamId;
  final String? hostOpponentTeamId;

  const MatchLobbyScreen({
    Key? key,
    this.initialMatchId,
    this.isHost = false,
    this.hostTeamId,
    this.hostOpponentTeamId,
  }) : super(key: key);

  @override
  State<MatchLobbyScreen> createState() => _MatchLobbyScreenState();
}

class _MatchLobbyScreenState extends State<MatchLobbyScreen> {
  final TetrisMatchService _matchService = TetrisMatchService();
  final GamerosProfileService _profileService = GamerosProfileService();
  final FriendsService _friendsService = FriendsService();
  late final String _currentUserId;
  String _gamerTag = 'Rey-ToRuS';

  String? _matchId;
  String? _roomCode;
  String _roomName = 'Duelo 1c1';
  String _myTeamId = '';
  String _opponentTeamId = '';
  bool _isLoading = false;
  bool _opponentConnected = false;
  bool _starting = false;
  List<TetrisPlayerModel> _players = [];
  TetrisRealtimeService? _realtimeService;

  @override
  void initState() {
    super.initState();
    final user = SupabaseConfig.client.auth.currentUser;
    _currentUserId = user?.id ?? 'guest_${Random().nextInt(99999)}';
    _gamerTag = user?.userMetadata?['full_name'] ??
        user?.userMetadata?['name'] ??
        user?.email?.split('@').first ??
        'Rey-ToRuS';

    _loadRealGamerTag();

    if (widget.initialMatchId == null) return;
    _matchId = widget.initialMatchId;

    if (widget.isHost && widget.hostTeamId != null && widget.hostOpponentTeamId != null) {
      _initAsHost(_matchId!);
    } else {
      _joinExistingMatch(_matchId!);
    }
  }

  Future<void> _loadRealGamerTag() async {
    try {
      final p = await _profileService.getFullProfile();
      if (p != null && mounted) {
        setState(() {
          _gamerTag = p.displayName;
        });
      }
    } catch (_) {}
  }

  /// El creador de la sala ya está unido (CreateDuelScreen ya llamó
  /// joinMatch) — acá solo carga los datos de la sala y arma el
  /// realtime, sin volver a unirse (eso pisaba su propio team_id).
  Future<void> _initAsHost(String matchId) async {
    setState(() => _isLoading = true);
    try {
      final match = await _matchService.getMatch(matchId);
      setState(() {
        _roomCode = match.roomCode;
        _roomName = match.roomName;
        _myTeamId = widget.hostTeamId!;
        _opponentTeamId = widget.hostOpponentTeamId!;
      });
      _initRealtime(matchId, _myTeamId, _opponentTeamId);
      _fetchPlayers();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error al cargar la sala: $e'),
        backgroundColor: const Color(0xFFDA3633),
      ));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _joinExistingMatch(String matchIdOrCode) async {
    setState(() => _isLoading = true);
    try {
      final match = await _matchService.getMatch(matchIdOrCode);
      final myTeam = match.team2Id;

      await _matchService.joinMatch(
        matchId: match.id,
        teamId: myTeam,
        gamerTag: _gamerTag,
      );

      setState(() {
        _matchId = match.id;
        _roomCode = match.roomCode;
        _roomName = match.roomName;
        _myTeamId = myTeam;
        _opponentTeamId = match.team1Id;
      });

      _initRealtime(match.id, myTeam, match.team1Id);
      _fetchPlayers();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error al unirse: $e'),
        backgroundColor: const Color(0xFFDA3633),
      ));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _initRealtime(String matchId, String myTeam, String opponentTeam) {
    try {
      _realtimeService = TetrisRealtimeService(
        matchId: matchId,
        myTeamId: myTeam,
        opponentTeamId: opponentTeam,
        currentUserId: _currentUserId,
        onMatchStart: () {
          _navigateToGame();
        },
        onOpponentConnectionChanged: (isConnected) {
          if (!mounted) return;
          setState(() => _opponentConnected = isConnected);
          // Decisión de producto (30/08/2026): mientras no esté el
          // sistema de doble "Listo" de Gameros integrado, la sala
          // lanza la partida automáticamente apenas se conecta el
          // jugador invitado — solo el host la dispara, para no
          // arrancarla dos veces.
          if (isConnected && widget.isHost) {
            _autoStartAsHost();
          }
        },
      );
      _realtimeService?.connect();
    } catch (_) {}
  }

  Future<void> _fetchPlayers() async {
    if (_matchId == null) return;
    try {
      final list = await _matchService.getMatchPlayers(_matchId!);
      if (mounted) setState(() => _players = list);
    } catch (_) {}
  }

  Future<void> _autoStartAsHost() async {
    if (_starting || _matchId == null) return;
    _starting = true;
    try {
      await _matchService.startMatch(_matchId!);
      await _realtimeService?.sendMatchStart();
    } catch (_) {}
    _navigateToGame();
  }

  void _navigateToGame() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => TetrisGameScreen(
          matchId: _matchId,
          myTeamId: _myTeamId,
          opponentTeamId: _opponentTeamId,
          realtimeService: _realtimeService,
          mode: GameMode.duel1v1,
        ),
      ),
    );
  }

  void _showInviteFriendBottomSheet() async {
    final friends = await _friendsService.getFriends();
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161B22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'INVITAR AMIGO A LA SALA',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13.5),
                ),
                IconButton(icon: const Icon(Icons.close, color: Colors.white70), onPressed: () => Navigator.of(ctx).pop()),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Comparte la sala "#${_roomCode ?? _matchId}" con tus amigos de Gameros:',
              style: const TextStyle(color: Color(0xFF8B949E), fontSize: 11.5),
            ),
            const SizedBox(height: 14),

            if (friends.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: Text('No tienes amigos conectados en este momento', style: TextStyle(color: Colors.white54, fontSize: 12))),
              )
            else
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: friends.length,
                  itemBuilder: (context, index) {
                    final f = friends[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D1117),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF30363D)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.account_circle, color: Color(0xFF5865F2), size: 28),
                              const SizedBox(width: 10),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(f.gamerTag, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12.5)),
                                  Text(f.currentGame, style: const TextStyle(color: Color(0xFF00D26A), fontSize: 9.5)),
                                ],
                              ),
                            ],
                          ),
                          ElevatedButton(
                            onPressed: () {
                              _friendsService.sendDirectMessage(f.userId, '¡Te invito a jugar un Duelo 1c1 en Tetris Now! Código de sala: ${_roomCode ?? _matchId}');
                              Navigator.of(ctx).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('¡Invitación enviada a ${f.gamerTag}!')),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF5865F2),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            ),
                            child: const Text('INVITAR', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
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

  @override
  void dispose() {
    try {
      _realtimeService?.disconnect();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080A0F),
      appBar: AppBar(
        title: Text(
          'SALA 1c1: ${_roomCode != null ? "#$_roomCode" : _matchId}',
          style: const TextStyle(letterSpacing: 1.2, fontWeight: FontWeight.w900, fontSize: 13),
        ),
        backgroundColor: const Color(0xFF0F141C),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF5865F2)))
          : Padding(
              padding: const EdgeInsets.all(18.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Tarjeta de Código de Sala
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF1E1B4B), Color(0xFF0F172A)]),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF6366F1), width: 1.5),
                      boxShadow: const [BoxShadow(color: Color(0x336366F1), blurRadius: 14, offset: Offset(0, 4))],
                    ),
                    child: Column(
                      children: [
                        Text(_roomName.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
                        const SizedBox(height: 4),
                        const Text('CÓDIGO DE SALA (COMPARTIR)', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 9.5, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        SelectableText(
                          _roomCode ?? _matchId ?? '',
                          style: const TextStyle(color: Color(0xFF818CF8), fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 3.0),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Botón Invitar Amigo de Gameros
                  OutlinedButton.icon(
                    onPressed: _showInviteFriendBottomSheet,
                    icon: const Icon(Icons.person_add_alt_1_rounded, color: Color(0xFF38BDF8), size: 18),
                    label: const Text('INVITAR AMIGO GAMEROS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11.5)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF38BDF8)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 16),

                  const Text('JUGADORES EN LA SALA', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _players.length,
                      itemBuilder: (context, index) {
                        final p = _players[index];
                        final isMe = p.userId == _currentUserId;
                        final conectado = isMe || _opponentConnected;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF161B22),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: isMe ? const Color(0xFF5865F2) : const Color(0xFF30363D)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.account_circle, color: isMe ? const Color(0xFF5865F2) : Colors.white54, size: 24),
                                  const SizedBox(width: 10),
                                  Text(
                                    p.gamerTag + (isMe ? ' (Tú)' : ''),
                                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: conectado ? const Color(0xFF238636) : const Color(0xFFDA3633),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  conectado ? 'CONECTADO' : 'ESPERANDO',
                                  style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),

                  // Sin botón "Listo": la partida arranca sola apenas
                  // se conecta el rival (decisión 30/08/2026, pendiente
                  // el doble-Listo cuando Gameros lo tenga integrado).
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF161B22),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF30363D)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _opponentConnected ? const Color(0xFF238636) : const Color(0xFF5865F2),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _opponentConnected ? 'RIVAL CONECTADO — INICIANDO...' : 'ESPERANDO AL RIVAL...',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.6),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
