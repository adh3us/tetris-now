import 'package:flutter/material.dart';
import '../game/tetris_types.dart';

class VirtualControllerWrapper extends StatelessWidget {
  final Function(GameAction) onAction;
  final ControllerTheme initialTheme;
  final double opacity;
  final bool isVisible;
  final VoidCallback onToggleTheme;
  final VoidCallback onCycleOpacity;
  final VoidCallback? onOpenMap;

  const VirtualControllerWrapper({
    Key? key,
    required this.onAction,
    this.initialTheme = ControllerTheme.moba,
    this.opacity = 1.0,
    this.isVisible = true,
    required this.onToggleTheme,
    required this.onCycleOpacity,
    this.onOpenMap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (!isVisible || opacity <= 0.05) {
      return Container(
        height: 26,
        color: Colors.transparent,
        alignment: Alignment.center,
        child: TextButton.icon(
          onPressed: onCycleOpacity,
          icon: const Icon(Icons.gamepad, size: 13, color: Color(0xFF58A6FF)),
          label: const Text('MOSTRAR JOYSTICK VIRTUAL', style: TextStyle(color: Color(0xFF58A6FF), fontSize: 8.5, fontWeight: FontWeight.bold)),
        ),
      );
    }

    return Opacity(
      opacity: opacity.clamp(0.1, 1.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Barra Compacta de Pausa (Optimizada para espacio máximo de pantalla)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            color: Colors.transparent,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                GestureDetector(
                  onTap: () => onAction(GameAction.pause),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD29922).withOpacity(0.90),
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4)],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.pause_rounded, size: 12, color: Colors.black),
                        SizedBox(width: 3),
                        Text('PAUSA', style: TextStyle(color: Colors.black, fontSize: 8.5, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          initialTheme == ControllerTheme.dualshock
              ? VirtualDualShockController(onAction: onAction, onOpenMap: onOpenMap)
              : MobaTouchController(onAction: onAction, onOpenMap: onOpenMap),
        ],
      ),
    );
  }
}

/// Controles Separados para el Modo Horizontal (Landscape)
class LandscapeLeftControl extends StatefulWidget {
  final Function(GameAction) onAction;
  final ControllerTheme theme;

  const LandscapeLeftControl({Key? key, required this.onAction, required this.theme}) : super(key: key);

  @override
  State<LandscapeLeftControl> createState() => _LandscapeLeftControlState();
}

class _LandscapeLeftControlState extends State<LandscapeLeftControl> {
  Offset _stickOffset = Offset.zero;
  static const double _maxDist = 26.0;
  DateTime _lastMove = DateTime.now();

  void _onDrag(DragUpdateDetails d) {
    setState(() {
      final o = _stickOffset + d.delta;
      _stickOffset = o.distance <= _maxDist ? o : Offset.fromDirection(o.direction, _maxDist);
    });

    final now = DateTime.now();
    if (now.difference(_lastMove).inMilliseconds > 110) {
      if (_stickOffset.dx < -12) {
        widget.onAction(GameAction.moveLeft);
        _lastMove = now;
      } else if (_stickOffset.dx > 12) {
        widget.onAction(GameAction.moveRight);
        _lastMove = now;
      }

      if (_stickOffset.dy > 14) {
        widget.onAction(GameAction.softDrop);
        _lastMove = now;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.theme == ControllerTheme.dualshock) {
      return SizedBox(
        width: 82,
        height: 82,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(top: 0, child: _buildDpadBtn(GameAction.rotateCW, Icons.arrow_drop_up)),
            Positioned(bottom: 0, child: _buildDpadBtn(GameAction.softDrop, Icons.arrow_drop_down)),
            Positioned(left: 0, child: _buildDpadBtn(GameAction.moveLeft, Icons.arrow_left)),
            Positioned(right: 0, child: _buildDpadBtn(GameAction.moveRight, Icons.arrow_right)),
          ],
        ),
      );
    }

