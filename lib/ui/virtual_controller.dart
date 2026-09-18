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
  final bool isShieldActive;
  final bool isVsMode;
  final bool enabled;

  const VirtualControllerWrapper({
    Key? key,
    required this.onAction,
    this.initialTheme = ControllerTheme.moba,
    this.opacity = 1.0,
    this.isVisible = true,
    required this.onToggleTheme,
    required this.onCycleOpacity,
    this.onOpenMap,
    this.isShieldActive = false,
    this.isVsMode = false,
    this.enabled = true,
  }) : super(key: key);

  void _handleSafeAction(GameAction action) {
    if (!enabled) return;
    onAction(action);
  }

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
      opacity: (enabled ? opacity : opacity * 0.45).clamp(0.1, 1.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Barra Compacta de Pausa Arcade con pulsación física
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            color: Colors.transparent,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _ArcadePausePill(
                  isVsMode: isVsMode,
                  onTap: () => _handleSafeAction(GameAction.pause),
                ),
              ],
            ),
          ),
          initialTheme == ControllerTheme.dualshock
              ? VirtualDualShockController(onAction: _handleSafeAction, onOpenMap: onOpenMap, isShieldActive: isShieldActive)
              : MobaTouchController(onAction: _handleSafeAction, onOpenMap: onOpenMap, isShieldActive: isShieldActive),
        ],
      ),
    );
  }
}

/// Pastilla física estilo botón arcade para la Pausa con feedback lumínico
class _ArcadePausePill extends StatefulWidget {
  final VoidCallback onTap;
  final bool isVsMode;
  const _ArcadePausePill({Key? key, required this.onTap, this.isVsMode = false}) : super(key: key);

  @override
  State<_ArcadePausePill> createState() => _ArcadePausePillState();
}

