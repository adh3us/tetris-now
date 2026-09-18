import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../game/tetris_engine.dart';
import '../game/tetris_types.dart';
import '../services/audio_service.dart';
import '../services/logros_service.dart';
import 'tetris_game_screen.dart';
import 'virtual_controller.dart';

class TutorialScreen extends StatefulWidget {
  const TutorialScreen({Key? key}) : super(key: key);

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialStep {
  final String numero;
  final String titulo;
  final String subtitulo;
  final String descripcion;
  final String tipPro;
  final IconData icono;
  final Color colorAcento;

  const _TutorialStep({
    required this.numero,
    required this.titulo,
    required this.subtitulo,
    required this.descripcion,
    required this.tipPro,
    required this.icono,
    required this.colorAcento,
  });
}

class _TutorialScreenState extends State<TutorialScreen> with SingleTickerProviderStateMixin {
  late TetrisEngine _engine;
  late Ticker _ticker;
  Duration _lastElapsed = Duration.zero;

  final TetrisAudioService _audioService = TetrisAudioService();
  final LogrosService _logrosService = LogrosService();

  int _currentStepIndex = 0;
  bool _isCardExpanded = true;

  final List<_TutorialStep> _steps = const [
    _TutorialStep(
      numero: '1 / 4',
      titulo: 'ROTACIÓN SRS & WALL KICKS',
      subtitulo: 'Super Rotation System Oficial',
      descripcion:
          'Las piezas no sólo rotan en el vacío: al chocar contra las paredes o bloques adyacentes, el motor calcula "patadas" (Wall Kicks) para deslizar la pieza y permitir encajarla en giros ajustados.',
      tipPro: 'Usa los botones de rotación ⟲ (CCW) y ↻ (CW). El sistema SRS te permite rotar piezas aún tocando los bordes.',
      icono: Icons.rotate_right_rounded,
      colorAcento: Color(0xFF00E5FF),
    ),
    _TutorialStep(
      numero: '2 / 4',
      titulo: 'HARD DROP EN BOTÓN FÍSICO',
      subtitulo: 'Regla de Oro Innegociable',
      descripcion:
          'La caída instantánea (Hard Drop) se ejecuta EXCLUSIVAMENTE mediante el botón físico "DROP" (Rosa). Empujar el joystick o deslizar hacia arriba NO tira la ficha, garantizando control y precisión total sin caídas accidentales.',
      tipPro: 'Ubica la sombra proyectada (Ghost Piece) en la columna deseada y pulsa DROP para bloquear la ficha de golpe.',
      icono: Icons.vertical_align_bottom_rounded,
      colorAcento: Color(0xFFFF2A85),
    ),
    _TutorialStep(
      numero: '3 / 4',
      titulo: 'COMBOS Y DAÑO EN DUELOS 1v1',
      subtitulo: 'Multiplicadores y Basura al Rival',
      descripcion:
          'Al limpiar líneas de manera consecutiva en turnos seguidos, el medidor de COMBO se infla (x2, x3, x4...). En las partidas 1v1 contra otros usuarios, cada combo envía ráfagas de líneas de basura con un hueco a la base del oponente.',
      tipPro: 'Construye torres escalonadas manteniendo libre una columna lateral para encadenar varios drops continuos.',
      icono: Icons.whatshot_rounded,
      colorAcento: Color(0xFFFFD700),
    ),
    _TutorialStep(
      numero: '4 / 4',
      titulo: 'CUBOS METÁLICOS 4x4 (ORO & PLATA)',
      subtitulo: 'Persistencia PBR Permanente',
      descripcion:
          'Al completar un bloque de 4x4 celdas cuadradas, los bloques se fusionan en un Cubo Metálico:\n• CUBO DORADO (Monocube): Creado con 4 piezas del mismo tipo. Otorga x3 puntos y Escudo.\n• CUBO PLATEADO (Multicube): Creado combinando tipos de piezas. Otorga x2 puntos.\n• PERSISTENCIA: ¡Jamás vuelven al color de pieza original, ni aun si se rompen en líneas sueltas!',
      tipPro: 'Armar cubos de 4x4 es la técnica maestra de Tetris Now para multiplicar tu puntaje en torneos.',
      icono: Icons.shield_rounded,
      colorAcento: Color(0xFFB388FF),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _initEngine();
  }

  void _initEngine() {
    _engine = TetrisEngine(
      cols: 10,
      rows: 20,
      mode: GameMode.solo,
    );

    _ticker = createTicker((elapsed) {
      if (_lastElapsed == Duration.zero) {
        _lastElapsed = elapsed;
        return;
      }
      final dt = (elapsed - _lastElapsed).inMicroseconds / 1000000.0;
      _lastElapsed = elapsed;

      final res = _engine.update(dt);
      if (res != null && res.linesCleared > 0) {
        _audioService.play(TetrisSfx.lineClear);
      }

      if (_engine.isGameOver) {
        _engine.reset();
      }

      if (mounted) setState(() {});
    });

    _ticker.start();
  }

  void _reiniciarTablero() {
    setState(() {
      _engine.reset();
    });
    _audioService.play(TetrisSfx.move);
  }

  void _cambiarPaso(int nuevoIndex) {
    if (nuevoIndex < 0 || nuevoIndex >= _steps.length) return;
    setState(() {
      _currentStepIndex = nuevoIndex;
      _isCardExpanded = true;
    });
    _audioService.play(TetrisSfx.rotate);

    // Al llegar al paso 4, configurar un escenario visual de práctica si el tablero está vacío
    if (nuevoIndex == 3 && _engine.linesCleared == 0) {
      _configurarDemostracionMetales();
    }
  }

  void _configurarDemostracionMetales() {
    // Colocar piezas O en la base para facilitar la forja de un cubo 4x4
    _engine.reset();
    // Dejar disponible una pieza O o I para la demostración
    setState(() {});
  }

  void _finalizarGuia() async {
    _ticker.stop();
    await _logrosService.desbloquearLogro('maestro_srs');

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF070B19),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFF00E5FF), width: 2),
        ),
        title: const Row(
          children: [
            Icon(Icons.emoji_events_rounded, color: Color(0xFFFFD700), size: 28),
            SizedBox(width: 10),
            Text(
              '¡GUÍA COMPLETADA!',
              style: TextStyle(
                color: Color(0xFF00E5FF),
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
          ],
        ),
        content: const Text(
          'Has dominado los pilares fundamentales de Tetris Now: Rotación SRS, Hard Drop físico, Sistema de Combos y Forja de Cubos Metálicos 4x4.\n\n¡Estás listo para competir en el radar 1v1 y los torneos de Gameros!',
          style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00E5FF),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('VOLVER AL MENÚ', style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final step = _steps[_currentStepIndex];

    return Scaffold(
      backgroundColor: const Color(0xFF070B19),
      body: SafeArea(
        child: Column(
          children: [
            // Cabecera superior Arcade
            _buildTopBar(step),

            // Tarjeta de lección guiada Neón Arcade (colapsable)
            _buildStepCard(step),

            // Tablero CRT interactivo
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: AspectRatio(
                    aspectRatio: 10 / 20,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF03050C),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: step.colorAcento.withOpacity(0.8),
                          width: 2.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: step.colorAcento.withOpacity(0.3),
                            blurRadius: 16,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Stack(
                          children: [
                            // Tablero con CustomPainter oficial
                            CustomPaint(
                              size: Size.infinite,
                              painter: TetrisBoardPainter(
                                engine: _engine,
                                arenaTheme: ArenaTheme.cyberpunk,
                              ),
                            ),
                            // Líneas scanline CRT
                            Positioned.fill(
                              child: IgnorePointer(
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Colors.transparent,
                                        Colors.black.withOpacity(0.08),
                                      ],
                                      stops: const [0.5, 0.5],
                                      tileMode: TileMode.repeated,
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
                ),
              ),
            ),

            // Botonera de control táctil 3D para practicar
            VirtualControllerWrapper(
              onAction: (action) => _handleGameAction(action),
              initialTheme: ControllerTheme.moba,
              opacity: 1.0,
              isVisible: true,
              onToggleTheme: () {},
              onCycleOpacity: () {},
              onOpenMap: _reiniciarTablero,
              isShieldActive: _engine.isShieldActive,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(_TutorialStep step) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF0D1226),
        border: Border(bottom: BorderSide(color: Color(0xFF1E2952), width: 1.5)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'GUÍA ARCADE DE ENTRENAMIENTO',
                  style: TextStyle(
                    color: Color(0xFF00E5FF),
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    letterSpacing: 1.0,
                  ),
                ),
                Text(
                  'PASO ${step.numero} — ${step.titulo}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFFFFD700), size: 22),
            tooltip: 'Reiniciar Tablero',
            onPressed: _reiniciarTablero,
          ),
        ],
      ),
    );
  }

  Widget _buildStepCard(_TutorialStep step) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1024),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: step.colorAcento.withOpacity(0.8), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: step.colorAcento.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: step.colorAcento.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(step.icono, color: step.colorAcento, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      step.titulo,
                      style: TextStyle(
                        color: step.colorAcento,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        letterSpacing: 0.8,
                      ),
                    ),
                    Text(
                      step.subtitulo,
                      style: const TextStyle(color: Colors.white54, fontSize: 10.5, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  _isCardExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  color: Colors.white70,
                  size: 20,
                ),
                onPressed: () => setState(() => _isCardExpanded = !_isCardExpanded),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          if (_isCardExpanded) ...[
            const SizedBox(height: 8),
            Text(
              step.descripcion,
              style: const TextStyle(color: Colors.white70, fontSize: 11.5, height: 1.35),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.tips_and_updates_rounded, color: Color(0xFFFFD700), size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      step.tipPro,
                      style: const TextStyle(color: Color(0xFFFFD700), fontSize: 10.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          // Botones de navegación del tutorial
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton.icon(
                onPressed: _currentStepIndex > 0 ? () => _cambiarPaso(_currentStepIndex - 1) : null,
                icon: const Icon(Icons.arrow_back_rounded, size: 14),
                label: const Text('ANTERIOR', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white70,
                  disabledForegroundColor: Colors.white24,
                ),
              ),
              if (_currentStepIndex < _steps.length - 1)
                ElevatedButton.icon(
                  onPressed: () => _cambiarPaso(_currentStepIndex + 1),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 14),
                  label: const Text('SIGUIENTE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: step.colorAcento,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                )
              else
                ElevatedButton.icon(
                  onPressed: _finalizarGuia,
                  icon: const Icon(Icons.check_circle_rounded, size: 16),
                  label: const Text('FINALIZAR GUÍA', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E676),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _handleGameAction(GameAction action) {
    switch (action) {
      case GameAction.moveLeft:
        _engine.moveLeft();
        _audioService.play(TetrisSfx.move);
        break;
      case GameAction.moveRight:
        _engine.moveRight();
        _audioService.play(TetrisSfx.move);
        break;
      case GameAction.softDrop:
        _engine.softDrop();
        _audioService.play(TetrisSfx.softDrop);
        break;
      case GameAction.hardDrop:
        _engine.hardDrop();
        _audioService.play(TetrisSfx.hardDrop);
        break;
      case GameAction.rotateCW:
        _engine.rotate(1);
        _audioService.play(TetrisSfx.rotate);
        break;
      case GameAction.rotateCCW:
        _engine.rotate(-1);
        _audioService.play(TetrisSfx.rotate);
        break;
      case GameAction.hold:
        _engine.hold();
        _audioService.play(TetrisSfx.hold);
        break;
      case GameAction.activateShield:
        _engine.activateShield();
        break;
      case GameAction.specialAttack:
        break;
      case GameAction.pause:
        _engine.isPaused = !_engine.isPaused;
        break;
      case GameAction.reset:
        _reiniciarTablero();
        break;
    }
    setState(() {});
  }
}
