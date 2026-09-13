import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import '../core/supabase_config.dart';
import '../game/tetris_engine.dart';
import '../game/tetris_types.dart';
import '../services/audio_service.dart';
import '../services/tetris_match_service.dart';
import '../services/tetris_realtime_service.dart';
import 'virtual_controller.dart';


/// Partícula luminosa de impacto y destrucción (Fase D3-1)
class VfxParticle {
  double x;
  double y;
  double vx;
  double vy;
  double size;
  double maxLife;
  double life;
  Color color;
  bool isSparkle;

  VfxParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
    required this.maxLife,
    required this.color,
    this.isSparkle = false,
  }) : life = maxLife;

  bool update(double dt) {
    x += vx * dt;
    y += vy * dt;
    vy += 180 * dt; // Gravedad suave hacia abajo
    life -= dt;
    return life > 0;
  }

  void draw(Canvas canvas) {
    final progress = (life / maxLife).clamp(0.0, 1.0);
    final paint = Paint()
      ..color = color.withOpacity(progress * 0.9)
      ..style = PaintingStyle.fill;

    if (isSparkle) {
      canvas.drawCircle(Offset(x, y), size * progress, paint);
      final glowPaint = Paint()
        ..color = color.withOpacity(progress * 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
      canvas.drawCircle(Offset(x, y), size * progress * 1.5, glowPaint);
    } else {
      canvas.drawCircle(Offset(x, y), size * progress, paint);
    }
  }
}

class TetrisGameScreen extends StatefulWidget {
  final String? matchId;
  final String? myTeamId;
  final String? opponentTeamId;
  final String? tournamentId;
  final TetrisRealtimeService? realtimeService;
  final GameMode mode;

  const TetrisGameScreen({
    Key? key,
    this.matchId,
    this.myTeamId,
    this.opponentTeamId,
    this.tournamentId,
    this.realtimeService,
    this.mode = GameMode.solo,
  }) : super(key: key);

  @override
  State<TetrisGameScreen> createState() => _TetrisGameScreenState();
}

class _TetrisGameScreenState extends State<TetrisGameScreen> with SingleTickerProviderStateMixin {
  late TetrisEngine _engine;
  late Ticker _ticker;
  Duration _lastElapsed = Duration.zero;
  Timer? _shieldTimer;
  final FocusNode _focusNode = FocusNode();
  final TetrisMatchService _matchService = TetrisMatchService();
  final TetrisAudioService _audioService = TetrisAudioService();
  // VFX Fase D3-1: Partículas y Screen Shake
  final List<VfxParticle> _particles = [];
  // Animación tipo latido/inflado para el contador de Combo
  int _lastComboValue = 0;
  double _comboPulseScale = 1.0;