    return GestureDetector(
      onPanUpdate: _onDrag,
      onPanEnd: (_) => setState(() => _stickOffset = Offset.zero),
      child: Container(
        width: 82,
        height: 82,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF161B22).withOpacity(0.85),
          border: Border.all(color: const Color(0xFF30363D), width: 1.5),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Icon(Icons.gamepad, color: Colors.white24, size: 24),
            Transform.translate(
              offset: _stickOffset,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(colors: [Color(0xFF58A6FF), Color(0xFF1F6FEB)]),
                  boxShadow: [BoxShadow(color: const Color(0xFF58A6FF).withOpacity(0.5), blurRadius: 6)],
                ),
                child: const Icon(Icons.touch_app, color: Colors.white, size: 15),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDpadBtn(GameAction act, IconData icon) {
    return Listener(
      onPointerDown: (_) => widget.onAction(act),
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: const Color(0xFF21262D),
          border: Border.all(color: const Color(0xFF30363D)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(icon, color: Colors.white, size: 16),
      ),
    );
  }
}

class LandscapeRightControl extends StatelessWidget {
  final Function(GameAction) onAction;
  final ControllerTheme theme;

  const LandscapeRightControl({Key? key, required this.onAction, required this.theme}) : super(key: key);

  Widget _btn({
    required VoidCallback onTap,
    required String label,
    required Color color,
    required double size,
    IconData? icon,
    bool isMain = false,
  }) {
    return Listener(
      onPointerDown: (_) => onTap(),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color.withOpacity(0.95), color.withOpacity(0.7)],
          ),
          border: Border.all(color: Colors.white.withOpacity(0.8), width: isMain ? 2 : 1),
          boxShadow: [BoxShadow(color: color.withOpacity(0.4), blurRadius: isMain ? 6 : 3)],
        ),
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.all(2.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) Icon(icon, color: Colors.white, size: isMain ? 17 : 11),
                Text(label, style: TextStyle(color: Colors.white, fontSize: isMain ? 8 : 5.8, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 96,
      height: 96,
      child: Stack(
        alignment: Alignment.center,
        children: [
          _btn(onTap: () => onAction(GameAction.rotateCW), label: 'ROTAR', icon: Icons.refresh, color: const Color(0xFF5865F2), size: 42, isMain: true),
          Positioned(top: 0, child: _btn(onTap: () => onAction(GameAction.activateShield), label: 'ESC', icon: Icons.shield, color: const Color(0xFF00D26A), size: 24)),
          Positioned(left: 0, child: _btn(onTap: () => onAction(GameAction.hardDrop), label: 'DROP', color: const Color(0xFFF778BA), size: 24)),
          Positioned(right: 0, child: _btn(onTap: () => onAction(GameAction.rotateCCW), label: '⟲', color: const Color(0xFFDA3633), size: 24)),
          Positioned(bottom: 0, child: _btn(onTap: () => onAction(GameAction.softDrop), label: 'DOWN', color: const Color(0xFF00E5FF), size: 24)),
          Positioned(top: 2, left: 2, child: _btn(onTap: () => onAction(GameAction.hold), label: 'HOLD', color: const Color(0xFFA000F0), size: 22)),
        ],
      ),
    );
  }
}

/// Plantilla Vertical MOBA (Mobile Legends Style - Compacto y Zero Overflow)
class MobaTouchController extends StatefulWidget {
  final Function(GameAction) onAction;
  final VoidCallback? onOpenMap;
  const MobaTouchController({Key? key, required this.onAction, this.onOpenMap}) : super(key: key);

  @override
  State<MobaTouchController> createState() => _MobaTouchControllerState();
}

class _MobaTouchControllerState extends State<MobaTouchController> {
  Offset _stickOffset = Offset.zero;
  static const double _maxDistance = 28.0;
  DateTime _lastMoveTime = DateTime.now();

  void _onStickDrag(DragUpdateDetails details) {
    setState(() {
      final newOffset = _stickOffset + details.delta;
      _stickOffset = newOffset.distance <= _maxDistance ? newOffset : Offset.fromDirection(newOffset.direction, _maxDistance);
    });

    final now = DateTime.now();
    if (now.difference(_lastMoveTime).inMilliseconds > 120) {
      if (_stickOffset.dx < -12) {
        widget.onAction(GameAction.moveLeft);
        _lastMoveTime = now;
      } else if (_stickOffset.dx > 12) {
        widget.onAction(GameAction.moveRight);
        _lastMoveTime = now;
      }

      if (_stickOffset.dy > 14) {
        widget.onAction(GameAction.softDrop);
        _lastMoveTime = now;
      }
    }
  }

