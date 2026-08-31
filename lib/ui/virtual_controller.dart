import 'package:flutter/material.dart';
import '../game/tetris_types.dart';

class VirtualControllerWrapper extends StatelessWidget {
  final Function(GameAction) onAction;
  final ControllerTheme initialTheme;
  final double opacity;
  final bool isVisible;
  final VoidCallback onToggleTheme;
  final VoidCallback onCycleOpacity;

  const VirtualControllerWrapper({
    Key? key,
    required this.onAction,
    this.initialTheme = ControllerTheme.moba,
    this.opacity = 1.0,
    this.isVisible = true,
    required this.onToggleTheme,
    required this.onCycleOpacity,
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
          // Barra de Control Rápido Adaptativa (Zero Overflow)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            color: const Color(0xFF161B22),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  onTap: onToggleTheme,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF21262D),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFF30363D)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.style, size: 11, color: Color(0xFF58A6FF)),
                        const SizedBox(width: 3),
                        Text(
                          initialTheme == ControllerTheme.moba ? "ESTILO: MOBA" : "ESTILO: PS",
                          style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: () => onAction(GameAction.reset),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        child: const Text('SELECT', style: TextStyle(color: Color(0xFF8B949E), fontSize: 8, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () => onAction(GameAction.pause),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD29922),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('START (PAUSA)', style: TextStyle(color: Colors.black, fontSize: 8, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: onCycleOpacity,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF238636),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.opacity, size: 9, color: Colors.white),
                            const SizedBox(width: 2),
                            Text(
                              opacity >= 0.9 ? '100%' : (opacity >= 0.4 ? '50%' : '25%'),
                              style: const TextStyle(color: Colors.white, fontSize: 7.5, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          initialTheme == ControllerTheme.dualshock
              ? VirtualDualShockController(onAction: onAction)
              : MobaTouchController(onAction: onAction),
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
      } else if (_stickOffset.dy < -16) {
        widget.onAction(GameAction.hardDrop);
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
            Positioned(top: 0, child: _buildDpadBtn(GameAction.hardDrop, Icons.arrow_drop_up)),
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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) Icon(icon, color: Colors.white, size: isMain ? 17 : 12),
            Text(label, style: TextStyle(color: Colors.white, fontSize: isMain ? 8 : 6, fontWeight: FontWeight.bold)),
          ],
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
  const MobaTouchController({Key? key, required this.onAction}) : super(key: key);

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
      } else if (_stickOffset.dy < -16) {
        widget.onAction(GameAction.hardDrop);
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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) Icon(icon, color: Colors.white, size: isMain ? 20 : 13),
            Text(label, style: TextStyle(color: Colors.white, fontSize: isMain ? 8.5 : 6.5, fontWeight: FontWeight.w900)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 155,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      decoration: const BoxDecoration(
        color: Color(0xFF0F141C),
        border: Border(top: BorderSide(color: Color(0xFF30363D), width: 1)),
      ),
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
                  const Icon(Icons.gamepad, color: Colors.white24, size: 28),
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

          // Botonera de habilidades MOBA con proporciones acotadas (Zero Overflow)
          SizedBox(
            width: 125, height: 125,
            child: Stack(
              alignment: Alignment.center,
              children: [
                _buildActionButton(onTap: () => widget.onAction(GameAction.rotateCW), label: 'ROTAR', icon: Icons.refresh, color: const Color(0xFF5865F2), size: 48, isMain: true),
                Positioned(top: 0, child: _buildActionButton(onTap: () => widget.onAction(GameAction.activateShield), label: 'ESCUDO', icon: Icons.shield, color: const Color(0xFF00D26A), size: 28)),
                Positioned(left: 0, child: _buildActionButton(onTap: () => widget.onAction(GameAction.hardDrop), label: 'DROP', color: const Color(0xFFF778BA), size: 28)),
                Positioned(right: 0, child: _buildActionButton(onTap: () => widget.onAction(GameAction.rotateCCW), label: '⟲', color: const Color(0xFFDA3633), size: 28)),
                Positioned(bottom: 0, child: _buildActionButton(onTap: () => widget.onAction(GameAction.softDrop), label: 'DOWN', color: const Color(0xFF00E5FF), size: 28)),
                Positioned(top: 4, left: 4, child: _buildActionButton(onTap: () => widget.onAction(GameAction.hold), label: 'HOLD', color: const Color(0xFFA000F0), size: 26)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Plantilla Vertical DualShock Compacta
class VirtualDualShockController extends StatelessWidget {
  final Function(GameAction) onAction;
  const VirtualDualShockController({Key? key, required this.onAction}) : super(key: key);

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
      height: 155,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: const BoxDecoration(
        color: Color(0xFFE0E0E0),
        borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
      ),
      child: Stack(
        children: [
          Positioned(
            top: 0, left: 4,
            child: _buildButton(onTap: () => onAction(GameAction.hold), size: 44, borderRadius: BorderRadius.circular(6), backgroundColor: const Color(0xFF263238), child: const Text('L1 (Hold)', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold))),
          ),
          Positioned(
            top: 0, right: 4,
            child: _buildButton(onTap: () => onAction(GameAction.hardDrop), size: 44, borderRadius: BorderRadius.circular(6), backgroundColor: const Color(0xFF263238), child: const Text('R1 (Drop)', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold))),
          ),
          Positioned(
            bottom: 4, left: 4,
            child: SizedBox(
              width: 82, height: 82,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned(top: 0, child: _buildButton(onTap: () => onAction(GameAction.hardDrop), size: 25, child: const Icon(Icons.arrow_drop_up, color: Colors.white, size: 18))),
                  Positioned(bottom: 0, child: _buildButton(onTap: () => onAction(GameAction.softDrop), size: 25, child: const Icon(Icons.arrow_drop_down, color: Colors.white, size: 18))),
                  Positioned(left: 0, child: _buildButton(onTap: () => onAction(GameAction.moveLeft), size: 25, child: const Icon(Icons.arrow_left, color: Colors.white, size: 18))),
                  Positioned(right: 0, child: _buildButton(onTap: () => onAction(GameAction.moveRight), size: 25, child: const Icon(Icons.arrow_right, color: Colors.white, size: 18))),
                ],
              ),
            ),
          ),
          Positioned(
            top: 10, left: 0, right: 0,
            child: Column(
              children: [
                const Text('GAMEROS', style: TextStyle(color: Color(0xFF263238), fontWeight: FontWeight.w900, fontSize: 9.5, letterSpacing: 2)),
                const SizedBox(height: 4),
                _buildButton(onTap: () => onAction(GameAction.activateShield), size: 24, backgroundColor: const Color(0xFFB0BEC5), child: const Text('G', style: TextStyle(color: Color(0xFF1A237E), fontWeight: FontWeight.bold, fontSize: 9.5))),
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
                  Positioned(top: 0, child: _buildButton(onTap: () => onAction(GameAction.activateShield), size: 25, child: const Text('△', style: TextStyle(color: Color(0xFF00E676), fontSize: 13, fontWeight: FontWeight.w900)))),
                  Positioned(bottom: 0, child: _buildButton(onTap: () => onAction(GameAction.rotateCW), size: 25, child: const Text('✕', style: TextStyle(color: Color(0xFF2979FF), fontSize: 13, fontWeight: FontWeight.w900)))),
                  Positioned(left: 0, child: _buildButton(onTap: () => onAction(GameAction.hardDrop), size: 25, child: const Text('▢', style: TextStyle(color: Color(0xFFF50057), fontSize: 13, fontWeight: FontWeight.w900)))),
                  Positioned(right: 0, child: _buildButton(onTap: () => onAction(GameAction.rotateCCW), size: 25, child: const Text('◯', style: TextStyle(color: Color(0xFFFF1744), fontSize: 13, fontWeight: FontWeight.w900)))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
