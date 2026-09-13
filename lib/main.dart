import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gameros_auth_ui/gameros_auth_ui.dart';
import 'core/supabase_config.dart';
import 'services/deep_link_service.dart';
import 'ui/home_shell.dart';
import 'ui/match_lobby_screen.dart';
import 'ui/tournament_brackets_screen.dart';

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
      if (payload.tournamentId != null && payload.tournamentId!.isNotEmpty) {
        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => TournamentBracketsScreen(
              tournamentId: payload.tournamentId!,
            ),
          ),
        );
      } else if (payload.matchId != null) {
        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => MatchLobbyScreen(
              initialMatchId: payload.matchId,
              tournamentId: payload.tournamentId,
            ),
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
      return HomeShell(isGuest: true, onGuestExit: () => setState(() => _isGuestMode = false));
    }

    try {
      return StreamBuilder<AuthState>(
        stream: SupabaseConfig.client.auth.onAuthStateChange,
        builder: (context, snapshot) {
          final session = snapshot.data?.session ?? SupabaseConfig.client.auth.currentSession;
          if (session != null) {
            return const HomeShell(isGuest: false);
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

