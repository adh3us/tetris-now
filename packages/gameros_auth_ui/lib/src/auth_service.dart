import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';

class GamerosAuthService {
  final SupabaseClient supabase;
  static const String googleWebClientId = '94178224153-777r7ncgiiclhq2vl2dj6437nbq7b9tl.apps.googleusercontent.com';

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    serverClientId: googleWebClientId,
    scopes: ['email', 'profile'],
  );

  GamerosAuthService({required this.supabase});

  User? get currentUser => supabase.auth.currentUser;
  Stream<AuthState> get authStateChanges => supabase.auth.onAuthStateChange;

  Future<AuthResponse> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    return await supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  Future<AuthResponse> signUpWithEmailPassword({
    required String email,
    required String password,
    Map<String, dynamic>? data,
  }) async {
    return await supabase.auth.signUp(
      email: email,
      password: password,
      data: data,
    );
  }

  Future<void> signInWithGoogle() async {
    // Flujo directo oficial de Supabase OAuth: solicita la cuenta de Google una sola vez
    // y retorna automáticamente al juego a través del deep link de AndroidManifest
    await supabase.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: 'io.supabase.tetrisnow://login-callback',
    );
  }

  Future<void> signOut() async {
    try {
      await _googleSignIn.disconnect(); // Desconectar cuenta para obligar al selector de cuentas
    } catch (_) {}
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
    await supabase.auth.signOut();
  }
}