  Widget _buildActionButton({
    required VoidCallback onTap, required String label, required Color color, required double size,
    IconData? icon, bool isMain = false,
  }) {
    return Listener(
      onPointerDown: (_) => onTap(),
      child: Container(
        width: size, height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color.withOpacity(0.95), color.withOpacity(0.65)],
          ),
          border: Border.all(color: Colors.white.withOpacity(0.8), width: isMain ? 2.0 : 1.2),
          boxShadow: [BoxShadow(color: color.withOpacity(0.35), blurRadius: isMain ? 8 : 4)],
        ),
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.all(2.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) Icon(icon, color: Colors.white, size: isMain ? 20 : 12),
                Text(label, style: TextStyle(color: Colors.white, fontSize: isMain ? 8.5 : 5.8, fontWeight: FontWeight.w900)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 142,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      decoration: const BoxDecoration(
        color: Color(0xFF0F141C),
        border: Border(top: BorderSide(color: Color(0xFF30363D), width: 1)),
      ),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: SizedBox(
            width: 320,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Stick analógico compacto
          GestureDetector(
            onPanUpdate: _onStickDrag,
            onPanEnd: (_) => setState(() => _stickOffset = Offset.zero),
            child: Container(
              width: 95, height: 95,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF161B22).withOpacity(0.85),
                border: Border.all(color: const Color(0xFF30363D), width: 1.5),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Icon(Icons.gamepad, color: Colors.white24, size: 24),
                  Transform.translate(
                    offset: _stickOffset,
                    child: Container(
                      width: 38, height: 38,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(colors: [Color(0xFF58A6FF), Color(0xFF1F6FEB)]),
                      ),
                      child: const Icon(Icons.touch_app, color: Colors.white, size: 16),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // BOTÓN DE MAPA / ARENA CENTRADO ENTRE EL CURSOR Y LOS BOTONES
          GestureDetector(
            onTap: widget.onOpenMap,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  colors: [Color(0xFF818CF8), Color(0xFF4F46E5), Color(0xFF312E81)],
                ),
                border: Border.all(color: const Color(0xFFA5B4FC), width: 1.8),
                boxShadow: const [
                  BoxShadow(color: Color(0x666366F1), blurRadius: 10, spreadRadius: 1),
                ],
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.map_rounded, color: Colors.white, size: 19),
                  Text(
                    'MAPA',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 7.0,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Botonera 3x2 Simil Arcade (Mismo tamaño para todos, Cero Overflow)
          SizedBox(
            width: 146,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Fila Superior (3 botones): HOLD, ESCUDO (Verde), ATAQUE (Cyan)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildActionButton(onTap: () => widget.onAction(GameAction.hold), label: 'HOLD', icon: Icons.pan_tool_alt_rounded, color: const Color(0xFFA000F0), size: 40),
                    _buildActionButton(onTap: () => widget.onAction(GameAction.activateShield), label: 'ESCUDO', icon: Icons.shield, color: const Color(0xFF00D26A), size: 40),
                    _buildActionButton(onTap: () => widget.onAction(GameAction.specialAttack), label: 'ATAQUE', icon: Icons.bolt, color: const Color(0xFF00E5FF), size: 40),
                  ],
                ),
                const SizedBox(height: 6),
                // Fila Inferior (3 botones): ROTAR CCW, ROTAR CW (Principal), DROP
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildActionButton(onTap: () => widget.onAction(GameAction.rotateCCW), label: '⟲ ROTAR', icon: Icons.undo, color: const Color(0xFFDA3633), size: 40),
                    _buildActionButton(onTap: () => widget.onAction(GameAction.rotateCW), label: '↻ ROTAR', icon: Icons.refresh, color: const Color(0xFF5865F2), size: 40, isMain: true),
                    _buildActionButton(onTap: () => widget.onAction(GameAction.hardDrop), label: 'DROP', icon: Icons.keyboard_double_arrow_down_rounded, color: const Color(0xFFF778BA), size: 40),
                  ],
                ),
              ],
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

/// Plantilla Vertical DualShock con Stick Analógico y Botones PS
class VirtualDualShockController extends StatefulWidget {
  final Function(GameAction) onAction;
  final VoidCallback? onOpenMap;
  const VirtualDualShockController({Key? key, required this.onAction, this.onOpenMap}) : super(key: key);

  @override
  State<VirtualDualShockController> createState() => _VirtualDualShockControllerState();
}

class _VirtualDualShockControllerState extends State<VirtualDualShockController> {
  Offset _stickOffset = Offset.zero;
  static const double _maxDistance = 28.0;
  DateTime _lastMoveTime = DateTime.now();

