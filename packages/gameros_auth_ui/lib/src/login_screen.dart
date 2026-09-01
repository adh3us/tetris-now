import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_service.dart';

class GamerosLoginScreen extends StatefulWidget {
  final GamerosAuthService authService;
  final VoidCallback onLoginSuccess;
  final VoidCallback? onGuestLogin;
  final String appTitle;

  const GamerosLoginScreen({
    Key? key,
    required this.authService,
    required this.onLoginSuccess,
    this.onGuestLogin,
    this.appTitle = 'Tetris now by gAmeros',
  }) : super(key: key);

  @override
  State<GamerosLoginScreen> createState() => _GamerosLoginScreenState();
}

class _GamerosLoginScreenState extends State<GamerosLoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isSignUpMode = false; // Alternar entre Iniciar Sesión y Registrarse
  String? _errorMessage;
  String? _successMessage;

  Future<void> _handleEmailAuth() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'Por favor completa el email y la contraseña.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      if (_isSignUpMode) {
        // Registro de nueva cuenta en auth.users de Gameros
        final res = await widget.authService.supabase.auth.signUp(
          email: email,
          password: password,
        );
        if (res.user != null) {
          if (res.session != null) {
            widget.onLoginSuccess();
          } else {
            setState(() {
              _successMessage = '¡Cuenta creada con éxito! Si tienes confirmación de email activada en Supabase, revisa tu casilla o inicia sesión.';
              _isSignUpMode = false;
            });
          }
        }
      } else {
        // Inicio de sesión
        await widget.authService.signInWithEmailPassword(
          email: email,
          password: password,
        );
        widget.onLoginSuccess();
      }
    } on AuthException catch (e) {
      setState(() {
        if (e.message.contains('Invalid login credentials')) {
          _errorMessage = 'Credenciales incorrectas. Si tu cuenta se creó con Google, usa el botón "Continuar con Google", o toca "Crear Cuenta" abajo.';
        } else {
          _errorMessage = e.message;
        }
      });
    } catch (e) {
      setState(() => _errorMessage = 'Error de conexión: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGoogleLogin() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      await widget.authService.signInWithGoogle();
      widget.onLoginSuccess();
    } on AuthException catch (e) {
      setState(() => _errorMessage = 'Google Auth: ${e.message}');
    } catch (e) {
      setState(() => _errorMessage = 'Para ingresar con Google, registra el SHA-1 de Android en tu Google Cloud Console.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080A0F),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Logo Icono Gamer
                Center(
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F141C),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF5865F2), width: 1.8),
                      boxShadow: const [
                        BoxShadow(color: Color(0x555865F2), blurRadius: 12),
                      ],
                    ),
                    child: const Icon(Icons.sports_esports, size: 36, color: Color(0xFF5865F2)),
                  ),
                ),
                const SizedBox(height: 14),

                Text(
                  widget.appTitle.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF5865F2),
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _isSignUpMode ? 'Crea una cuenta en la red Gameros' : 'Inicia sesión con tu cuenta Gameros',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12),
                ),
                const SizedBox(height: 20),

                // Mensajes de Alerta / Error
                if (_errorMessage != null)
                  Container(
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDA3633).withOpacity(0.15),
                      border: Border.all(color: const Color(0xFFDA3633)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Color(0xFFF85149), fontSize: 11.5, height: 1.3),
                    ),
                  ),

                if (_successMessage != null)
                  Container(
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF238636).withOpacity(0.15),
                      border: Border.all(color: const Color(0xFF238636)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _successMessage!,
                      style: const TextStyle(color: Color(0xFF3FB950), fontSize: 11.5, height: 1.3),
                    ),
                  ),

                // Selector de modo (Iniciar Sesión vs Registrarse)
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() { _isSignUpMode = false; _errorMessage = null; }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            border: Border(bottom: BorderSide(color: !_isSignUpMode ? const Color(0xFF5865F2) : Colors.transparent, width: 2)),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'INGRESAR',
                            style: TextStyle(color: !_isSignUpMode ? Colors.white : const Color(0xFF8B949E), fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() { _isSignUpMode = true; _errorMessage = null; }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            border: Border(bottom: BorderSide(color: _isSignUpMode ? const Color(0xFF5865F2) : Colors.transparent, width: 2)),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'CREAR CUENTA',
                            style: TextStyle(color: _isSignUpMode ? Colors.white : const Color(0xFF8B949E), fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Campo Email
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(color: Colors.white, fontSize: 13.5),
                  decoration: InputDecoration(
                    labelText: 'Email',
                    labelStyle: const TextStyle(color: Color(0xFF8B949E), fontSize: 12.5),
                    filled: true,
                    fillColor: const Color(0xFF161B22),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF30363D)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF30363D)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Campo Contraseña
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  style: const TextStyle(color: Colors.white, fontSize: 13.5),
                  decoration: InputDecoration(
                    labelText: 'Contraseña',
                    labelStyle: const TextStyle(color: Color(0xFF8B949E), fontSize: 12.5),
                    filled: true,
                    fillColor: const Color(0xFF161B22),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF30363D)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF30363D)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Botón Ingresar / Registrarse
                ElevatedButton(
                  onPressed: _isLoading ? null : _handleEmailAuth,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5865F2),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: _isLoading
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text(
                          _isSignUpMode ? 'REGISTRARME EN GAMEROS' : 'INGRESAR',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, letterSpacing: 0.8),
                        ),
                ),
                const SizedBox(height: 10),

                // Botón Google Sign-In
                OutlinedButton.icon(
                  onPressed: _isLoading ? null : _handleGoogleLogin,
                  icon: const Icon(Icons.g_mobiledata, size: 22, color: Colors.white),
                  label: const Text(
                    'Continuar con Google',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12.5),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF30363D)),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 12),

                const Divider(color: Color(0xFF30363D), height: 1),
                const SizedBox(height: 6),

                // Acceso Directo Modo Prueba
                TextButton.icon(
                  onPressed: widget.onGuestLogin,
                  icon: const Icon(Icons.videogame_asset, color: Color(0xFF00D26A), size: 18),
                  label: const Text(
                    'MODO PRUEBA DIRECTA (SIN LOGIN)',
                    style: TextStyle(color: Color(0xFF00D26A), fontWeight: FontWeight.bold, fontSize: 11.5),
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