class _ArcadePausePillState extends State<_ArcadePausePill> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        setState(() => _isPressed = true);
        widget.onTap();
      },
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      behavior: HitTestBehavior.opaque,
      child: Transform.translate(
        offset: Offset(0, _isPressed ? 2.0 : 0.0),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: widget.isVsMode
                  ? (_isPressed
                      ? const [Color(0xFF64748B), Color(0xFF475569), Color(0xFF334155)]
                      : const [Color(0xFF475569), Color(0xFF334155), Color(0xFF1E293B)])
                  : (_isPressed
                      ? const [Color(0xFFFEF08A), Color(0xFFEAB308), Color(0xFFA16207)]
                      : const [Color(0xFFFDE047), Color(0xFFCA8A04), Color(0xFF854D0E)]),
            ),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: widget.isVsMode
                  ? (_isPressed ? Colors.white38 : const Color(0xFF64748B))
                  : (_isPressed ? Colors.white : const Color(0xFFFEF08A)),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: widget.isVsMode ? Colors.black87 : const Color(0xFF583307),
                offset: Offset(0, _isPressed ? 1.0 : 3.0),
                blurRadius: 0.5,
              ),
              if (_isPressed) ...[
                BoxShadow(
                  color: widget.isVsMode
                      ? const Color(0xFFFF1744).withOpacity(0.6)
                      : const Color(0xFFFACC15).withOpacity(0.95),
                  blurRadius: 12.0,
                  spreadRadius: 2.5,
                ),
                const BoxShadow(
                  color: Colors.white,
                  blurRadius: 3.0,
                  spreadRadius: 0.5,
                ),
              ],
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.isVsMode ? Icons.lock_outline_rounded : Icons.pause_rounded,
                size: 11,
                color: widget.isVsMode ? const Color(0xFF94A3B8) : const Color(0xFF1E293B),
              ),
              const SizedBox(width: 3),
              Text(
                widget.isVsMode ? 'ONLINE' : 'PAUSA',
                style: TextStyle(
                  color: widget.isVsMode ? const Color(0xFF94A3B8) : const Color(0xFF1E293B),
                  fontSize: 8.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Acabados de materiales para los botones arcade
enum Arcade3DTheme {
  bronze, // Cobre / Naranja profundo para acciones principales (ROTAR, DROP, ATAQUE)
  silver, // Plata brillante / Titanio para utilidades (HOLD, ESCUDO, MAPA)
  dark,   // Carbón oscuro mate con bisel plata (#CBD5E1) para cruceta
}

/// Botón Arcade Físico 3D Reactivo con sensación táctil de microswitch y fogonazo lumínico
class Arcade3DButton extends StatefulWidget {
  final VoidCallback onTap;
  final String label;
  final IconData? icon;
  final double size;
  final bool isMain;
  final Arcade3DTheme theme;
  final BorderRadius? borderRadius;
  final bool isPulsing;
  final Color? pulseGlowColor;

  const Arcade3DButton({
    Key? key,
    required this.onTap,
    required this.label,
    this.icon,
    required this.size,
    this.isMain = false,
    this.theme = Arcade3DTheme.bronze,
    this.borderRadius,
    this.isPulsing = false,
    this.pulseGlowColor,
  }) : super(key: key);

  @override
  State<Arcade3DButton> createState() => _Arcade3DButtonState();
}

class _Arcade3DButtonState extends State<Arcade3DButton> with SingleTickerProviderStateMixin {
  bool _isPressed = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _pulseAnimation = Tween<double>(begin: 0.25, end: 0.90).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    if (widget.isPulsing) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant Arcade3DButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPulsing != oldWidget.isPulsing) {
      if (widget.isPulsing) {
        _pulseController.repeat(reverse: true);
      } else {
        _pulseController.stop();
        _pulseController.reset();
      }
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isBronze = widget.theme == Arcade3DTheme.bronze;
    final bool isSilver = widget.theme == Arcade3DTheme.silver;

    // Gradientes de superficie metálica / acrílica (con destello al presionar)
    final List<Color> surfaceColors = isBronze
        ? (_isPressed
            ? const [Color(0xFFFFA726), Color(0xFFF97316), Color(0xFFC2410C)]
            : const [Color(0xFFFB923C), Color(0xFFEA580C), Color(0xFF9A3412)])
        : isSilver
            ? (_isPressed
                ? const [Colors.white, Color(0xFFE2E8F0), Color(0xFFCBD5E1)]
                : const [Color(0xFFF8FAFC), Color(0xFFCBD5E1), Color(0xFF94A3B8)])
            : (_isPressed
                ? const [Color(0xFF475569), Color(0xFF334155), Color(0xFF1E293B)]
                : const [Color(0xFF272F3D), Color(0xFF161B22), Color(0xFF0D1117)]);

    // Sombra inferior biselada (labio 3D del switch)
    final Color bevelColor = isBronze
        ? const Color(0xFF6C2005)
        : isSilver
            ? const Color(0xFF475569)
            : const Color(0xFF05080E);

    // Borde exterior biselado
    final Color borderColor = isBronze
        ? (_isPressed ? const Color(0xFFFFD54F) : const Color(0xFFFFB74D))
        : isSilver
            ? const Color(0xFFFFFFFF)
            : (_isPressed ? Colors.white : const Color(0xFFCBD5E1));

    // Color del contenido (texto e icono)
    final Color contentColor = isBronze
        ? Colors.white
        : isSilver
            ? const Color(0xFF0F172A)
            : const Color(0xFFCBD5E1);

    final double shadowDepth = _isPressed ? 1.0 : (widget.isMain ? 4.0 : 3.0);
    final double translateY = _isPressed ? (widget.isMain ? 3.0 : 2.5) : 0.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2.0, top: 1.0),
      child: GestureDetector(
        onTapDown: (_) {
          setState(() => _isPressed = true);
          widget.onTap();
        },
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        behavior: HitTestBehavior.opaque,
        child: AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, _) {
            // BoxShadows: Bisel 3D + Fogonazo lumínico reactivo al presionar
            final List<BoxShadow> shadows = [
              // 1. Bisel 3D físico que se comprime al presionar (sensación de hundimiento)
              BoxShadow(
                color: bevelColor,
                offset: Offset(0, shadowDepth),
                blurRadius: 0.5,
              ),
            ];

            if (_isPressed) {
              // 2. Fogonazo de contacto eléctrico (Microswitch switch spark)
              if (isBronze) {
                shadows.addAll([
                  BoxShadow(
                    color: const Color(0xFFFF9100).withOpacity(0.95), // Resplandor bronce/cobre intenso
                    blurRadius: widget.isMain ? 18.0 : 12.0,
                    spreadRadius: widget.isMain ? 3.5 : 2.5,
                  ),
                  const BoxShadow(
                    color: Color(0xFFFFE082), // Núcleo ámbar de contacto
                    blurRadius: 4.0,
                    spreadRadius: 1.0,
                  ),
                ]);
              } else if (isSilver) {
                shadows.addAll([
                  BoxShadow(
                    color: const Color(0xFF00E5FF).withOpacity(0.95), // Resplandor arco voltaico cian/plata
                    blurRadius: widget.isMain ? 18.0 : 12.0,
                    spreadRadius: widget.isMain ? 3.5 : 2.5,
                  ),
                  const BoxShadow(
                    color: Colors.white, // Chispa blanca del microswitch
                    blurRadius: 4.0,
                    spreadRadius: 1.0,
                  ),
                ]);
              } else {
                shadows.add(
                  BoxShadow(
                    color: const Color(0xFFCBD5E1).withOpacity(0.85),
                    blurRadius: 10.0,
                    spreadRadius: 2.0,
                  ),
                );
              }
            } else {
              // 3. Estado de reposo o respiración suave si está activo
              if (widget.isPulsing) {
                final Color pColor = widget.pulseGlowColor ?? const Color(0xFF00E5FF);
                shadows.add(
                  BoxShadow(
                    color: pColor.withOpacity(_pulseAnimation.value),
                    blurRadius: 14.0,
                    spreadRadius: 3.0,
                  ),
                );
              } else {
                shadows.add(
                  BoxShadow(
                    color: isBronze
                        ? const Color(0x44EA580C)
                        : (isSilver ? const Color(0x28CBD5E1) : const Color(0x33000000)),
                    blurRadius: widget.isMain ? 5.0 : 2.5,
                    offset: Offset(0, shadowDepth),
                  ),
                );
              }
            }

            return Transform.translate(
              offset: Offset(0, translateY),
              child: Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  shape: widget.borderRadius == null ? BoxShape.circle : BoxShape.rectangle,
                  borderRadius: widget.borderRadius,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: surfaceColors,
                  ),
                  border: Border.all(
                    color: borderColor.withOpacity(isBronze ? 0.95 : 0.90),
                    width: widget.isMain ? 2.0 : 1.3,
                  ),
                  boxShadow: shadows,
                ),
                alignment: Alignment.center,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Padding(
                    padding: const EdgeInsets.all(2.5),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (widget.icon != null)
                          Icon(
                            widget.icon,
                            color: contentColor,
                            size: widget.isMain ? 18.0 : (widget.size < 30 ? 11.0 : 13.0),
                          ),
                        if (widget.label.isNotEmpty)
                          Text(
                            widget.label,
                            style: TextStyle(
                              color: contentColor,
                              fontSize: widget.isMain ? 8.5 : (widget.size < 30 ? 5.5 : 6.5),
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.3,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
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
          color: const Color(0xFF12161F),
          border: Border.all(color: const Color(0xFFCBD5E1), width: 1.8),
          boxShadow: const [
            BoxShadow(color: Color(0x33CBD5E1), blurRadius: 4, spreadRadius: 1),
            BoxShadow(color: Color(0x88000000), offset: Offset(0, 2), blurRadius: 3),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Positioned(top: 5, child: Icon(Icons.arrow_drop_up, color: Color(0x66CBD5E1), size: 12)),
            const Positioned(bottom: 5, child: Icon(Icons.arrow_drop_down, color: Color(0x66CBD5E1), size: 12)),
            const Positioned(left: 5, child: Icon(Icons.arrow_left, color: Color(0x66CBD5E1), size: 12)),
            const Positioned(right: 5, child: Icon(Icons.arrow_right, color: Color(0x66CBD5E1), size: 12)),
            const Icon(Icons.gamepad, color: Color(0x22CBD5E1), size: 22),
            Transform.translate(
              offset: _stickOffset,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(colors: [Color(0xFF334155), Color(0xFF0F172A)]),
                  border: Border.all(color: const Color(0xFFCBD5E1), width: 1.6),
                  boxShadow: const [
                    BoxShadow(color: Color(0x66000000), offset: Offset(0, 2), blurRadius: 3),
                  ],
                ),
                child: const Icon(Icons.control_camera, color: Color(0xFFCBD5E1), size: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDpadBtn(GameAction act, IconData icon) {
    return Arcade3DButton(
      onTap: () => widget.onAction(act),
      label: '',
      icon: icon,
      size: 26,
      theme: Arcade3DTheme.dark,
      borderRadius: BorderRadius.circular(4),
    );
  }
}

class LandscapeRightControl extends StatelessWidget {
  final Function(GameAction) onAction;
  final ControllerTheme theme;
  final bool isShieldActive;

  const LandscapeRightControl({
    Key? key,
    required this.onAction,
    required this.theme,
    this.isShieldActive = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 96,
      height: 96,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Arcade3DButton(
            onTap: () => onAction(GameAction.rotateCW),
            label: 'ROTAR',
            icon: Icons.refresh,
            size: 42,
            isMain: true,
            theme: Arcade3DTheme.bronze,
          ),
          Positioned(
            top: 0,
            child: Arcade3DButton(
              onTap: () => onAction(GameAction.activateShield),
              label: 'ESC',
              icon: Icons.shield,
              size: 24,
              theme: Arcade3DTheme.silver,
              isPulsing: isShieldActive,
              pulseGlowColor: const Color(0xFF00E5FF),
            ),
          ),
          Positioned(
            left: 0,
            child: Arcade3DButton(
              onTap: () => onAction(GameAction.hardDrop),
              label: 'DROP',
              icon: Icons.keyboard_double_arrow_down_rounded,
              size: 24,
              theme: Arcade3DTheme.bronze,
            ),
          ),
          Positioned(
            right: 0,
            child: Arcade3DButton(
              onTap: () => onAction(GameAction.specialAttack),
              label: 'ATQ',
              icon: Icons.bolt,
              size: 24,
              theme: Arcade3DTheme.bronze,
            ),
          ),
          Positioned(
            bottom: 0,
            child: Arcade3DButton(
              onTap: () => onAction(GameAction.softDrop),
              label: 'DOWN',
              icon: Icons.arrow_downward_rounded,
              size: 24,
              theme: Arcade3DTheme.bronze,
            ),
          ),
          Positioned(
            top: 2,
            left: 2,
            child: Arcade3DButton(
              onTap: () => onAction(GameAction.hold),
              label: 'HOLD',
              icon: Icons.pan_tool_alt_rounded,
              size: 22,
              theme: Arcade3DTheme.silver,
            ),
          ),
        ],
      ),
    );
  }
}

/// Plantilla Vertical MOBA Arcade (Acabados en Bronce y Plata con Pulsación Física 3D)
class MobaTouchController extends StatefulWidget {
  final Function(GameAction) onAction;
  final VoidCallback? onOpenMap;
  final bool isShieldActive;

  const MobaTouchController({
    Key? key,
    required this.onAction,
    this.onOpenMap,
    this.isShieldActive = false,
  }) : super(key: key);

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

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 142,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      decoration: const BoxDecoration(
        color: Color(0xFF131620), // Carcasa gris oscuro mate
        border: Border(
          top: BorderSide(color: Color(0xFF282D3D), width: 2), // Separación de cabina arcade
        ),
      ),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: SizedBox(
            width: 326,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Stick analógico / cruceta arcade en tonos oscuros con borde plata (#CBD5E1)
                GestureDetector(
                  onPanUpdate: _onStickDrag,
                  onPanEnd: (_) => setState(() => _stickOffset = Offset.zero),
                  child: Container(
                    width: 95,
                    height: 95,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF12161F),
                      border: Border.all(color: const Color(0xFFCBD5E1), width: 2.0),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x33CBD5E1),
                          blurRadius: 6,
                          spreadRadius: 1,
                        ),
                        BoxShadow(
                          color: Color(0xAA000000),
                          offset: Offset(0, 3),
                          blurRadius: 3,
                        ),
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        const Positioned(top: 6, child: Icon(Icons.arrow_drop_up, color: Color(0x66CBD5E1), size: 14)),
                        const Positioned(bottom: 6, child: Icon(Icons.arrow_drop_down, color: Color(0x66CBD5E1), size: 14)),
                        const Positioned(left: 6, child: Icon(Icons.arrow_left, color: Color(0x66CBD5E1), size: 14)),
                        const Positioned(right: 6, child: Icon(Icons.arrow_right, color: Color(0x66CBD5E1), size: 14)),
                        const Icon(Icons.gamepad, color: Color(0x22CBD5E1), size: 24),
                        Transform.translate(
                          offset: _stickOffset,
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const RadialGradient(
                                colors: [Color(0xFF334155), Color(0xFF0F172A)],
                              ),
                              border: Border.all(color: const Color(0xFFCBD5E1), width: 1.8),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x88000000),
                                  offset: Offset(0, 3),
                                  blurRadius: 3,
                                ),
                                BoxShadow(
                                  color: Color(0x44CBD5E1),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                            child: const Icon(Icons.control_camera, color: Color(0xFFCBD5E1), size: 16),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // BOTÓN DE MAPA / ARENA CENTRADO CON ACABADO EN PLATA Y PULSACIÓN ARCADE
                Arcade3DButton(
                  onTap: widget.onOpenMap ?? () {},
                  label: 'MAPA',
                  icon: Icons.map_rounded,
                  size: 42,
                  theme: Arcade3DTheme.silver,
                ),

                // Botonera Simil Arcade (Acabados Bronce y Plata, Cero Overflow)
                SizedBox(
                  width: 146,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Fila Superior (3 botones): HOLD (Plata), ESCUDO (Plata), ATAQUE (Bronce)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          Arcade3DButton(
                            onTap: () => widget.onAction(GameAction.hold),
                            label: 'HOLD',
                            icon: Icons.pan_tool_alt_rounded,
                            theme: Arcade3DTheme.silver,
                            size: 39,
                          ),
                          Arcade3DButton(
                            onTap: () => widget.onAction(GameAction.activateShield),
                            label: 'ESCUDO',
                            icon: Icons.shield,
                            theme: Arcade3DTheme.silver,
                            size: 39,
                            isPulsing: widget.isShieldActive,
                            pulseGlowColor: const Color(0xFF00E5FF),
                          ),
                          Arcade3DButton(
                            onTap: () => widget.onAction(GameAction.specialAttack),
                            label: 'ATAQUE',
                            icon: Icons.bolt,
                            theme: Arcade3DTheme.bronze,
                            size: 39,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // Fila Inferior (2 botones): ROTAR CW (Principal, Bronce), DROP (Bronce)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          Arcade3DButton(
                            onTap: () => widget.onAction(GameAction.rotateCW),
                            label: '↻ ROTAR',
                            icon: Icons.refresh,
                            theme: Arcade3DTheme.bronze,
                            size: 45,
                            isMain: true,
                          ),
                          Arcade3DButton(
                            onTap: () => widget.onAction(GameAction.hardDrop),
                            label: 'DROP',
                            icon: Icons.keyboard_double_arrow_down_rounded,
                            theme: Arcade3DTheme.bronze,
                            size: 45,
                          ),
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

/// Plantilla Vertical DualShock Arcade
class VirtualDualShockController extends StatefulWidget {
  final Function(GameAction) onAction;
  final VoidCallback? onOpenMap;
  final bool isShieldActive;

  const VirtualDualShockController({
    Key? key,
    required this.onAction,
    this.onOpenMap,
    this.isShieldActive = false,
  }) : super(key: key);

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

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 142,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: const BoxDecoration(
        color: Color(0xFF131620), // Carcasa mate
        borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
        border: Border(top: BorderSide(color: Color(0xFF282D3D), width: 2)),
      ),
      child: Stack(
        children: [
          Positioned(
            top: 2, left: 4,
            child: Arcade3DButton(
              onTap: () => widget.onAction(GameAction.hold),
              label: 'L1 (Hold)',
              icon: Icons.pan_tool_alt_rounded,
              size: 42,
              borderRadius: BorderRadius.circular(6),
              theme: Arcade3DTheme.silver,
            ),
          ),
          Positioned(
            top: 2, right: 4,
            child: Arcade3DButton(
              onTap: () => widget.onAction(GameAction.hardDrop),
              label: 'R1 (Drop)',
              icon: Icons.keyboard_double_arrow_down_rounded,
              size: 42,
              borderRadius: BorderRadius.circular(6),
              theme: Arcade3DTheme.bronze,
            ),
          ),
          // Stick analógico arcade con borde plata (#CBD5E1)
          Positioned(
            bottom: 4, left: 8,
            child: GestureDetector(
              onPanUpdate: _onStickDrag,
              onPanEnd: (_) => setState(() => _stickOffset = Offset.zero),
              child: Container(
                width: 84, height: 84,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF12161F),
                  border: Border.all(color: const Color(0xFFCBD5E1), width: 1.8),
                  boxShadow: const [
                    BoxShadow(color: Color(0x33CBD5E1), blurRadius: 4),
                    BoxShadow(color: Color(0x88000000), offset: Offset(0, 2), blurRadius: 3),
                  ],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Icon(Icons.gamepad, color: Color(0x22CBD5E1), size: 22),
                    Transform.translate(
                      offset: _stickOffset,
                      child: Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const RadialGradient(colors: [Color(0xFF334155), Color(0xFF0F172A)]),
                          border: Border.all(color: const Color(0xFFCBD5E1), width: 1.6),
                          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4)],
                        ),
                        child: const Icon(Icons.control_camera, color: Color(0xFFCBD5E1), size: 14),
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
                Arcade3DButton(
                  onTap: widget.onOpenMap ?? () {},
                  label: 'MAPA',
                  icon: Icons.map_rounded,
                  size: 32,
                  borderRadius: BorderRadius.circular(6),
                  theme: Arcade3DTheme.silver,
                ),
                const SizedBox(height: 4),
                Arcade3DButton(
                  onTap: () => widget.onAction(GameAction.activateShield),
                  label: 'ESC',
                  icon: Icons.shield,
                  size: 26,
                  theme: Arcade3DTheme.silver,
                  isPulsing: widget.isShieldActive,
                  pulseGlowColor: const Color(0xFF00E5FF),
                ),
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
                  Positioned(
                    top: 0,
                    child: Arcade3DButton(
                      onTap: () => widget.onAction(GameAction.activateShield),
                      label: '△',
                      size: 25,
                      theme: Arcade3DTheme.silver,
                      isPulsing: widget.isShieldActive,
                      pulseGlowColor: const Color(0xFF00E5FF),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    child: Arcade3DButton(
                      onTap: () => widget.onAction(GameAction.rotateCW),
                      label: '✕',
                      size: 25,
                      theme: Arcade3DTheme.bronze,
                    ),
                  ),
                  Positioned(
                    left: 0,
                    child: Arcade3DButton(
                      onTap: () => widget.onAction(GameAction.hardDrop),
                      label: '▢',
                      size: 25,
                      theme: Arcade3DTheme.bronze,
                    ),
                  ),
                  Positioned(
                    right: 0,
                    child: Arcade3DButton(
                      onTap: () => widget.onAction(GameAction.specialAttack),
                      label: '⚡',
                      size: 25,
                      theme: Arcade3DTheme.bronze,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