  void _onStickDrag(DragUpdateDetails details) {
    setState(() {
      final newOffset = _stickOffset + details.delta;
      _stickOffset = newOffset.distance <= _maxDistance ? newOffset : Offset.fromDirection(newOffset.direction, _maxDistance);
    });

    final now = DateTime.now();
    if (now.difference(_lastMoveTime).inMilliseconds > 120) {
      if (_stickOffset.dx < -12) {
        widget.onAction(GameAction.moveLeft);
        _lastMoveTime = now;
      } else if (_stickOffset.dx > 12) {
        widget.onAction(GameAction.moveRight);
        _lastMoveTime = now;
      }

      if (_stickOffset.dy > 14) {
        widget.onAction(GameAction.softDrop);
        _lastMoveTime = now;
      }
    }
  }

  Widget _buildButton({
    required VoidCallback onTap, required Widget child, required double size,
    Color backgroundColor = const Color(0xFF212121), BorderRadius? borderRadius,
  }) {
    return Listener(
      onPointerDown: (_) => onTap(),
      child: Container(
        width: size, height: size,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: borderRadius ?? BorderRadius.circular(size / 2),
          border: Border.all(color: const Color(0xFF111111), width: 1.2),
        ),
        alignment: Alignment.center,
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 142,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: const BoxDecoration(
        color: Color(0xFFE0E0E0),
        borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
      ),
      child: Stack(
        children: [
          Positioned(
            top: 0, left: 4,
            child: _buildButton(onTap: () => widget.onAction(GameAction.hold), size: 44, borderRadius: BorderRadius.circular(6), backgroundColor: const Color(0xFF263238), child: const Text('L1 (Hold)', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold))),
          ),
          Positioned(
            top: 0, right: 4,
            child: _buildButton(onTap: () => widget.onAction(GameAction.hardDrop), size: 44, borderRadius: BorderRadius.circular(6), backgroundColor: const Color(0xFF263238), child: const Text('R1 (Drop)', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold))),
          ),
          // Stick analógico DualShock fluido (Reemplazo moderno de la cruceta)
          Positioned(
            bottom: 4, left: 8,
            child: GestureDetector(
              onPanUpdate: _onStickDrag,
              onPanEnd: (_) => setState(() => _stickOffset = Offset.zero),
              child: Container(
                width: 84, height: 84,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF212121),
                  border: Border.all(color: const Color(0xFF424242), width: 1.5),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Icon(Icons.gamepad, color: Colors.white24, size: 24),
                    Transform.translate(
                      offset: _stickOffset,
                      child: Container(
                        width: 36, height: 36,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(colors: [Color(0xFF616161), Color(0xFF1E1E1E)]),
                          boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 4)],
                        ),
                        child: const Icon(Icons.touch_app, color: Colors.white, size: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 10, left: 0, right: 0,
            child: Column(
              children: [
                GestureDetector(
                  onTap: widget.onOpenMap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF263238),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.map_rounded, size: 10, color: Color(0xFF818CF8)),
                        SizedBox(width: 2),
                        Text('MAPA', style: TextStyle(color: Colors.white, fontSize: 7.5, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                _buildButton(onTap: () => widget.onAction(GameAction.activateShield), size: 24, backgroundColor: const Color(0xFFB0BEC5), child: const Text('G', style: TextStyle(color: Color(0xFF1A237E), fontWeight: FontWeight.bold, fontSize: 9.5))),
              ],
            ),
          ),
          Positioned(
            bottom: 4, right: 4,
            child: SizedBox(
              width: 82, height: 82,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned(top: 0, child: _buildButton(onTap: () => widget.onAction(GameAction.activateShield), size: 25, child: const Text('△', style: TextStyle(color: Color(0xFF00E676), fontSize: 13, fontWeight: FontWeight.w900)))),
                  Positioned(bottom: 0, child: _buildButton(onTap: () => widget.onAction(GameAction.rotateCW), size: 25, child: const Text('✕', style: TextStyle(color: Color(0xFF2979FF), fontSize: 13, fontWeight: FontWeight.w900)))),
                  Positioned(left: 0, child: _buildButton(onTap: () => widget.onAction(GameAction.hardDrop), size: 25, child: const Text('▢', style: TextStyle(color: Color(0xFFF50057), fontSize: 13, fontWeight: FontWeight.w900)))),
                  Positioned(right: 0, child: _buildButton(onTap: () => widget.onAction(GameAction.rotateCCW), size: 25, child: const Text('◯', style: TextStyle(color: Color(0xFFFF1744), fontSize: 13, fontWeight: FontWeight.w900)))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