  void _showMapSelectorModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F141C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: Color(0xFF5865F2), width: 1.5),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.map_rounded, color: Color(0xFF5865F2), size: 22),
                    SizedBox(width: 8),
                    Text(
                      'SELECCIONAR MAPA / ARENA',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13.5, letterSpacing: 1.2),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildMapOption(ctx, 'cyberpunk', '🌌 CYBERPUNK NEÓN', 'Rejilla neón con resplandor láser y estrellas', const Color(0xFF00E5FF)),
                _buildMapOption(ctx, 'gameros', '⚡ GAMEROS ARENA', 'Emblema oficial de Gameros con aura violeta', const Color(0xFF5865F2)),
                _buildMapOption(ctx, 'space', '🚀 ESPACIO PROFUNDO', 'Polvo cósmico, nebulosas y vacío estelar', const Color(0xFFE040FB)),
                _buildMapOption(ctx, 'retro', '🕹️ RETRO ARCADE 1989', 'Look verde fósforo clásico con scanlines', const Color(0xFF00D26A)),
              ],
            ),
          );
        },
      ),
    );
  }


  String get _selectedArena {
    switch (_currentArena) {
      case ArenaTheme.gamerosArena:
        return 'gameros';
      case ArenaTheme.deepSpace:
        return 'space';
      case ArenaTheme.retroArcade:
        return 'retro';
      case ArenaTheme.cyberpunk:
      default:
        return 'cyberpunk';
    }
  }

  void _selectArena(String id) {
    ArenaTheme theme;
    switch (id) {
      case 'gameros':
        theme = ArenaTheme.gamerosArena;
        break;
      case 'space':
        theme = ArenaTheme.deepSpace;
        break;
      case 'retro':
        theme = ArenaTheme.retroArcade;
        break;
      case 'cyberpunk':
      default:
        theme = ArenaTheme.cyberpunk;
        break;
    }
    setState(() {
      _currentArena = theme;
      final preset = arenaVisualPresets[_currentArena]!;
      _triggerImpactBanner(preset.name, sub: 'ESCENARIO ACTIVADO', color: preset.ambientColor);
    });
    _audioService.play(TetrisSfx.rotate);
    SharedPreferences.getInstance().then((p) => p.setInt('tetris_now_arena_theme', theme.index)).catchError((_) {});
  }

  Widget _buildMapOption(BuildContext ctx, String id, String title, String desc, Color accent) {
    final isSelected = _selectedArena == id;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: isSelected ? accent.withOpacity(0.18) : const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isSelected ? accent : const Color(0xFF30363D), width: isSelected ? 2 : 1),
      ),
      child: ListTile(
        onTap: () {
          _selectArena(id);
          Navigator.of(ctx).pop();
        },
        leading: Icon(Icons.palette_rounded, color: accent, size: 22),
        title: Text(title, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12)),
        subtitle: Text(desc, style: const TextStyle(color: Color(0xFF8B949E), fontSize: 10)),
        trailing: isSelected ? Icon(Icons.check_circle_rounded, color: accent, size: 20) : null,
      ),
    );
  }

  Offset _shakeOffset = Offset.zero;
  double _shakeIntensity = 0.0;
  double _shakeDuration = 0.0;

  // VFX Fase D3-2: Screen Flash, Impact Banner y Onda Expansiva del Escudo
  String? _impactBannerText;
  String? _impactBannerSub;
  Color _impactBannerColor = const Color(0xFF00E5FF);
  double _impactBannerTimer = 0.0;
  static const double _impactBannerDuration = 1.2;

  double _screenFlashOpacity = 0.0;

  // FASE D4: Arenas y Escenarios de Fondo Dinámicos
  ArenaTheme _currentArena = ArenaTheme.cyberpunk;
  double _ambientTime = 0.0;

  Future<void> _loadSavedArena() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedIndex = prefs.getInt('tetris_now_arena_theme') ?? 0;
      if (mounted && savedIndex >= 0 && savedIndex < ArenaTheme.values.length) {
        setState(() {
          _currentArena = ArenaTheme.values[savedIndex];
        });
      }
    } catch (_) {}
  }

  void _cycleArena() {
    final nextIndex = (_currentArena.index + 1) % ArenaTheme.values.length;
    setState(() {
      _currentArena = ArenaTheme.values[nextIndex];
      final preset = arenaVisualPresets[_currentArena]!;
      _triggerImpactBanner(preset.name, sub: 'ESCENARIO CAMBIADO', color: preset.ambientColor);
    });
    _audioService.play(TetrisSfx.rotate);
    SharedPreferences.getInstance().then((p) => p.setInt('tetris_now_arena_theme', nextIndex)).catchError((_) {});
  }

  double _shieldWaveProgress = -1.0;

  void _triggerImpactBanner(String text, {String? sub, Color color = const Color(0xFF00E5FF)}) {
    _impactBannerText = text;
    _impactBannerSub = sub;
    _impactBannerColor = color;
    _impactBannerTimer = _impactBannerDuration;
  }

  void _triggerScreenFlash({double opacity = 0.45}) {
    _screenFlashOpacity = opacity;
  }

  void _triggerShieldWave() {
    _shieldWaveProgress = 0.0;
  }


  void _triggerScreenShake({double intensity = 4.0, double duration = 0.15}) {
    _shakeIntensity = intensity;
    _shakeDuration = duration;
  }

  void _spawnLineClearParticles(int lineCount, CubeType tier, double boardW, double boardH) {
    final rng = Random();
    final count = 12 * lineCount;
    for (int i = 0; i < count; i++) {
      final px = rng.nextDouble() * boardW;
      final py = boardH * 0.65 + (rng.nextDouble() - 0.5) * 60;
      final angle = -pi / 2 + (rng.nextDouble() - 0.5) * 1.4; // Dispersión hacia arriba
      final speed = 70 + rng.nextDouble() * 160;

      Color color;
      if (tier == CubeType.gold) {
        color = const Color(0xFFFFD700);
      } else if (tier == CubeType.silver) {
        color = const Color(0xFFE2E8F0);
      } else if (lineCount >= 4) {
        color = const Color(0xFF00E5FF); // Tetris Cyan Neón
      } else {
        color = [
          const Color(0xFF00E5FF),
          const Color(0xFF5865F2),
          const Color(0xFFFFD700),
          const Color(0xFF00D26A),
          const Color(0xFFFF78B4),
        ][rng.nextInt(5)];
      }

      _particles.add(
        VfxParticle(
          x: px,
          y: py,
          vx: cos(angle) * speed,
          vy: sin(angle) * speed,
          size: 2.0 + rng.nextDouble() * 3.0,
          maxLife: 0.45 + rng.nextDouble() * 0.35,
          color: color,
          isSparkle: rng.nextBool(),
        ),
      );
    }
  }

  int _hiScore = 0;
  int _opponentHp = 100;

  String _combatLog = 'Partida en curso...';
  bool _isOpponentReconnecting = false;
  ControllerTheme _controllerTheme = ControllerTheme.moba;
  double _controllerOpacity = 1.0;
  bool _isControllerVisible = true;

  double _dragStartX = 0;
  double _dragStartY = 0;

  @override
  void initState() {
    super.initState();
    _loadHiScore();
    _loadSavedArena();

    // Bloqueo estricto en modo vertical para eliminar franjas de desborde
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);

    _engine = TetrisEngine(
      cols: widget.mode == GameMode.coop2v2Wide ? 20 : 10,
      rows: 20,
      mode: widget.mode,
    );

    _ticker = createTicker((elapsed) {
      if (_lastElapsed == Duration.zero) {
        _lastElapsed = elapsed;
        return;
      }
      final dt = (elapsed - _lastElapsed).inMicroseconds / 1000000.0;
      _lastElapsed = elapsed;

      // Actualizar efecto latido del combo
      if (_engine.combo != _lastComboValue) {
        if (_engine.combo > _lastComboValue && _engine.combo > 0) {
          _comboPulseScale = 1.45; // Inflado al sumar punto de combo
        }
        _lastComboValue = _engine.combo;
      }
      if (_comboPulseScale > 1.0) {
        _comboPulseScale = max(1.0, _comboPulseScale - dt * 2.8); // Desinflado elástico suave
      }

      // 1. Actualizar Partículas VFX
      for (int i = _particles.length - 1; i >= 0; i--) {
        if (!_particles[i].update(dt)) {
          _particles.removeAt(i);
        }
      }

      // 2. Actualizar Screen Shake elástico
      if (_shakeDuration > 0.0) {
        _shakeDuration -= dt;
        final progress = (_shakeDuration / 0.20).clamp(0.0, 1.0);
        final decay = _shakeIntensity * progress;
        final angle = Random().nextDouble() * 2 * pi;
        _shakeOffset = Offset(cos(angle) * decay, sin(angle) * decay);
        if (_shakeDuration <= 0.0) {
          _shakeOffset = Offset.zero;
        }
      }

      // 3. Actualizar VFX Fase D3-2 (Screen Flash, Impact Banner y Onda de Escudo)
      if (_impactBannerTimer > 0.0) {
        _impactBannerTimer -= dt;
        if (_impactBannerTimer <= 0.0) {
          _impactBannerText = null;
          _impactBannerSub = null;
        }
      }

      _ambientTime += dt;
      if (_screenFlashOpacity > 0.0) {
        _screenFlashOpacity = max(0.0, _screenFlashOpacity - dt * 3.0);
      }

      if (_shieldWaveProgress >= 0.0) {
        _shieldWaveProgress += dt * 2.2;
        if (_shieldWaveProgress > 1.0) {
          _shieldWaveProgress = -1.0;
        }
      }

      final res = _engine.update(dt);
      if (res != null) {
        _processAttackResult(res);
      }
      _checkAndUpdateHiScore();
      if (_engine.isGameOver) {
        _handleGameOver();
      }
      if (mounted) setState(() {});
    });
    _ticker.start();

    _shieldTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_engine.isShieldActive) {
        setState(() {
          _engine.updateShieldTimer();
        });
      }
    });

    if (widget.realtimeService != null) {
      widget.realtimeService!.connect(); // Conectar canal WebSocket de Realtime
      widget.realtimeService!.onIncomingAttack = (lines, tier, damageHp, diamondLines, opponentHp) {
        if (!mounted) return;
        setState(() {
          _opponentHp = opponentHp;

          // 1. Escudo de Plasma: Inmunidad total (0 daño y 0 líneas)
          if (_engine.isShieldActive) {
            _combatLog = '⚡ ¡ESCUDO ACTIVO! Ataque neutralizado al 100%.';
            _triggerImpactBanner('¡ESCUDO BLOQUEÓ!', sub: '0 DAÑO RECIBIDO', color: const Color(0xFF00D26A));
            _audioService.play(TetrisSfx.shieldActivate);
            return;
          }

          // 2. Sistema de Daño a la Vida (HP)
          // Un Tetris quita 10 HP (no inyecta basura común para evitar muertes súbitas)
          final int actualDamage = damageHp > 0 ? damageHp : (lines >= 4 ? 10 : (lines > 0 ? lines * 2 : 0));
          if (actualDamage > 0) {
            _engine.takeDamage(actualDamage);
            _audioService.play(TetrisSfx.damageReceived);
            _triggerScreenShake(intensity: 6.5, duration: 0.22);
            _triggerScreenFlash(opacity: 0.40);
            _combatLog = '⚡ ¡Recibiste -$actualDamage HP de daño!';

            if (_engine.currentHp <= 0) {
              _handleGameOver();
              return;
            }
          }

          // 3. Líneas Diamantadas Resistentes (Solo si el ataque provino de cubos especiales)
          if (diamondLines > 0) {
            _engine.receiveDiamondGarbage(diamondLines);
            _combatLog = '💎 ¡Recibiste +$diamondLines línea(s) diamantada(s)!';
            _triggerImpactBanner('¡LÍNEAS DIAMANTADAS!', sub: '+$diamondLines LÍNEAS RESISTENTES', color: const Color(0xFF00E5FF));
          } else if (tier == CubeType.gold) {
            _engine.receiveDiamondGarbage(2);
            _combatLog = '💎 ¡Recibiste +2 líneas diamantadas de Oro!';
            _triggerImpactBanner('¡LÍNEAS DIAMANTADAS ORO!', sub: '+2 LÍNEAS RESISTENTES', color: const Color(0xFFFFD700));
          } else if (tier == CubeType.silver) {
            _engine.receiveDiamondGarbage(1);
            _combatLog = '💎 ¡Recibiste +1 línea diamantada de Plata!';
            _triggerImpactBanner('¡LÍNEAS DIAMANTADAS PLATA!', sub: '+1 LÍNEA RESISTENTE', color: const Color(0xFFE2E8F0));
          }
        });
      };

      widget.realtimeService!.onOpponentConnectionChanged = (isConnected) {
        if (!mounted) return;
        setState(() {
          _isOpponentReconnecting = !isConnected;
        });
      };

      widget.realtimeService!.onMatchEnd = (winnerTeamId) {
        if (!mounted) return;
        final isVictory = winnerTeamId == widget.myTeamId;
        if (isVictory && widget.matchId != null) {
          if (widget.tournamentId != null) {
            _matchService.reportarResultadoCruceTorneo(
              matchId: widget.matchId!,
              winnerTeamId: widget.myTeamId ?? winnerTeamId,
              tournamentId: widget.tournamentId,
            );
          } else {
            _matchService.reportMatchResult(
              matchId: widget.matchId!,
              winnerTeamId: widget.myTeamId ?? winnerTeamId,
            );
          }
        }
        _showEndDialog(isVictory ? '¡VICTORIA!' : 'DERROTA');
      };

      widget.realtimeService!.onOpponentTimeout = (opponentUserId) {
        if (widget.matchId == null) return;
        // El rival se declaró abandonado por timeout real (no derrota jugada):
        // se le aplica la penalización de ELO del 15% de su rating actual.
        _matchService.penalizarAbandono(
          matchId: widget.matchId!,
          userId: opponentUserId,
        );
      };
    }
  }

  void _cycleOpacity() {
    setState(() {
      if (_controllerOpacity >= 0.9) {
        _controllerOpacity = 0.5;
        _isControllerVisible = true;
      } else if (_controllerOpacity >= 0.45) {
        _controllerOpacity = 0.2;
        _isControllerVisible = true;
      } else if (_controllerOpacity >= 0.15) {
        _controllerOpacity = 0.0;
        _isControllerVisible = false;
      } else {
        _controllerOpacity = 1.0;
        _isControllerVisible = true;
      }
    });
  }

  void _handleAction(GameAction action) {
    setState(() {
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
          if (_engine.isGameOver) _handleGameOver();
          break;
        case GameAction.hardDrop:
          _audioService.play(TetrisSfx.hardDrop);
          _triggerScreenShake(intensity: 4.5, duration: 0.14); // Shake de impacto en Hard Drop
          final res = _engine.hardDrop();
          _processAttackResult(res);
          if (_engine.isGameOver) _handleGameOver();
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
          final activated = _engine.activateShield();
          if (activated) {
            _audioService.play(TetrisSfx.shieldActivate);
            _triggerShieldWave();
            _triggerScreenShake(intensity: 4.5, duration: 0.20);
            _triggerImpactBanner('¡ESCUDO DE PLASMA!', sub: 'INMUNIDAD ACTIVA (20s)', color: const Color(0xFF00D26A));
            _combatLog = '⚡ ¡ESCUDO ACTIVADO! (20s de inmunidad) ⚡';
          }
          break;
        case GameAction.specialAttack:
          _handleSpecialAttack();
          break;
        case GameAction.pause:
          _engine.isPaused = !_engine.isPaused;
          _showPauseDialog();
          break;
        case GameAction.reset:
          _engine.reset();
          break;
        default:
          break;
      }
    });
  }

  void _showPauseDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          backgroundColor: const Color(0xFF161B22),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF30363D), width: 1.5),
          ),
          title: const Text('PAUSA', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 1.5, fontSize: 18)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Partida en pausa', style: TextStyle(color: Color(0xFF8B949E), fontSize: 12)),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    setState(() => _engine.isPaused = false);
                  },
                  icon: const Icon(Icons.play_arrow_rounded, color: Colors.white),
                  label: const Text('CONTINUAR', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF238636),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    _showControlsConfigDialog(ctx, () {
                      setModalState(() {});
                      setState(() {});
                    });
                  },
                  icon: const Icon(Icons.settings, color: Color(0xFF58A6FF)),
                  label: const Text('CONFIGURACIÓN DE MANDOS', style: TextStyle(color: Color(0xFF58A6FF), fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF58A6FF)),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    _handleAction(GameAction.reset);
                  },
                  icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
                  label: const Text('REINICIAR PARTIDA', style: TextStyle(color: Colors.white70)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF30363D)),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showControlsConfigDialog(BuildContext parentCtx, VoidCallback onUpdated) {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setConfigState) => AlertDialog(
          backgroundColor: const Color(0xFF0F141C),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF5865F2), width: 1.5),
          ),
          title: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.sports_esports, color: Color(0xFF5865F2), size: 22),
              SizedBox(width: 8),
              Text('CONFIGURACIÓN', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('DISPOSITIVO:', style: TextStyle(color: Color(0xFF8B949E), fontSize: 10.5, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF161B22),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF30363D)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.gamepad, color: Color(0xFF00D26A), size: 16),
                    SizedBox(width: 6),
                    Text('Manba one / PS5 Conectado', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const Text('ESTILO DE JOYSTICK:', style: TextStyle(color: Color(0xFF8B949E), fontSize: 10.5, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        setConfigState(() => _controllerTheme = ControllerTheme.moba);
                        setState(() => _controllerTheme = ControllerTheme.moba);
                        onUpdated();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _controllerTheme == ControllerTheme.moba ? const Color(0xFF5865F2) : const Color(0xFF21262D),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      child: const Text('MOBA (Arcade)', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        setConfigState(() => _controllerTheme = ControllerTheme.dualshock);
                        setState(() => _controllerTheme = ControllerTheme.dualshock);
                        onUpdated();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _controllerTheme == ControllerTheme.dualshock ? const Color(0xFF5865F2) : const Color(0xFF21262D),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      child: const Text('PLAYSTATION', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text('OPACIDAD DEL JOYSTICK:', style: TextStyle(color: Color(0xFF8B949E), fontSize: 10.5, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [0.25, 0.50, 0.75, 1.0].map((op) {
                  final isSelected = (_controllerOpacity - op).abs() < 0.1 && _isControllerVisible;
                  return GestureDetector(
                    onTap: () {
                      setConfigState(() {
                        _controllerOpacity = op;
                        _isControllerVisible = true;
                      });
                      setState(() {
                        _controllerOpacity = op;
                        _isControllerVisible = true;
                      });
                      onUpdated();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFF238636) : const Color(0xFF21262D),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: isSelected ? const Color(0xFF00D26A) : const Color(0xFF30363D)),
                      ),
                      child: Text('${(op * 100).toInt()}%', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  );
                }).toList()..add(
                  GestureDetector(
                    onTap: () {
                      setConfigState(() => _isControllerVisible = !_isControllerVisible);
                      setState(() => _isControllerVisible = !_isControllerVisible);
                      onUpdated();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: !_isControllerVisible ? const Color(0xFFDA3633) : const Color(0xFF21262D),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(!_isControllerVisible ? 'OFF' : 'OCULTAR', style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF5865F2)),
              child: const Text('LISTO', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _processAttackResult(AttackResult res) {
    if (res.linesCleared > 0 || _engine.lastMoveWasTSpin) {
      final tier = res.goldCubeLines > 0 ? CubeType.gold : (res.silverCubeLines > 0 ? CubeType.silver : CubeType.none);
      _spawnLineClearParticles(max(1, res.linesCleared), tier, 220, 440);

      if (_engine.lastMoveWasTSpin) {
        _triggerScreenFlash(opacity: 0.50);
        _triggerScreenShake(intensity: 7.5, duration: 0.25);
        _audioService.play(TetrisSfx.tetris);
        String tspinName = '¡T-SPIN!';
        if (res.linesCleared == 3) tspinName = '¡T-SPIN TRIPLE!';
        else if (res.linesCleared == 2) tspinName = '¡T-SPIN DOUBLE!';
        else if (res.linesCleared == 1) tspinName = '¡T-SPIN SINGLE!';
        _triggerImpactBanner(tspinName, sub: '+${res.linesSent} LÍNEAS ENVIADAS', color: const Color(0xFFE040FB));
      } else if (res.linesCleared >= 4) {
        _triggerScreenFlash(opacity: 0.55);
        _triggerScreenShake(intensity: 8.5, duration: 0.28);
        _audioService.play(TetrisSfx.tetris);
        _triggerImpactBanner('¡TETRIS!', sub: '4 LÍNEAS LIMPIAS (+4 ATAQUE)', color: const Color(0xFF00E5FF));
      } else if (res.goldCubeLines > 0) {
        _triggerScreenFlash(opacity: 0.50);
        _triggerScreenShake(intensity: 7.0, duration: 0.22);
        _triggerImpactBanner('¡MONOCUBO DE ORO!', sub: '+2500 PTS / +8 LÍNEAS', color: const Color(0xFFFFD700));
      } else if (res.silverCubeLines > 0) {
        _triggerScreenFlash(opacity: 0.40);
        _triggerScreenShake(intensity: 5.5, duration: 0.18);
        _triggerImpactBanner('¡MULTICUBO DE PLATA!', sub: '+1000 PTS / +4 LÍNEAS', color: const Color(0xFFE2E8F0));
      } else {
        _audioService.play(TetrisSfx.lineClear);
        _triggerScreenShake(intensity: 3.0 + res.linesCleared * 1.0, duration: 0.16);
      }
    }

    if (res.hpHealed > 0) {
      _combatLog = '💚 ¡COMBO x${_engine.combo}! +${res.hpHealed} HP regenerados.';
      _triggerImpactBanner('+${res.hpHealed} HP', sub: 'COMBO x${_engine.combo} REGENERACIÓN', color: const Color(0xFF00D26A));
    }

    // Envío Realtime unificado al rival en duelos 1v1 con daño de HP y líneas diamantadas
    if (widget.realtimeService != null && (res.linesSent > 0 || res.damageHp > 0 || res.diamondLines > 0)) {
      final tier = res.goldCubeLines > 0
          ? CubeType.gold
          : (res.silverCubeLines > 0 ? CubeType.silver : (res.diamondLines > 0 ? CubeType.diamond : CubeType.none));
      widget.realtimeService!.sendAttack(
        lines: res.linesSent,
        tier: tier,
        damageHp: res.damageHp,
        diamondLines: res.diamondLines,
        senderHp: _engine.currentHp,
      );
      if (res.damageHp > 0 && res.diamondLines > 0) {
        _combatLog = '¡TETRIS ESPECIAL! -${res.damageHp} HP y +${res.diamondLines} diamantadas al rival!';
      } else if (res.damageHp > 0) {
        _combatLog = '¡Ataque infligió -${res.damageHp} HP al rival!';
      } else {
        _combatLog = 'Enviaste +${res.linesSent} líneas al rival.';
      }
    }
  }

  
  Future<void> _loadHiScore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getInt('tetris_now_hiscore') ?? 0;
      if (mounted) {
        setState(() {
          _hiScore = saved;
          _engine.hiScore = saved;
        });
      }
    } catch (_) {}
  }

  void _checkAndUpdateHiScore() {
    if (_engine.score > _hiScore) {
      setState(() {
        _hiScore = _engine.score;
        _engine.hiScore = _hiScore;
      });
      SharedPreferences.getInstance().then((prefs) {
        prefs.setInt('tetris_now_hiscore', _hiScore);
      }).catchError((_) {});
    }
  }

  
  void _handleSpecialAttack() {
    // Especial 2: Ataque de basura concentrado al rival
    _audioService.play(TetrisSfx.tetris);
    if (widget.mode == GameMode.duel1v1 && widget.realtimeService != null) {
      widget.realtimeService!.sendAttack(lines: 4, damageHp: 15, senderHp: _engine.currentHp);
      setState(() => _combatLog = '¡ATAQUE ESPECIAL! -15 HP al rival.');
    } else {
      // Modo Solitario: Prueba de contraataque y bonificación de puntos
      setState(() {
        _engine.score += 1500;
        _combatLog = '¡ATAQUE ESPECIAL! (+1500 PTS)';
      });
      _checkAndUpdateHiScore();
    }
  }

  void _handleGameOver() {
    _ticker.stop();
    _audioService.play(TetrisSfx.gameOver);

    if (widget.matchId != null && widget.opponentTeamId != null) {
      widget.realtimeService?.sendKnockout();
      widget.realtimeService?.sendMatchEnd(widget.opponentTeamId!);

      if (widget.tournamentId != null) {
        _matchService.reportarResultadoCruceTorneo(
          matchId: widget.matchId!,
          winnerTeamId: widget.opponentTeamId!,
          tournamentId: widget.tournamentId,
        );
      } else {
        _matchService.reportMatchResult(
          matchId: widget.matchId!,
          winnerTeamId: widget.opponentTeamId!,
        );
      }
      _showEndDialog('DERROTA');
    } else {
      _showEndDialog('GAME OVER');
    }
  }

  void _showEndDialog(String title) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        title: Text(title, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          'Líneas limpiadas: ${_engine.linesCleared}\nLíneas enviadas: ${_engine.linesSent}',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF8B949E), fontSize: 13),
        ),
        actions: [
          Center(
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).pop();
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF5865F2)),
              child: const Text('VOLVER AL LOBBY', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      final key = event.logicalKey;

      if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.keyA) {
        _handleAction(GameAction.moveLeft);
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.keyD) {
        _handleAction(GameAction.moveRight);
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.keyS) {
        _handleAction(GameAction.softDrop);
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.keyW) {
        _handleAction(GameAction.hardDrop);
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.gameButtonA || key == LogicalKeyboardKey.keyZ) {
        _handleAction(GameAction.rotateCW);
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.gameButtonB || key == LogicalKeyboardKey.keyX) {
        _handleAction(GameAction.rotateCCW);
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.gameButtonX || key == LogicalKeyboardKey.space) {
        _handleAction(GameAction.hardDrop);
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.gameButtonY || key == LogicalKeyboardKey.gameButtonLeft2 || key == LogicalKeyboardKey.keyG) {
        _handleAction(GameAction.activateShield);
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.gameButtonLeft1 || key == LogicalKeyboardKey.keyC || key == LogicalKeyboardKey.shiftLeft) {
        _handleAction(GameAction.hold);
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.gameButtonRight1 || key == LogicalKeyboardKey.gameButtonRight2) {
        _handleAction(GameAction.hardDrop);
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.gameButtonSelect) {
        _handleAction(GameAction.reset);
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.gameButtonStart || key == LogicalKeyboardKey.enter) {
        _handleAction(GameAction.pause);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _shieldTimer?.cancel();
    _focusNode.dispose();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: const Color(0xFF080A0F),
        body: SafeArea(
          child: _buildPortraitLayout(),
        ),
      ),
    );
  }

  /// DISEÑO HORIZONTAL (CONSOLA PORTÁTIL: SWITCH / STEAM DECK) CON ZOOM MÁXIMO
  Widget _buildLandscapeLayout() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxH = constraints.maxHeight;
        final boardH = maxH - 24.0;
        final boardW = (boardH / 20.0) * _engine.cols;

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // 1. ZONA IZQUIERDA: HOLD + JOYSTICK
            SizedBox(
              width: 130,
              child: Padding(
                padding: const EdgeInsets.only(left: 6, bottom: 2),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        GestureDetector(
                          onTap: () => _handleAction(GameAction.hold),
                          child: _buildCard(
                            title: 'HOLD (L1)',
                            child: CustomPaint(
                              size: const Size(34, 34),
                              painter: TetrominoPreviewPainter(type: _engine.holdPiece),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GestureDetector(
                              onTap: () => _handleAction(GameAction.reset),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2.5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF21262D),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text('SELECT', style: TextStyle(color: Color(0xFF8B949E), fontSize: 7.5, fontWeight: FontWeight.bold)),
                              ),
                            ),
                            const SizedBox(height: 3),
                            GestureDetector(
                              onTap: _cycleOpacity,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2.5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF238636),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  _isControllerVisible ? 'JOY: ${(_controllerOpacity * 100).toInt()}%' : 'JOY: OFF',
                                  style: const TextStyle(color: Colors.white, fontSize: 7.5, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (_isControllerVisible)
                      Opacity(
                        opacity: _controllerOpacity.clamp(0.1, 1.0),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: LandscapeLeftControl(onAction: _handleAction, theme: _controllerTheme),
                        ),
                      )
                    else
                      const SizedBox(height: 50),
                  ],
                ),
              ),
            ),

            // 2. ZONA CENTRAL: TABLERO MAXIMIZADO
            SizedBox(
              width: boardW + 8,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildShieldBar(isCompact: true),
                  const SizedBox(height: 2),
                  _buildInteractiveBoard(boardW, boardH),
                  const SizedBox(height: 1),
                  Text(
                    _combatLog,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFF8B949E), fontSize: 7.5, fontFamily: 'monospace'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // 3. ZONA DERECHA: STATS + BOTONERA
            SizedBox(
              width: 130,
              child: Padding(
                padding: const EdgeInsets.only(right: 6, bottom: 2),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        GestureDetector(
                          onTap: () => _handleAction(GameAction.pause),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFD29922),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('START (PAUSA)', style: TextStyle(color: Colors.black, fontSize: 7.5, fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(width: 6),
                        _buildCard(
                          title: 'NEXT',
                          child: Row(
                            children: _engine.nextQueue.take(2).map((type) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 1.5),
                                child: CustomPaint(
                                  size: const Size(20, 16),
                                  painter: TetrominoPreviewPainter(type: type),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                    if (_isControllerVisible)
                      Opacity(
                        opacity: _controllerOpacity.clamp(0.1, 1.0),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: LandscapeRightControl(onAction: _handleAction, theme: _controllerTheme),
                        ),
                      )
                    else
                      const SizedBox(height: 50),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// DISEÑO VERTICAL (ESTÁNDAR MÓVIL)
    Widget _buildPortraitLayout() {
    return Column(
      children: [
        _buildCombatStatusBar(),

        // Área Central Dinámica: Tablero y Columnas Adaptativas (0 Overflow Garantizado)
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              const double sideW = 46.0;
              const double colGap = 3.5;
              const double reservedSideSpacing = (sideW * 2) + (colGap * 2) + 16.0;
              final double maxAvailableW = (box.maxWidth - reservedSideSpacing).clamp(100.0, 480.0);
              final double maxAvailableH = (box.maxHeight - 4.0).clamp(200.0, 950.0);

              // Aspect ratio 1:2 estricto (10 columnas x 20 filas visibles)
              double boardW = maxAvailableH * 0.5;
              double boardH = maxAvailableH;
              if (boardW > maxAvailableW) {
                boardW = maxAvailableW;
                boardH = boardW * 2.0;
              }

              return Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.center,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2.0),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Columna Izquierda: HOLD, SCORE, HI-SCORE, LÍNEAS y ESCUDO
                        SizedBox(
                          width: sideW,
                          height: boardH,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.center,
                            child: SizedBox(
                              width: sideW,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  GestureDetector(
                                    onTap: () => _handleAction(GameAction.hold),
                                    child: _buildCard(
                                      title: 'HOLD (L1)',
                                      child: CustomPaint(
                                        size: const Size(30, 30),
                                        painter: TetrominoPreviewPainter(type: _engine.holdPiece),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  _buildCard(title: 'SCORE', value: '${_engine.score}'),
                                  const SizedBox(height: 3),
                                  _buildCard(title: 'HI-SCORE', value: '$_hiScore'),
                                  const SizedBox(height: 3),
                                  _buildCard(title: 'LÍNEAS', value: '${_engine.linesCleared}'),
                                  const SizedBox(height: 3),
                                  _buildShieldCard(),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: colGap),

                        // Tablero Central Maximizado
                        _buildInteractiveBoard(boardW, boardH),
                        const SizedBox(width: colGap),

                        // Columna Derecha: NEXT & COMBO Pulsante
                        SizedBox(
                          width: sideW,
                          height: boardH,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.center,
                            child: SizedBox(
                              width: sideW,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _buildCard(
                                    title: 'NEXT',
                                    child: Column(
                                      children: _engine.nextQueue.take(3).map((type) {
                                        return Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 1.5),
                                          child: CustomPaint(
                                            size: const Size(26, 18),
                                            painter: TetrominoPreviewPainter(type: type),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  _buildPulsingComboCard(),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),

        // Barra de combate protegida contra saltos de línea (FittedBox + maxLines: 1)
        if (_combatLog.isNotEmpty)
          Container(
            height: 14,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.center,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                _combatLog,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF8B949E), fontSize: 8.5, fontFamily: 'monospace'),
              ),
            ),
          ),

        // Botonera de Control Compacta con Botón MAPA que cicla directamente de mapa
        VirtualControllerWrapper(
          onAction: _handleAction,
          initialTheme: _controllerTheme,
          opacity: _controllerOpacity,
          isVisible: _isControllerVisible,
          onOpenMap: _cycleArena,
          onToggleTheme: () {
            setState(() {
              _controllerTheme = _controllerTheme == ControllerTheme.dualshock
                  ? ControllerTheme.moba
                  : ControllerTheme.dualshock;
            });
          },
          onCycleOpacity: _cycleOpacity,
        ),
      ],
    );
  }

  int get _opponentRowsOccupied {
    for (int y = 0; y < _engine.rows; y++) {
      if (_engine.grid[y].any((c) => c != null)) {
        return _engine.rows - y;
      }
    }
    return 0;
  }

  Widget _buildCombatStatusBar() {
    final myHp = _engine.currentHp;
    final myHpRatio = (myHp / 100.0).clamp(0.0, 1.0);
    final myHpColor = myHp >= 60 ? const Color(0xFF00D26A) : (myHp >= 30 ? const Color(0xFFF59E0B) : const Color(0xFFEF4444));

    final oppHpRatio = (_opponentHp / 100.0).clamp(0.0, 1.0);
    final oppHpColor = _opponentHp >= 60 ? const Color(0xFF00E5FF) : (_opponentHp >= 30 ? const Color(0xFFF59E0B) : const Color(0xFFEF4444));

    return Container(
      height: 20,
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: const Color(0xFF30363D), width: 1),
      ),
      child: Row(
        children: [
          // Tu Barra de Vida (HP)
          Expanded(
            child: Row(
              children: [
                const Icon(Icons.favorite, size: 11, color: Color(0xFFEF4444)),
                const SizedBox(width: 3),
                Text('HP: $myHp', style: TextStyle(color: myHpColor, fontSize: 8.5, fontWeight: FontWeight.w900)),
                const SizedBox(width: 4),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: myHpRatio,
                      backgroundColor: const Color(0xFF21262D),
                      valueColor: AlwaysStoppedAnimation<Color>(myHpColor),
                      minHeight: 4,
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (widget.matchId != null) ...[
            const SizedBox(width: 10),
            // Barra de Vida del Rival (1v1)
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: oppHpRatio,
                        backgroundColor: const Color(0xFF21262D),
                        valueColor: AlwaysStoppedAnimation<Color>(oppHpColor),
                        minHeight: 4,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text('RIVAL: $_opponentHp', style: TextStyle(color: oppHpColor, fontSize: 8.5, fontWeight: FontWeight.w900)),
                  const SizedBox(width: 3),
                  const Icon(Icons.flash_on_rounded, size: 11, color: Color(0xFFFFD700)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildShieldBar({required bool isCompact}) {
    return GestureDetector(
      onDoubleTap: () => _handleAction(GameAction.activateShield),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: isCompact ? 16.0 : 12.0, vertical: 1.5),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: isCompact ? 2.5 : 4),
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: _engine.isShieldActive ? const Color(0xFFFFD700) : const Color(0xFF30363D)),
            boxShadow: _engine.isShieldActive ? [const BoxShadow(color: Color(0x66FFD700), blurRadius: 8)] : null,
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('ESCUDO DE DEFENSA (△ / Doble Tap)', style: TextStyle(color: Color(0xFF8B949E), fontSize: 8, fontWeight: FontWeight.bold)),
                  Text('${_engine.defenseEnergy} / 5 PTS', style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                children: List.generate(5, (index) {
                  final isFilled = index < _engine.defenseEnergy;
                  return Expanded(
                    child: Container(
                      height: isCompact ? 4.0 : 5.5,
                      margin: const EdgeInsets.symmetric(horizontal: 1.0),
                      decoration: BoxDecoration(
                        color: isFilled ? const Color(0xFF00D26A) : const Color(0xFF21262D),
                        borderRadius: BorderRadius.circular(2),
                        boxShadow: isFilled ? [const BoxShadow(color: Color(0x6600D26A), blurRadius: 3)] : null,
                      ),
                    ),
                  );
                }),
              ),
              if (_engine.isShieldActive)
                Padding(
                  padding: const EdgeInsets.only(top: 1.5),
                  child: Text(
                    '⚡ INMUNIDAD: ${_engine.shieldSecondsRemaining}s ⚡',
                    style: const TextStyle(color: Color(0xFFFFD700), fontSize: 8, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  
  
  
  Widget _buildCenterImpactBanner() {
    final progress = (_impactBannerTimer / _impactBannerDuration).clamp(0.0, 1.0);
    final scale = progress > 0.85 ? 1.0 + (progress - 0.85) * 1.8 : (progress < 0.2 ? progress * 5.0 : 1.0);
    final opacity = (progress * 2.5).clamp(0.0, 1.0);

    return Opacity(
      opacity: opacity,
      child: Transform.scale(
        scale: scale,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF070A0F).withOpacity(0.92),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _impactBannerColor, width: 2.2),
            boxShadow: [
              BoxShadow(color: _impactBannerColor.withOpacity(0.6), blurRadius: 18, spreadRadius: 2),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _impactBannerText!,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  letterSpacing: 1.5,
                  fontStyle: FontStyle.italic,
                  shadows: [
                    Shadow(color: _impactBannerColor, blurRadius: 10),
                  ],
                ),
              ),
              if (_impactBannerSub != null) ...[
                const SizedBox(height: 3),
                Text(
                  _impactBannerSub!,
                  style: TextStyle(
                    color: _impactBannerColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 9.5,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildComboViewer() {
    if (_engine.combo <= 0) return const SizedBox.shrink();

    final c = _engine.combo;
    Color comboColor;
    String label;
    if (c >= 5) {
      comboColor = const Color(0xFFFF007F); // Magenta Eléctrico Mega Combo
      label = 'MEGA COMBO x$c!';
    } else if (c == 4) {
      comboColor = const Color(0xFFFF6D00); // Naranja Fuego
      label = 'SUPER COMBO x4!';
    } else if (c == 3) {
      comboColor = const Color(0xFFFFD700); // Oro Neón
      label = 'TRIPLE COMBO x3!';
    } else if (c == 2) {
      comboColor = const Color(0xFF00D26A); // Verde Esmeralda
      label = 'DOUBLE COMBO x2!';
    } else {
      comboColor = const Color(0xFF00E5FF); // Cyan Neón
      label = 'COMBO x1!';
    }

    final graceProgress = (_engine.comboTimer / 3.0).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0F141C).withOpacity(0.92),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: comboColor, width: 2),
        boxShadow: [
          BoxShadow(color: comboColor.withOpacity(0.45), blurRadius: 12, spreadRadius: 1),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bolt_rounded, color: comboColor, size: 20),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 14,
              letterSpacing: 1.1,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(width: 10),
          // Barra de gracia de 3 segundos
          SizedBox(
            width: 36,
            height: 6,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: graceProgress,
                backgroundColor: Colors.white12,
                valueColor: AlwaysStoppedAnimation<Color>(comboColor),
              ),
            ),
          ),
        ],
      ),
    );
  }

  
  Widget _buildArenaButton() {
    final preset = arenaVisualPresets[_currentArena]!;
    return GestureDetector(
      onTap: _cycleArena,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: preset.ambientColor.withOpacity(0.6), width: 1),
          boxShadow: [
            BoxShadow(color: preset.ambientColor.withOpacity(0.25), blurRadius: 4),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.palette_rounded, size: 12, color: preset.ambientColor),
            const SizedBox(width: 4),
            Text(
              preset.name,
              style: TextStyle(color: preset.ambientColor, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.5),
            ),
          ],
        ),
      ),
    );
  }

  
  /// Barra de Escudo Compacta con icono y (3/5), ubicada arriba de HOLD (L1)
  Widget _buildCompactShieldCard() {
    final isFull = _engine.defenseEnergy >= 5;
    final isActive = _engine.isShieldActive;

    Color shieldColor;
    if (isActive) {
      shieldColor = const Color(0xFFFFD700);
    } else if (isFull) {
      shieldColor = const Color(0xFF00E676);
    } else {
      shieldColor = const Color(0xFF38BDF8);
    }

    return GestureDetector(
      onTap: () => _handleAction(GameAction.activateShield),
      child: Container(
        width: 48,
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 3),
        decoration: BoxDecoration(
          color: const Color(0xFF0F141C),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? const Color(0xFFFFD700) : (isFull ? const Color(0xFF00E676) : const Color(0xFF30363D)),
            width: isActive || isFull ? 1.5 : 1.0,
          ),
          boxShadow: isActive
              ? [const BoxShadow(color: Color(0x66FFD700), blurRadius: 8, spreadRadius: 1)]
              : (isFull ? [const BoxShadow(color: Color(0x4400E676), blurRadius: 6)] : null),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.shield_rounded, color: shieldColor, size: 14),
                const SizedBox(width: 2),
                Text(
                  isActive ? '${_engine.shieldSecondsRemaining}s' : '(${_engine.defenseEnergy}/5)',
                  style: TextStyle(color: shieldColor, fontSize: 8.5, fontWeight: FontWeight.w900),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) {
                final filled = index < _engine.defenseEnergy;
                return Container(
                  width: 7,
                  height: 3,
                  margin: const EdgeInsets.symmetric(horizontal: 0.8),
                  decoration: BoxDecoration(
                    color: filled ? (isActive ? const Color(0xFFFFD700) : const Color(0xFF00E676)) : const Color(0xFF21262D),
                    borderRadius: BorderRadius.circular(1),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  /// Cuadro de Combo con números a color cambiante y animación de inflado/desinflado/latido
  Widget _buildPulsingComboCard() {
    final c = _engine.combo;
    Color comboColor;
    if (c >= 7) {
      comboColor = const Color(0xFFFF1744); // Rojo supernova
    } else if (c == 6) {
      comboColor = const Color(0xFFA000F0); // Violeta plasma
    } else if (c == 5) {
      comboColor = const Color(0xFFFF007F); // Magenta eléctrico
    } else if (c == 4) {
      comboColor = const Color(0xFFFF6D00); // Naranja fuego
    } else if (c == 3) {
      comboColor = const Color(0xFFFFD700); // Oro brillante
    } else if (c == 2) {
      comboColor = const Color(0xFF00D26A); // Verde esmeralda
    } else if (c == 1) {
      comboColor = const Color(0xFF00E5FF); // Cyan neón
    } else {
      comboColor = const Color(0xFF64748B); // Gris inactivo
    }

    return Transform.scale(
      scale: _comboPulseScale,
      child: Container(
        width: 48,
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        decoration: BoxDecoration(
          color: const Color(0xFF0F141C),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: comboColor.withOpacity(0.85), width: c > 0 ? 1.5 : 1.0),
          boxShadow: c > 0
              ? [BoxShadow(color: comboColor.withOpacity(0.45), blurRadius: 8, spreadRadius: 1)]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('COMBO', style: TextStyle(color: Color(0xFF8B949E), fontSize: 7.5, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
            const SizedBox(height: 1),
            Text(
              c > 0 ? 'X$c' : 'X0',
              style: TextStyle(
                color: comboColor,
                fontSize: 13.5,
                fontWeight: FontWeight.w900,
                fontStyle: FontStyle.italic,
                letterSpacing: 0.5,
                shadows: c > 0 ? [Shadow(color: comboColor, blurRadius: 6)] : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOpponentStatusBar() {
    int maxOccupiedRow = 0;
    for (int y = 0; y < _engine.rows; y++) {
      if (_engine.grid[y].any((c) => c != null)) {
        maxOccupiedRow = _engine.rows - y;
        break;
      }
    }

    Color ledColor;
    String statusText;
    if (maxOccupiedRow >= 14) {
      ledColor = const Color(0xFFEF4444);
      statusText = 'CRÍTICO';
    } else if (maxOccupiedRow >= 8) {
      ledColor = const Color(0xFFF59E0B);
      statusText = 'ALERTA';
    } else {
      ledColor = const Color(0xFF10B981);
      statusText = 'SEGURO';
    }

    final label = widget.mode == GameMode.duel1v1 ? 'RIVAL' : 'ESTADO';

    return Container(
      width: 58,
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF0F141C),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ledColor.withOpacity(0.8), width: 1.2),
        boxShadow: [BoxShadow(color: ledColor.withOpacity(0.35), blurRadius: 6)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF8B949E), fontSize: 7.5, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 7, height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ledColor,
                  boxShadow: [BoxShadow(color: ledColor, blurRadius: 4, spreadRadius: 1)],
                ),
              ),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  statusText,
                  style: TextStyle(color: ledColor, fontSize: 8, fontWeight: FontWeight.w900),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (_engine.pendingGarbageLines > 0) ...[
            const SizedBox(height: 2),
            Text(
              '+${_engine.pendingGarbageLines} IN',
              style: const TextStyle(color: Color(0xFFEF4444), fontSize: 7.5, fontWeight: FontWeight.w900),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInteractiveBoard(double width, double height) {
    return GestureDetector(
      onTap: () => _handleAction(GameAction.rotateCW),
      onDoubleTap: () => _handleAction(GameAction.hardDrop),
      onPanStart: (details) {
        _dragStartX = details.localPosition.dx;
        _dragStartY = details.localPosition.dy;
      },
      onPanUpdate: (details) {
        final dx = details.localPosition.dx - _dragStartX;
        final dy = details.localPosition.dy - _dragStartY;

        if (dx.abs() > 14) {
          if (dx > 0) {
            _handleAction(GameAction.moveRight);
          } else {
            _handleAction(GameAction.moveLeft);
          }
          _dragStartX = details.localPosition.dx;
        }

        if (dy > 18) {
          _handleAction(GameAction.softDrop);
          _dragStartY = details.localPosition.dy;
        } else if (dy < -26) {
          _handleAction(GameAction.hardDrop);
          _dragStartY = details.localPosition.dy;
        }
      },
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFF30363D), width: 1.8),
          borderRadius: BorderRadius.circular(6),
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 8)],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: Size(width, height),
                painter: TetrisBoardPainter(
                  engine: _engine,
                  particles: _particles,
                  screenFlashOpacity: _screenFlashOpacity,
                  shieldWaveProgress: _shieldWaveProgress,
                  arenaTheme: _currentArena,
                  ambientTime: _ambientTime,
                  shakeOffset: _shakeOffset,
                ),
              ),
              if (_impactBannerText != null)
                _buildCenterImpactBanner(),
            ],
          ),
        ),
      ),
    );
  }

    /// Tarjeta de Escudo compacta para la columna izquierda (debajo de LÍNEAS)
  Widget _buildShieldCard() {
    final bool isActive = _engine.isShieldActive;
    final int energy = _engine.defenseEnergy;
    final bool isReady = energy >= 5;

    final Color glowColor = isActive
        ? const Color(0xFFFFD700)
        : isReady
            ? const Color(0xFF00D26A)
            : const Color(0xFF58A6FF);

    return GestureDetector(
      onTap: () => _handleAction(GameAction.activateShield),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 3.0, horizontal: 2.0),
        decoration: BoxDecoration(
          color: const Color(0xFF0F141C),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: glowColor.withOpacity(isActive || isReady ? 0.9 : 0.4),
            width: isActive ? 1.8 : 1.0,
          ),
          boxShadow: (isActive || isReady)
              ? [BoxShadow(color: glowColor.withOpacity(0.40), blurRadius: 6, spreadRadius: 1)]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'ESCUDO',
                style: TextStyle(color: Color(0xFF8B949E), fontSize: 7.0, fontWeight: FontWeight.bold, letterSpacing: 0.5),
              ),
            ),
            const SizedBox(height: 1.5),
            Icon(
              isActive ? Icons.shield : (isReady ? Icons.shield : Icons.shield_outlined),
              size: 15,
              color: glowColor,
            ),
            const SizedBox(height: 1.5),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                isActive ? '${_engine.shieldSecondsRemaining}s' : '$energy/5',
                style: TextStyle(
                  color: isActive ? const Color(0xFFFFD700) : (isReady ? const Color(0xFF00D26A) : Colors.white),
                  fontSize: 9.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) {
                final filled = index < energy;
                return Container(
                  width: 4,
                  height: 2.5,
                  margin: const EdgeInsets.symmetric(horizontal: 0.5),
                  decoration: BoxDecoration(
                    color: filled ? (isActive ? const Color(0xFFFFD700) : const Color(0xFF00D26A)) : const Color(0xFF21262D),
                    borderRadius: BorderRadius.circular(1),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard({required String title, String? value, Widget? child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 2.0, vertical: 2.5),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(title, style: const TextStyle(color: Color(0xFF8B949E), fontSize: 7.0, fontWeight: FontWeight.bold), maxLines: 1),
          ),
          const SizedBox(height: 1.5),
          if (value != null)
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 10.0, fontWeight: FontWeight.bold), maxLines: 1),
            )
          else if (child != null)
            child,
        ],
      ),
    );
  }
}

/// CustomPainter: Sistema Gráfico 3D Neón & Metálico (Fase D1)
/// Inspirado en 'The New Tetris' (Metales PBR 4x4) y 'Tetris Effect' (Glow, Biseles y Holograma)
class TetrisBoardPainter extends CustomPainter {
  final TetrisEngine engine;
  final List<VfxParticle> particles;
  final double screenFlashOpacity;
  final double shieldWaveProgress;

  final ArenaTheme arenaTheme;
  final double ambientTime;
  final Offset shakeOffset;

  TetrisBoardPainter({
    required this.engine,
    this.particles = const [],
    this.screenFlashOpacity = 0.0,
    this.shieldWaveProgress = -1.0,
    this.arenaTheme = ArenaTheme.cyberpunk,
    this.ambientTime = 0.0,
    this.shakeOffset = Offset.zero,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    if (shakeOffset != Offset.zero) {
      canvas.translate(shakeOffset.dx, shakeOffset.dy);
    }

    final blockW = size.width / engine.cols;
    final int visibleRows = engine.rows > 20 ? 20 : engine.rows;
    final blockH = size.height / visibleRows;
    final int startRow = engine.rows > 20 ? engine.rows - 20 : 0;

    final preset = arenaVisualPresets[arenaTheme] ?? arenaVisualPresets[ArenaTheme.cyberpunk]!;

    // 0. Fondo de Escenario / Arena con Profundidad Radial
    final bgRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final bgPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.0, -0.2),
        radius: 1.25,
        colors: preset.bgGradient,
      ).createShader(bgRect);
    canvas.drawRect(bgRect, bgPaint);

    // Screen Flash cinemático en jugadas maestras
    if (screenFlashOpacity > 0.0) {
      final flashPaint = Paint()..color = Colors.white.withOpacity(screenFlashOpacity * 0.40);
      canvas.drawRect(bgRect, flashPaint);
    }

    // Onda Expansiva de Plasma al activar el Escudo
    if (shieldWaveProgress >= 0.0) {
      final waveY = size.height * (1.0 - shieldWaveProgress);
      final wavePaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            const Color(0xFF00D26A).withOpacity((1.0 - shieldWaveProgress) * 0.75),
            Colors.transparent,
          ],
        ).createShader(Rect.fromLTWH(0, waveY - 20, size.width, 40));
      canvas.drawRect(Rect.fromLTWH(0, waveY - 20, size.width, 40), wavePaint);
    }

    // Halo protector activo del Escudo
    if (engine.isShieldActive) {
      final shieldHaloPaint = Paint()
        ..color = const Color(0xFF00D26A).withOpacity(0.50)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 5.0);
      canvas.drawRect(bgRect, shieldHaloPaint);
    }

    // Grilla Cyber-Laser con color temático de la Arena seleccionada
    final gridLinePaint = Paint()
      ..color = preset.gridColor
      ..strokeWidth = 0.6;
    for (int c = 1; c < engine.cols; c++) {
      canvas.drawLine(Offset(c * blockW, 0), Offset(c * blockW, size.height), gridLinePaint);
    }
    for (int r = 1; r < visibleRows; r++) {
      canvas.drawLine(Offset(0, r * blockH), Offset(size.width, r * blockH), gridLinePaint);
    }

    // Línea de Alerta / Peligro temática
    final dangerPaint = Paint()
      ..color = preset.dangerColor
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(0, 4 * blockH), Offset(size.width, 4 * blockH), dangerPaint);

    final Set<String> drawnCubeCells = {};

    // 1. DIBUJAR CUBOS 4x4 COMPLETOS COMO UN SOLO BLOQUE MACIZO MONOLÍTICO
    for (int y = startRow; y <= engine.rows - 4; y++) {
      for (int x = 0; x <= engine.cols - 4; x++) {
        final first = engine.grid[y][x];
        if (first != null && (first.cubeType == CubeType.gold || first.cubeType == CubeType.silver)) {
          final targetCube = first.cubeType;
          bool is4x4 = true;
          for (int r = 0; r < 4; r++) {
            for (int c = 0; c < 4; c++) {
              final cell = engine.grid[y + r][x + c];
              if (cell == null || cell.cubeType != targetCube) {
                is4x4 = false;
                break;
              }
            }
            if (!is4x4) break;
          }

          if (is4x4) {
            final slabRect = Rect.fromLTWH(
              x * blockW + 0.8,
              (y - startRow) * blockH + 0.8,
              4 * blockW - 1.6,
              4 * blockH - 1.6,
            );

            if (targetCube == CubeType.gold) {
              _drawMonolithicGoldSlab(canvas, slabRect);
            } else {
              _drawMonolithicSilverSlab(canvas, slabRect);
            }

            for (int r = 0; r < 4; r++) {
              for (int c = 0; c < 4; c++) {
                drawnCubeCells.add('${x + c}_${y + r}');
              }
            }
          }
        }
      }
    }

    // 2. DIBUJAR CELDAS RESTANTES (CON FUSIÓN CONTINUA LISA Y ANIMACIÓN DE CASCADA)
    for (int y = startRow; y < engine.rows; y++) {
      for (int x = 0; x < engine.cols; x++) {
        if (drawnCubeCells.contains('${x}_${y}')) continue;

        final cell = engine.grid[y][x];
        if (cell != null) {
          final topConn = (y > 0 && _isSamePiece(cell, engine.grid[y - 1][x]));
          final bottomConn = (y < engine.rows - 1 && _isSamePiece(cell, engine.grid[y + 1][x]));
          final leftConn = (x > 0 && _isSamePiece(cell, engine.grid[y][x - 1]));
          final rightConn = (x < engine.cols - 1 && _isSamePiece(cell, engine.grid[y][x + 1]));

          // Offset de deslizamiento fluido si está cayendo por cascada
          double slideY = 0.0;
          if (engine.isCascading && engine.cascadeSlideProgress > 0.0) {
            final dropRows = engine.cascadeDropDistances['${x}_${y}'] ?? 0;
            slideY = dropRows * engine.cascadeSlideProgress * blockH;
          }

          _drawConnectedCell(
            canvas: canvas,
            x: x,
            y: y - startRow,
            blockW: blockW,
            blockH: blockH,
            cell: cell,
            topConn: topConn,
            bottomConn: bottomConn,
            leftConn: leftConn,
            rightConn: rightConn,
            slideY: slideY,
            boardSize: size,
          );
        }
      }
    }

    // 3. Sombra Holográfica de Caída (Ghost Piece - Tetris Effect Glow)
    if (engine.currentPiece != null && !engine.isGameOver) {
      final piece = engine.currentPiece!;
      final shape = tetrominoShapes[piece.type]![piece.rotation];
      final ghostPos = engine.getGhostPosition();
      final pieceColor = tetrominoColors[piece.type] ?? const Color(0xFF00E5FF);

      for (int r = 0; r < shape.length; r++) {
        for (int c = 0; c < shape[r].length; c++) {
          if (shape[r][c] != 0) {
            final gx = (ghostPos.x + c) * blockW;
            final gy = (ghostPos.y - startRow + r) * blockH;
            if (gy < 0) continue;
            _drawGhostCell(canvas, gx, gy, blockW, blockH, pieceColor);
          }
        }
      }

      // 4. Pieza Activa en el Aire (CUBITOS MÁS PEQUEÑOS INDIVIDUALES MIENTRAS CAE)
      final smoothY = engine.getRenderY();
      for (int r = 0; r < shape.length; r++) {
        for (int c = 0; c < shape[r].length; c++) {
          if (shape[r][c] != 0) {
            final px = (piece.position.x + c) * blockW;
            final py = (smoothY - startRow + r) * blockH;
            if (py < 0) continue;
            _drawIndividualCube(
              canvas: canvas,
              x: px,
              y: py,
              w: blockW,
              h: blockH,
              type: piece.type,
            );
          }
        }
      }
    }

    // 5. Renderizado de Partículas de Impacto y Destrucción (VFX Fase D3-1)
    for (final p in particles) {
      p.draw(canvas);
    }

    canvas.restore();
  }

  /// Comprueba si dos celdas contiguas pertenecen a la misma pieza para fusionarse
  bool _isSamePiece(Cell c1, Cell? c2) {
    if (c2 == null) return false;
    // Cubos metálicos de Oro o Plata siempre se fusionan entre sí para mantener su estructura lisa
    if (c1.cubeType != CubeType.none) {
      return c2.cubeType == c1.cubeType;
    }
    // Fichas normales: se fusionan si fueron colocadas juntas (mismo pieceId)
    if (c1.pieceId > 0 && c2.pieceId == c1.pieceId) {
      return c2.type == c1.type;
    }
    return false;
  }

  /// Renderizado de Bloque Monolítico 4x4 de Plata / Cromo (The New Tetris)
  void _drawMonolithicSilverSlab(Canvas canvas, Rect rect) {
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4.0));

    // 1. Resplandor / Halo exterior de titanio reflectante
    final glowPaint = Paint()
      ..color = const Color(0xFFE2E8F0).withOpacity(0.40)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 6.0);
    canvas.drawRRect(rrect, glowPaint);

    // 2. Base metálica continua de cromo espejo de una sola pieza (4x4)
    final silverGradient = const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(0xFFFFFFFF),
        Color(0xFFF1F5F9),
        Color(0xFFCBD5E1),
        Color(0xFF64748B),
        Color(0xFF334155),
        Color(0xFFE2E8F0),
      ],
      stops: [0.0, 0.18, 0.45, 0.72, 0.90, 1.0],
    ).createShader(rect);

    final basePaint = Paint()..shader = silverGradient;
    canvas.drawRRect(rrect, basePaint);

    // 3. Faceta interna de lingote macizo (Embossed Plate)
    const inset = 3.5;
    final innerRect = Rect.fromLTWH(rect.left + inset, rect.top + inset, rect.width - inset * 2, rect.height - inset * 2);
    final innerRRect = RRect.fromRectAndRadius(innerRect, const Radius.circular(2.5));

    final innerSilver = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFF8FAFC), Color(0xFFE2E8F0), Color(0xFF94A3B8)],
        stops: [0.0, 0.4, 1.0],
      ).createShader(innerRect);
    canvas.drawRRect(innerRRect, innerSilver);

    // 4. Haz diagonal de destello resplandeciente a través de TODO el bloque 4x4
    final shinePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Colors.white.withOpacity(0.80), Colors.white.withOpacity(0.0)],
        stops: const [0.0, 0.65],
      ).createShader(innerRect);

    final shinePath = Path()
      ..moveTo(innerRect.left, innerRect.top)
      ..lineTo(innerRect.left + innerRect.width * 0.85, innerRect.top)
      ..lineTo(innerRect.left, innerRect.top + innerRect.height * 0.85)
      ..close();
    canvas.drawPath(shinePath, shinePaint);

    // 5. Marco biselado exterior
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    canvas.drawRRect(rrect, borderPaint);
  }

  /// Renderizado de Bloque Monolítico 4x4 de Oro Puro (The New Tetris)
  void _drawMonolithicGoldSlab(Canvas canvas, Rect rect) {
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4.0));

    // 1. Resplandor solar exterior dorado
    final glowPaint = Paint()
      ..color = const Color(0xFFFFD700).withOpacity(0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 6.0);
    canvas.drawRRect(rrect, glowPaint);

    // 2. Base metálica continua de oro puro de una sola pieza (4x4)
    final goldGradient = const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(0xFFFFFDE7),
        Color(0xFFFFE082),
        Color(0xFFFFD700),
        Color(0xFFFFB300),
        Color(0xFFB78103),
        Color(0xFFFFE082),
      ],
      stops: [0.0, 0.18, 0.42, 0.68, 0.90, 1.0],
    ).createShader(rect);

    final basePaint = Paint()..shader = goldGradient;
    canvas.drawRRect(rrect, basePaint);

    // 3. Faceta interna de lingote macizo
    const inset = 3.5;
    final innerRect = Rect.fromLTWH(rect.left + inset, rect.top + inset, rect.width - inset * 2, rect.height - inset * 2);
    final innerRRect = RRect.fromRectAndRadius(innerRect, const Radius.circular(2.5));

    final innerGold = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFFF9C4), Color(0xFFFFD700), Color(0xFFC69214)],
        stops: [0.0, 0.35, 1.0],
      ).createShader(innerRect);
    canvas.drawRRect(innerRRect, innerGold);

    // 4. Haz diagonal de destello solar
    final shinePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Colors.white.withOpacity(0.85), Colors.white.withOpacity(0.0)],
        stops: const [0.0, 0.65],
      ).createShader(innerRect);

    final shinePath = Path()
      ..moveTo(innerRect.left, innerRect.top)
      ..lineTo(innerRect.left + innerRect.width * 0.85, innerRect.top)
      ..lineTo(innerRect.left, innerRect.top + innerRect.height * 0.85)
      ..close();
    canvas.drawPath(shinePath, shinePaint);

    // 5. Marco biselado exterior
    final borderPaint = Paint()
      ..color = const Color(0xFFFFFBEA)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    canvas.drawRRect(rrect, borderPaint);
  }

  /// Renderizado de Celda Conectada y Lisa (Estilo 'The New Tetris')
  void _drawConnectedCell({
    required Canvas canvas,
    required int x,
    required int y,
    required double blockW,
    required double blockH,
    required Cell cell,
    required bool topConn,
    required bool bottomConn,
    required bool leftConn,
    required bool rightConn,
    required double slideY,
    required Size boardSize,
  }) {
    final double left = leftConn ? x * blockW : x * blockW + 1.0;
    final double right = rightConn ? (x + 1) * blockW : (x + 1) * blockW - 1.0;
    final double top = topConn ? y * blockH + slideY : y * blockH + 1.0 + slideY;
    final double bottom = bottomConn ? (y + 1) * blockH + slideY : (y + 1) * blockH - 1.0 + slideY;
    final cellRect = Rect.fromLTRB(left, top, right, bottom);

    // REGLA CRÍTICA: SI EL BLOQUE ES PARTE O REMANENTE DE UN CUBO ESPECIAL, NUNCA PIERDE SU CONDICIÓN!
    if (cell.cubeType == CubeType.silver) {
      _drawSmoothSilver(canvas, cellRect, topConn, bottomConn, leftConn, rightConn, boardSize);
      return;
    }
    if (cell.cubeType == CubeType.gold) {
      _drawSmoothGold(canvas, cellRect, topConn, bottomConn, leftConn, rightConn, boardSize);
      return;
    }
    if (cell.cubeType == CubeType.diamond) {
      _drawSmoothDiamond(canvas, cellRect, topConn, bottomConn, leftConn, rightConn, boardSize);
      return;
    }

    final baseColor = tetrominoColors[cell.type] ?? const Color(0xFF00E5FF);
    final HSLColor hsl = HSLColor.fromColor(baseColor);
    final Color topLight = hsl.withLightness((hsl.lightness + 0.22).clamp(0.0, 1.0)).toColor();
    final Color darkShadow = hsl.withLightness((hsl.lightness - 0.26).clamp(0.0, 1.0)).toColor();

    // Relleno continuo liso de color sin grietas internas
    final bodyPaint = Paint()..color = baseColor;
    canvas.drawRect(cellRect, bodyPaint);

    // Bisel perimetral 3D exterior (únicamente donde NO hay conexión con otra celda)
    const bevel = 2.4;
    if (!topConn) {
      final p = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [topLight.withOpacity(0.95), baseColor],
        ).createShader(Rect.fromLTWH(left, top, right - left, bevel));
      canvas.drawRect(Rect.fromLTWH(left, top, right - left, bevel), p);
    }
    if (!leftConn) {
      final p = Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [topLight.withOpacity(0.95), baseColor],
        ).createShader(Rect.fromLTWH(left, top, bevel, bottom - top));
      canvas.drawRect(Rect.fromLTWH(left, top, bevel, bottom - top), p);
    }
    if (!bottomConn) {
      final p = Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [darkShadow.withOpacity(0.95), baseColor],
        ).createShader(Rect.fromLTWH(left, bottom - bevel, right - left, bevel));
      canvas.drawRect(Rect.fromLTWH(left, bottom - bevel, right - left, bevel), p);
    }
    if (!rightConn) {
      final p = Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
          colors: [darkShadow.withOpacity(0.95), baseColor],
        ).createShader(Rect.fromLTWH(right - bevel, top, bevel, bottom - top));
      canvas.drawRect(Rect.fromLTWH(right - bevel, top, bevel, bottom - top), p);
    }

    // Destello de esquina superior-izquierda si es vértice exterior
    if (!topConn && !leftConn) {
      final gleamPaint = Paint()..color = Colors.white.withOpacity(0.70);
      canvas.drawCircle(Offset(left + 2.4, top + 2.4), 1.6, gleamPaint);
    }

    // Borde perimetral exterior nítido
    final borderPaint = Paint()
      ..color = Colors.white.withOpacity(0.35)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;

    final Path borderPath = Path();
    if (!topConn) { borderPath.moveTo(left, top); borderPath.lineTo(right, top); }
    if (!bottomConn) { borderPath.moveTo(left, bottom); borderPath.lineTo(right, bottom); }
    if (!leftConn) { borderPath.moveTo(left, top); borderPath.lineTo(left, bottom); }
    if (!rightConn) { borderPath.moveTo(right, top); borderPath.lineTo(right, bottom); }
    canvas.drawPath(borderPath, borderPaint);
  }

  /// Renderizado de Celda Plateada Conectada (HOMOGÉNEA Y LISA, SIN GRILLAS NI CUADROS INTERNOS)
  void _drawSmoothSilver(Canvas canvas, Rect rect, bool topConn, bool bottomConn, bool leftConn, bool rightConn, Size boardSize) {
    // Fondo cromado homogéneo continuo a través del tablero
    final silverBase = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFFFFFFFF),
          Color(0xFFE2E8F0),
          Color(0xFF94A3B8),
          Color(0xFF475569),
        ],
      ).createShader(Rect.fromLTWH(0, 0, boardSize.width, boardSize.height));
    canvas.drawRect(rect, silverBase);

    // Bisel perimetral de cromo únicamente en los bordes exteriores libres
    const bevel = 2.4;
    if (!topConn) {
      final p = Paint()..color = Colors.white;
      canvas.drawRect(Rect.fromLTWH(rect.left, rect.top, rect.width, bevel), p);
    }
    if (!leftConn) {
      final p = Paint()..color = const Color(0xFFF1F5F9);
      canvas.drawRect(Rect.fromLTWH(rect.left, rect.top, bevel, rect.height), p);
    }
    if (!bottomConn) {
      final p = Paint()..color = const Color(0xFF1E293B);
      canvas.drawRect(Rect.fromLTWH(rect.left, rect.bottom - bevel, rect.width, bevel), p);
    }
    if (!rightConn) {
      final p = Paint()..color = const Color(0xFF475569);
      canvas.drawRect(Rect.fromLTWH(rect.right - bevel, rect.top, bevel, rect.height), p);
    }

    // Brillo en esquina superior izquierda exterior
    if (!topConn && !leftConn) {
      final gleam = Paint()..color = Colors.white;
      canvas.drawCircle(Offset(rect.left + 3.0, rect.top + 3.0), 2.0, gleam);
    }

    // Borde de acero perimetral exterior
    final borderPaint = Paint()
      ..color = Colors.white.withOpacity(0.85)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    final Path bPath = Path();
    if (!topConn) { bPath.moveTo(rect.left, rect.top); bPath.lineTo(rect.right, rect.top); }
    if (!bottomConn) { bPath.moveTo(rect.left, rect.bottom); bPath.lineTo(rect.right, rect.bottom); }
    if (!leftConn) { bPath.moveTo(rect.left, rect.top); bPath.lineTo(rect.left, rect.bottom); }
    if (!rightConn) { bPath.moveTo(rect.right, rect.top); bPath.lineTo(rect.right, rect.bottom); }
    canvas.drawPath(bPath, borderPaint);
  }

  /// Renderizado de Celda Dorada Conectada (HOMOGÉNEA Y LISA, SIN GRILLAS NI CUADROS INTERNOS)
    void _drawSmoothDiamond(Canvas canvas, Rect rect, bool top, bool bottom, bool left, bool right, Size boardSize) {
    final rrect = RRect.fromRectAndCorners(
      rect,
      topLeft: (!top && !left) ? const Radius.circular(3.0) : Radius.zero,
      topRight: (!top && !right) ? const Radius.circular(3.0) : Radius.zero,
      bottomLeft: (!bottom && !left) ? const Radius.circular(3.0) : Radius.zero,
      bottomRight: (!bottom && !right) ? const Radius.circular(3.0) : Radius.zero,
    );

    final diamondShader = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: const [
        Color(0xFFFFFFFF),
        Color(0xFFE0F7FA),
        Color(0xFF00E5FF),
        Color(0xFF0097A7),
        Color(0xFFE0F7FA),
      ],
      stops: const [0.0, 0.25, 0.55, 0.85, 1.0],
    ).createShader(rect);

    final fillPaint = Paint()..shader = diamondShader;
    canvas.drawRRect(rrect, fillPaint);

    final borderPaint = Paint()
      ..color = Colors.white.withOpacity(0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    canvas.drawRRect(rrect, borderPaint);

    final shinePaint = Paint()
      ..color = Colors.white.withOpacity(0.45)
      ..strokeWidth = 1.0;
    canvas.drawLine(rect.topLeft + const Offset(2, 2), rect.bottomRight - const Offset(2, 2), shinePaint);
  }

  void _drawSmoothGold(Canvas canvas, Rect rect, bool topConn, bool bottomConn, bool leftConn, bool rightConn, Size boardSize) {
    // Fondo de oro puro homogéneo continuo a través del tablero
    final goldBase = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFFFFFDF0),
          Color(0xFFFFD700),
          Color(0xFFC69214),
          Color(0xFF78350F),
        ],
      ).createShader(Rect.fromLTWH(0, 0, boardSize.width, boardSize.height));
    canvas.drawRect(rect, goldBase);

    // Bisel perimetral de oro macizo únicamente en los bordes exteriores libres
    const bevel = 2.4;
    if (!topConn) {
      final p = Paint()..color = const Color(0xFFFFFDE7);
      canvas.drawRect(Rect.fromLTWH(rect.left, rect.top, rect.width, bevel), p);
    }
    if (!leftConn) {
      final p = Paint()..color = const Color(0xFFFFE082);
      canvas.drawRect(Rect.fromLTWH(rect.left, rect.top, bevel, rect.height), p);
    }
    if (!bottomConn) {
      final p = Paint()..color = const Color(0xFF78350F);
      canvas.drawRect(Rect.fromLTWH(rect.left, rect.bottom - bevel, rect.width, bevel), p);
    }
    if (!rightConn) {
      final p = Paint()..color = const Color(0xFFB45309);
      canvas.drawRect(Rect.fromLTWH(rect.right - bevel, rect.top, bevel, rect.height), p);
    }

    // Brillo en esquina superior izquierda exterior
    if (!topConn && !leftConn) {
      final gleam = Paint()..color = const Color(0xFFFFFFEE);
      canvas.drawCircle(Offset(rect.left + 3.0, rect.top + 3.0), 2.0, gleam);
    }

    // Borde de oro perimetral exterior
    final borderPaint = Paint()
      ..color = const Color(0xFFFFFBEA)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    final Path bPath = Path();
    if (!topConn) { bPath.moveTo(rect.left, rect.top); bPath.lineTo(rect.right, rect.top); }
    if (!bottomConn) { bPath.moveTo(rect.left, rect.bottom); bPath.lineTo(rect.right, rect.bottom); }
    if (!leftConn) { bPath.moveTo(rect.left, rect.top); bPath.lineTo(rect.left, rect.bottom); }
    if (!rightConn) { bPath.moveTo(rect.right, rect.top); bPath.lineTo(rect.right, rect.bottom); }
    canvas.drawPath(bPath, borderPaint);
  }

  /// Cubito individual con separación (Renderizado de la pieza activa en el aire mientras cae)
  void _drawIndividualCube({
    required Canvas canvas,
    required double x,
    required double y,
    required double w,
    required double h,
    required TetrominoType type,
  }) {
    const margin = 0.7;
    final rect = Rect.fromLTWH(x + margin, y + margin, w - (margin * 2), h - (margin * 2));
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(2.2));

    final baseColor = tetrominoColors[type] ?? const Color(0xFF00E5FF);
    final HSLColor hsl = HSLColor.fromColor(baseColor);
    final Color topLight = hsl.withLightness((hsl.lightness + 0.22).clamp(0.0, 1.0)).toColor();
    final Color darkShadow = hsl.withLightness((hsl.lightness - 0.26).clamp(0.0, 1.0)).toColor();

    final Paint bevelPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [topLight.withOpacity(0.95), baseColor, darkShadow],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(rect);
    canvas.drawRRect(rrect, bevelPaint);

    const bevelInset = 2.0;
    final innerRect = Rect.fromLTWH(
      rect.left + bevelInset,
      rect.top + bevelInset,
      rect.width - (bevelInset * 2),
      rect.height - (bevelInset * 2),
    );
    final innerRRect = RRect.fromRectAndRadius(innerRect, const Radius.circular(1.2));

    final Paint innerPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [baseColor, hsl.withLightness((hsl.lightness - 0.12).clamp(0.0, 1.0)).toColor()],
      ).createShader(innerRect);
    canvas.drawRRect(innerRRect, innerPaint);

    final borderPaint = Paint()
      ..color = Colors.white.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;
    canvas.drawRRect(rrect, borderPaint);
  }

  /// Ghost Piece holográfico con Neón Glow (Tetris Effect)
  void _drawGhostCell(Canvas canvas, double x, double y, double w, double h, Color color) {
    const margin = 1.0;
    final rect = Rect.fromLTWH(x + margin, y + margin, w - (margin * 2), h - (margin * 2));
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(2.0));

    final fillPaint = Paint()
      ..color = color.withOpacity(0.12)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(rrect, fillPaint);

    final borderPaint = Paint()
      ..color = color.withOpacity(0.65)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawRRect(rrect, borderPaint);

    final centerPaint = Paint()
      ..color = color.withOpacity(0.40)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(rect.center, 1.2, centerPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class TetrominoPreviewPainter extends CustomPainter {
  final TetrominoType? type;

  TetrominoPreviewPainter({this.type});

  @override
  void paint(Canvas canvas, Size size) {
    if (type == null) return;
    final shape = tetrominoShapes[type]![0];
    const cellSize = 6.5;

    final baseColor = tetrominoColors[type] ?? Colors.white;
    final HSLColor hsl = HSLColor.fromColor(baseColor);
    final Color topLight = hsl.withLightness((hsl.lightness + 0.20).clamp(0.0, 1.0)).toColor();
    final Color darkShadow = hsl.withLightness((hsl.lightness - 0.25).clamp(0.0, 1.0)).toColor();

    final offsetX = (size.width - shape[0].length * cellSize) / 2;
    final offsetY = (size.height - shape.length * cellSize) / 2;

    for (int r = 0; r < shape.length; r++) {
      for (int c = 0; c < shape[r].length; c++) {
        if (shape[r][c] != 0) {
          final rect = Rect.fromLTWH(offsetX + c * cellSize, offsetY + r * cellSize, cellSize - 0.8, cellSize - 0.8);
          final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(1.2));

          final Paint bevelPaint = Paint()
            ..shader = LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [topLight, baseColor, darkShadow],
            ).createShader(rect);
          canvas.drawRRect(rrect, bevelPaint);

          final borderPaint = Paint()
            ..color = Colors.white.withOpacity(0.35)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.4;
          canvas.drawRRect(rrect, borderPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
