import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gameros_auth_ui/gameros_auth_ui.dart';
import 'core/supabase_config.dart';
import 'game/tetris_types.dart';
import 'services/deep_link_service.dart';
import 'services/gameros_profile_service.dart';
import 'ui/create_duel_screen.dart';
import 'ui/match_lobby_screen.dart';
import 'ui/friends_screen.dart';
import 'ui/tetris_game_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await SupabaseConfig.initialize();
  } catch (_) {}
  try {
    await DeepLinkService().initialize();
  } catch (_) {}
  runApp(const TetrisNowApp());
}

class TetrisNowApp extends StatefulWidget {
  const TetrisNowApp({Key? key}) : super(key: key);

  @override
  State<TetrisNowApp> createState() => _TetrisNowAppState();
}

class _TetrisNowAppState extends State<TetrisNowApp> {
  @override
  void initState() {
    super.initState();
    DeepLinkService().onDeepLink.listen((payload) {
      if (payload.matchId != null) {
        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => MatchLobbyScreen(initialMatchId: payload.matchId),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Tetris now by gAmeros',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF07090E),
        primaryColor: const Color(0xFF5865F2),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0D111A),
          elevation: 0,
        ),
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({Key? key}) : super(key: key);

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _isGuestMode = false;

  @override
  Widget build(BuildContext context) {
    if (_isGuestMode) {
      return const TetrisHomeScreen(isGuest: true);
    }

    try {
      return StreamBuilder<AuthState>(
        stream: SupabaseConfig.client.auth.onAuthStateChange,
        builder: (context, snapshot) {
          final session = snapshot.data?.session ?? SupabaseConfig.client.auth.currentSession;
          if (session != null) {
            return const TetrisHomeScreen(isGuest: false);
          }
          return GamerosLoginScreen(
            authService: GamerosAuthService(supabase: SupabaseConfig.client),
            appTitle: 'Tetris now by gAmeros',
            onLoginSuccess: () {
              setState(() {});
            },
            onGuestLogin: () {
              setState(() {
                _isGuestMode = true;
              });
            },
          );
        },
      );
    } catch (_) {
      return GamerosLoginScreen(
        authService: GamerosAuthService(supabase: SupabaseConfig.client),
        appTitle: 'Tetris now by gAmeros',
        onLoginSuccess: () => setState(() {}),
        onGuestLogin: () => setState(() => _isGuestMode = true),
      );
    }
  }
}

class TetrisHomeScreen extends StatefulWidget {
  final bool isGuest;

  const TetrisHomeScreen({Key? key, this.isGuest = false}) : super(key: key);

  @override
  State<TetrisHomeScreen> createState() => _TetrisHomeScreenState();
}

class _TetrisHomeScreenState extends State<TetrisHomeScreen> {
  final GamerosProfileService _profileService = GamerosProfileService();
  GamerosUserProfile? _profile;

  @override
  void initState() {
    super.initState();
    if (!widget.isGuest) {
      _loadProfile();
    }
  }

  Future<void> _loadProfile() async {
    try {
      final p = await _profileService.getFullProfile();
      if (p != null && mounted) {
        setState(() => _profile = p);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.isGuest ? null : SupabaseConfig.client.auth.currentUser;
    final displayName = _profile?.displayName ?? user?.userMetadata?['full_name'] ?? 'Rey-ToRuS';
    final clanTag = _profile?.clanTag != null ? '[${_profile!.clanTag}] ' : '';

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'TETRIS NOW BY GAMEROS',
          style: TextStyle(
            letterSpacing: 2.0,
            fontWeight: FontWeight.w900,
            fontSize: 13.5,
            color: Color(0xFFF1F5F9),
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.people_alt_rounded, color: Color(0xFF38BDF8)),
            tooltip: 'Amigos Gameros',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const FriendsScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, size: 20, color: Color(0xFF94A3B8)),
            tooltip: 'Cerrar Sesión',
            onPressed: () async {
              if (widget.isGuest) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const AuthGate()),
                );
              } else {
                await GamerosAuthService(supabase: SupabaseConfig.client).signOut();
              }
            },
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Tarjeta de Perfil Oficial Gameros (Esports Card)
                Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF1E1B4B), Color(0xFF0F172A)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF6366F1), width: 1.5),
                    boxShadow: const [
                      BoxShadow(color: Color(0x336366F1), blurRadius: 16, offset: Offset(0, 4)),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF6366F1).withOpacity(0.2),
                          border: Border.all(color: const Color(0xFF818CF8), width: 2),
                        ),
                        child: _profile?.avatarUrl != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(28),
                                child: Image.network(
                                  _profile!.avatarUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Icon(Icons.account_circle, size: 38, color: Color(0xFF818CF8)),
                                ),
                              )
                            : const Icon(Icons.account_circle, size: 38, color: Color(0xFF818CF8)),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.isGuest ? 'INVITADO / MODO OFFLINE' : '$clanTag$displayName',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 14.5,
                                letterSpacing: 0.8,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (_profile?.username != null)
                              Text(
                                '${_profile!.username}',
                                style: const TextStyle(color: Color(0xFF818CF8), fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            const SizedBox(height: 3),
                            Text(
                              widget.isGuest
                                  ? 'Sin conexión a cuenta Gameros'
                                  : 'Nivel ${_profile?.nivel ?? 1} • Reputación: ${_profile?.reputacion ?? 100} PTS',
                              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                            ),
                            const SizedBox(height: 5),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFF4F46E5).withOpacity(0.35),
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(color: const Color(0xFF6366F1)),
                              ),
                              child: Text(
                                'TETRIS ELO: ${_profile?.tetrisElo ?? 1000} PTS  (W: ${_profile?.tetrisWins ?? 0} / L: ${_profile?.tetrisLosses ?? 0})',
                                style: const TextStyle(color: Color(0xFFC7D2FE), fontSize: 9.5, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // 1. BOTÓN PRINCIPAL: JUGAR DUELO 1v1 (MATCHMAKING Y SALAS PRIVADAS)
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
                    boxShadow: const [
                      BoxShadow(color: Color(0x666366F1), blurRadius: 20, offset: Offset(0, 6)),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const CreateDuelScreen()),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 18.0),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.18),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.flash_on_rounded, color: Colors.white, size: 28),
                            ),
                            const SizedBox(width: 16),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'JUGAR DUELO 1v1',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 16,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                  SizedBox(height: 3),
                                  Text(
                                    'Matchmaking competitivo y salas con clave',
                                    style: TextStyle(color: Color(0xFFE0E7FF), fontSize: 11, fontWeight: FontWeight.w500),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 18),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // 2. BOTÓN SECUNDARIO: MODO SOLITARIO / PRÁCTICA (TEST INDIVIDUAL)
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF334155), width: 1.2),
                    boxShadow: const [
                      BoxShadow(color: Color(0x22000000), blurRadius: 10, offset: Offset(0, 3)),
                    ],
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
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 14.0),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0EA5E9).withOpacity(0.2),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.videogame_asset_rounded, color: Color(0xFF38BDF8), size: 24),
                            ),
                            const SizedBox(width: 14),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'MODO SOLITARIO (PRÁCTICA)',
                                    style: TextStyle(
                                      color: Color(0xFFF1F5F9),
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'Prueba libre 10x20 con sonido, cubos dorados y plata',
                                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.play_arrow_rounded, color: Color(0xFF38BDF8), size: 20),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
