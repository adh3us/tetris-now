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
import '../services/logros_service.dart';
import '../services/tetris_match_service.dart';
import '../services/tetris_realtime_service.dart';
import '../services/presence_service.dart';
import 'virtual_controller.dart';


int generateDeterministicSeed(String input) {
  int hash = 0x811c9dc5;
  for (final unit in input.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0x7FFFFFFF;
  }
  return hash;
}

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
  final String? torneoPartidaId;
  final String? myInscripcionId;
  final String? opponentInscripcionId;
  final String? opponentName;
  final TetrisRealtimeService? realtimeService;
  final GameMode mode;

  const TetrisGameScreen({
    Key? key,
    this.matchId,
    this.myTeamId,
    this.opponentTeamId,
    this.tournamentId,
    this.torneoPartidaId,
    this.myInscripcionId,
    this.opponentInscripcionId,
    this.opponentName,
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
  int _maxCombo = 0;
  double _comboPulseScale = 1.0;

  String? _resolvedMyTeamId;
  String? _resolvedOpponentTeamId;

  String? get _effectiveMyTeamId => _resolvedMyTeamId ?? widget.myTeamId ?? widget.realtimeService?.myTeamId;
  String? get _effectiveOpponentTeamId => _resolvedOpponentTeamId ?? widget.opponentTeamId ?? widget.realtimeService?.opponentTeamId;

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

  // Feedback Visual: Alerta de Daño en CRT (parpadeo en rojo neón por 0.5s)
  int _crtDamageFlashCount = 0;
  Timer? _crtDamageFlashTimer;
  int _lastMyHp = 100;

  void _triggerDamageCrtFlash() {
    _crtDamageFlashTimer?.cancel();
    _crtDamageFlashCount = 6; // 3 destellos completos (on/off) en ~500ms
    _crtDamageFlashTimer = Timer.periodic(const Duration(milliseconds: 80), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _crtDamageFlashCount--;
        if (_crtDamageFlashCount <= 0) {
          timer.cancel();
        }
      });
    });
  }

  bool get _isCrtDamageFlashing => _crtDamageFlashCount > 0 && (_crtDamageFlashCount % 2 != 0);

  // Feedback Visual: Fogonazo Citrino en PUNTOS y LÍNEAS al limpiar líneas o subir puntaje
  bool _isLineScoreFlashing = false;
  Timer? _lineScoreFlashTimer;
  int _lastScore = 0;
  int _lastLinesCleared = 0;

  void _triggerLineScoreFlash() {
    _lineScoreFlashTimer?.cancel();
    setState(() {
      _isLineScoreFlashing = true;
    });
    _lineScoreFlashTimer = Timer(const Duration(milliseconds: 400), () {
      if (mounted) {
        setState(() {
          _isLineScoreFlashing = false;
        });
      }
    });
  }

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

  bool _isMatchEnded = false;
  String? _opponentDisplayName;
  String? _opponentUserId;
  int _appliedEloDelta = 0;
  bool _isWinnerResult = false;
  List<List<int>> _opponentGrid = [];
  int _opponentStackHeight = 0;
  double _boardSyncCooldown = 0.0;

  Future<void> _fetchOpponentInfo() async {
    if (widget.matchId == null) return;
    try {
      final myId = SupabaseConfig.client.auth.currentUser?.id;

      // 1. Resolver el teamId propio desde match_tetris_players
      if (myId != null) {
        final myRow = await SupabaseConfig.client
            .schema('tetris')
            .from('match_tetris_players')
            .select('team_id')
            .eq('match_id', widget.matchId!)
            .eq('user_id', myId)
            .maybeSingle();
        if (myRow != null && myRow['team_id'] != null) {
          _resolvedMyTeamId = myRow['team_id'] as String?;
        }
      }

      // 2. Resolver info del rival y su team_id
      final rows = await SupabaseConfig.client
          .schema('tetris')
          .from('match_tetris_players')
          .select('user_id, gamer_tag, team_id')
          .eq('match_id', widget.matchId!)
          .neq('user_id', myId ?? '');

      if (rows.isNotEmpty) {
        final tag = rows.first['gamer_tag'] as String?;
        final oppId = rows.first['user_id'] as String?;
        final oppTeam = rows.first['team_id'] as String?;
        if (oppId != null) {
          _opponentUserId = oppId;
        }
        if (oppTeam != null && oppTeam.isNotEmpty) {
          _resolvedOpponentTeamId = oppTeam;
        }

        if (tag != null && tag.isNotEmpty && mounted) {
          setState(() => _opponentDisplayName = tag);
        }
        if (oppId != null) {
          final uRow = await SupabaseConfig.client
              .from('usuarios')
              .select('nombre_display, username')
              .eq('id', oppId)
              .maybeSingle();
          if (uRow != null && mounted) {
            final dName = uRow['nombre_display'] ?? uRow['username'];
            if (dName != null && dName.toString().trim().isNotEmpty) {
              setState(() => _opponentDisplayName = dName.toString().trim());
            }
          }
        }
      }

      // 3. Si aún falta alguno, resolver desde match_tetris (team_1_id / team_2_id)
      if (_resolvedMyTeamId == null || _resolvedOpponentTeamId == null) {
        final mRow = await SupabaseConfig.client
            .schema('tetris')
            .from('match_tetris')
            .select('team_1_id, team_2_id')
            .eq('id', widget.matchId!)
            .maybeSingle();
        if (mRow != null) {
          final t1 = mRow['team_1_id'] as String?;
          final t2 = mRow['team_2_id'] as String?;
          if (_resolvedMyTeamId != null) {
            _resolvedOpponentTeamId ??= (_resolvedMyTeamId == t1 ? t2 : t1);
          } else if (_resolvedOpponentTeamId != null) {
            _resolvedMyTeamId ??= (_resolvedOpponentTeamId == t1 ? t2 : t1);
          } else {
            _resolvedMyTeamId = t1;
            _resolvedOpponentTeamId = t2;
          }
        }
      }
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    PresenceService.instance.statusesNotifier.addListener(_onPresenceChanged);
    _opponentDisplayName = widget.opponentName;
    if (widget.matchId != null) {
      _fetchOpponentInfo();
    }
    _loadHiScore();
    _loadSavedArena();

    // Bloqueo estricto en modo vertical para eliminar franjas de desborde
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);

    final matchSeed = widget.matchId != null && widget.matchId!.trim().isNotEmpty
        ? generateDeterministicSeed(widget.matchId!.trim())
        : null;

    _engine = TetrisEngine(
      cols: widget.mode == GameMode.coop2v2Wide ? 20 : 10,
      rows: 20,
      mode: widget.mode,
      randomSeed: matchSeed,
    );
    _lastMyHp = _engine.currentHp;
    _lastScore = _engine.score;
    _lastLinesCleared = _engine.linesCleared;
    _audioService.playMusic(TetrisAudioService.bgmBattle);

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
      if (_engine.combo > _maxCombo) {
        _maxCombo = _engine.combo;
      }
      if (_engine.maxCombo > _maxCombo) {
        _maxCombo = _engine.maxCombo;
      }
      if (_comboPulseScale > 1.0) {
        _comboPulseScale = max(1.0, _comboPulseScale - dt * 2.5);
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

      if (_isMatchEnded) return;

      // Sincronización periódica del minimapa del rival (3 veces por segundo)
      _boardSyncCooldown -= dt;
      if (_boardSyncCooldown <= 0.0) {
        _boardSyncCooldown = 0.35;
        if (widget.realtimeService != null && (widget.mode == GameMode.duel1v1 || widget.mode == GameMode.tournament)) {
          widget.realtimeService!.sendBoardSync(
            _engine.getCompactVisibleMatrix(),
            _engine.getStackHeight(),
            _engine.currentHp,
          );
        }
      }

      final res = _engine.update(dt);
      if (res != null) {
        _processAttackResult(res);
      }
      _checkAndUpdateHiScore();

      // Detección de daño recibido para parpadeo rojo neón en pantalla CRT
      if (_engine.currentHp < _lastMyHp) {
        _triggerDamageCrtFlash();
      }
      _lastMyHp = _engine.currentHp;

      // Detección de aumento drástico de puntaje o líneas limpiadas para fogonazo citrino
      if (_engine.score > _lastScore + 40 || _engine.linesCleared > _lastLinesCleared) {
        _triggerLineScoreFlash();
      }
      _lastScore = _engine.score;
      _lastLinesCleared = _engine.linesCleared;

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
        if (!mounted || _isMatchEnded) return;
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

      // Recepción de ataques especiales (4 barras)
      widget.realtimeService!.onSpecialAttack = (tier, duration) {
        if (!mounted || _isMatchEnded) return;
        setState(() {
          if (_engine.isShieldActive) {
            _combatLog = '⚡ ¡ESCUDO ACTIVO! Ataque especial bloqueado.';
            _triggerImpactBanner('¡ESCUDO BLOQUEÓ!', sub: 'ATAQUE ESPECIAL NEUTRALIZADO', color: const Color(0xFF00D26A));
            _audioService.play(TetrisSfx.shieldActivate);
            return;
          }

          if (tier == 1) {
            _engine.invertedRotationTimer = duration.toDouble();
            _audioService.play(TetrisSfx.damageReceived);
            _triggerScreenShake(intensity: 5.5, duration: 0.22);
            _triggerImpactBanner('⚠️ ¡GIRO INVERTIDO!', sub: 'Controles invertidos (${duration}s)', color: const Color(0xFFFB923C));
            _combatLog = '⚠️ ¡Rival activó Giro Invertido (${duration}s)!';
          } else if (tier == 2) {
            _engine.invisibleFlickerTimer = duration.toDouble();
            _audioService.play(TetrisSfx.damageReceived);
            _triggerScreenShake(intensity: 5.5, duration: 0.22);
            _triggerImpactBanner('👻 ¡FICHAS INVISIBLES!', sub: 'Piezas titilando (${duration}s)', color: const Color(0xFFC084FC));
            _combatLog = '👻 ¡Rival volvió tus fichas invisibles (${duration}s)!';
          } else if (tier == 3) {
            _engine.speedMultiplierTimer = duration.toDouble();
            _audioService.play(TetrisSfx.damageReceived);
            _triggerScreenShake(intensity: 7.0, duration: 0.25);
            _triggerImpactBanner('⚡ ¡VELOCIDAD x4!', sub: 'Caída acelerada (${duration}s)', color: const Color(0xFF38BDF8));
            _combatLog = '⚡ ¡Rival aceleró tu caída a x4 (${duration}s)!';
          } else if (tier == 4) {
            _engine.receiveStarShower(4);
            _audioService.play(TetrisSfx.damageReceived);
            _triggerScreenShake(intensity: 9.0, duration: 0.35);
            _triggerImpactBanner('⭐ ¡LLUVIA DE ESTRELLAS! ⭐', sub: '4 estrellas fijas en tu pantalla', color: const Color(0xFFFBBF24));
            _combatLog = '⭐ ¡Lluvia de estrellas del rival! Elimínalas con líneas.';
          }
        });
      };

      // Recepción en vivo del minimapa del rival
      widget.realtimeService!.onOpponentBoardSync = (matrix, stackHeight, hp) {
        if (!mounted || _isMatchEnded) return;
        setState(() {
          _opponentGrid = matrix;
          _opponentStackHeight = stackHeight;
          _opponentHp = hp;
        });
      };

      widget.realtimeService!.onPlayerKnockout = (userId, teamId) {
        if (!mounted || _isMatchEnded) return;

        // Congelar de inmediato el ticker y el motor gráfico para corte simultáneo
        _ticker.stop();
        _engine.isGameOver = true;
        _engine.isPaused = true;

        final myTeam = _effectiveMyTeamId;
        final isVictory = (userId.isNotEmpty && userId != widget.realtimeService?.currentUserId) ||
                          (teamId.isNotEmpty && teamId != myTeam) ||
                          (userId.isEmpty && teamId.isEmpty);

        if (isVictory && widget.matchId != null) {
          final cruceId = widget.torneoPartidaId ?? widget.tournamentId;
          if (cruceId != null && cruceId.isNotEmpty) {
            _matchService.reportarResultadoCruceTorneo(
              partidaId: cruceId,
              ganadorInscripcionId: widget.myInscripcionId,
              matchId: widget.matchId!,
            );
          } else if (myTeam != null && myTeam.isNotEmpty) {
            _matchService.reportMatchResult(
              matchId: widget.matchId!,
              winnerTeamId: myTeam,
            );
          }
        }
        _terminateMatch(isWinner: isVictory);
      };

      widget.realtimeService!.onOpponentConnectionChanged = (isConnected) {
        if (!mounted) return;
        setState(() {
          _isOpponentReconnecting = !isConnected;
        });
      };

      widget.realtimeService!.onMatchEnd = (winnerTeamId) {
        if (!mounted || _isMatchEnded) return;

        // Congelar de inmediato el ticker y el motor gráfico para corte simultáneo
        _ticker.stop();
        _engine.isGameOver = true;
        _engine.isPaused = true;

        final myTeam = _effectiveMyTeamId;
        final isVictory = winnerTeamId.isNotEmpty && (winnerTeamId == myTeam);
        if (isVictory && widget.matchId != null) {
          final cruceId = widget.torneoPartidaId ?? widget.tournamentId;
          if (cruceId != null && cruceId.isNotEmpty) {
            _matchService.reportarResultadoCruceTorneo(
              partidaId: cruceId,
              ganadorInscripcionId: widget.myInscripcionId,
              matchId: widget.matchId!,
            );
          } else if (myTeam != null && myTeam.isNotEmpty) {
            _matchService.reportMatchResult(
              matchId: widget.matchId!,
              winnerTeamId: myTeam,
            );
          }
        }
        _terminateMatch(isWinner: isVictory);
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
    // Bloqueo total de controles y audio si la partida terminó o el motor está en game over
    if (_isMatchEnded || _engine.isGameOver) return;
    if (_engine.isPaused && action != GameAction.pause) return;

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
          final bool isVs = widget.matchId != null || widget.mode == GameMode.duel1v1 || widget.mode == GameMode.tournament;
          if (isVs) {
            _triggerImpactBanner('DUELO ONLINE EN VIVO', sub: 'NO SE PERMITE PAUSAR EN PARTIDAS VS', color: const Color(0xFFFF1744));
            return;
          }
          _engine.isPaused = !_engine.isPaused;
          _showPauseDialog();
          break;
        case GameAction.reset:
          final bool isVs = widget.matchId != null || widget.mode == GameMode.duel1v1 || widget.mode == GameMode.tournament;
          if (isVs) return; // No reiniciar en partidas online
          _maxCombo = 0;
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

    if (widget.realtimeService != null && (widget.mode == GameMode.duel1v1 || widget.mode == GameMode.tournament)) {
      widget.realtimeService!.sendBoardSync(
        _engine.getCompactVisibleMatrix(),
        _engine.getStackHeight(),
        _engine.currentHp,
      );
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

  /// Ejecuta el ataque especial correspondiente al nivel cargado (1 a 4 barras)
  void _handleSpecialAttack() {
    final bars = _engine.specialChargeBars;
    if (bars <= 0) {
      _triggerImpactBanner('SIN CARGA', sub: 'HAZ UN TETRIS (4 LÍNEAS) PARA CARGAR', color: const Color(0xFF8B949E));
      return;
    }

    _audioService.play(TetrisSfx.tetris);
    _triggerScreenShake(intensity: 6.0, duration: 0.20);
    _engine.specialChargeBars = 0; // Consume las barras acumuladas

    String attackName = '';
    Color attackColor = const Color(0xFF00E5FF);
    switch (bars) {
      case 1:
        attackName = 'GIRO INVERTIDO (20s)';
        attackColor = const Color(0xFFFB923C);
        _combatLog = '⚡ ¡ATAQUE NIVEL 1! Giro invertido al rival por 20s.';
        break;
      case 2:
        attackName = 'FICHAS INVISIBLES (20s)';
        attackColor = const Color(0xFFC084FC);
        _combatLog = '👻 ¡ATAQUE NIVEL 2! Fichas invisibles al rival por 20s.';
        break;
      case 3:
        attackName = 'VELOCIDAD x4 (20s)';
        attackColor = const Color(0xFF38BDF8);
        _combatLog = '⚡ ¡ATAQUE NIVEL 3! Caída acelerada x4 al rival por 20s.';
        break;
      case 4:
      default:
        attackName = 'LLUVIA DE ESTRELLAS ⭐';
        attackColor = const Color(0xFFFBBF24);
        _combatLog = '⭐ ¡ATAQUE NIVEL 4! Lluvia de estrellas fijas al rival.';
        break;
    }

    if (widget.realtimeService != null && (widget.mode == GameMode.duel1v1 || widget.mode == GameMode.tournament)) {
      widget.realtimeService!.sendSpecialAttack(bars, duration: 20);
    } else {
      // Modo Solitario / Pruebas locales: Los ataques son siempre para el rival, nunca sobre uno mismo
      _engine.score += bars * 1500;
      _checkAndUpdateHiScore();
    }

    _triggerImpactBanner('¡ATAQUE LANZADO!', sub: attackName, color: attackColor);
    if (mounted) setState(() {});
  }

  /// Finaliza la partida de manera instantánea y simultánea para ambos jugadores
  void _terminateMatch({required bool isWinner, bool isSurrender = false}) {
    if (_isMatchEnded) return;
    _isMatchEnded = true;
    _isWinnerResult = isWinner;
    _ticker.stop();
    _engine.isGameOver = true;
    _engine.isPaused = true;

    final matchSecs = _ambientTime > 0 ? _ambientTime : 60.0;
    final winnerDelta = TetrisMatchService.calcularEloDeltaGanador(
      durationSeconds: matchSecs,
      linesSent: _engine.linesSent,
      maxCombo: max(_engine.maxCombo, _maxCombo),
      linesCleared: _engine.linesCleared,
    );
    final loserDelta = TetrisMatchService.calcularEloDeltaPerdedor(
      durationSeconds: matchSecs,
      linesSent: _engine.linesSent,
      maxCombo: max(_engine.maxCombo, _maxCombo),
      linesCleared: _engine.linesCleared,
      isSurrender: isSurrender,
    );

    _appliedEloDelta = isWinner ? winnerDelta : loserDelta;

    if (widget.matchId != null) {
      final myTeam = _effectiveMyTeamId;
      final oppTeam = _effectiveOpponentTeamId;
      final winnerTeam = isWinner ? myTeam : oppTeam;
      if (winnerTeam != null && winnerTeam.isNotEmpty) {
        _matchService.reportMatchResult(
          matchId: widget.matchId!,
          winnerTeamId: winnerTeam,
          payload: {
            'duration_seconds': matchSecs,
            'lines_sent': _engine.linesSent,
            'max_combo': max(_engine.maxCombo, _maxCombo),
            'lines_cleared': _engine.linesCleared,
            'is_surrender': isSurrender,
            'elo_delta_winner': winnerDelta,
            'elo_delta_loser': loserDelta,
          },
        ).catchError((_) => <String, dynamic>{});
      }
    }

    _audioService.stopMusic();
    if (isWinner) {
      _audioService.play(TetrisSfx.tetris);
      _triggerImpactBanner('¡GANADOR!', sub: '¡HAS GANADO LA PARTIDA! +$_appliedEloDelta PTS ELO', color: const Color(0xFF00D26A));
    } else {
      _audioService.play(TetrisSfx.gameOver);
      _triggerImpactBanner('PERDEDOR', sub: 'PARTIDA FINALIZADA • $_appliedEloDelta PTS ELO', color: const Color(0xFFFF1744));
    }

    if (mounted) {
      setState(() {});
      _showResultDialog(isWinner: isWinner, eloDelta: _appliedEloDelta);
    }

    // Evaluación asíncrona de logros desbloqueados en la partida
    try {
      final hasGold = _engine.grid.any((row) => row.any((cell) => cell?.cubeType == CubeType.gold));
      final hasSilver = _engine.grid.any((row) => row.any((cell) => cell?.cubeType == CubeType.silver));
      final isDuel = widget.mode == GameMode.duel1v1 || widget.mode == GameMode.tournament;
      LogrosService().evaluarLogrosDePartida(
        linesCleared: _engine.linesCleared,
        maxCombo: max(_engine.maxCombo, _maxCombo),
        currentHp: _engine.currentHp,
        isWinner: isWinner,
        hasGoldCube: hasGold,
        hasSilverCube: hasSilver,
        isDuel: isDuel,
      );
    } catch (_) {}
  }

  void _handleGameOver({bool surrender = false}) {
    if (_isMatchEnded) return;
    _ticker.stop();
    _engine.isGameOver = true;
    _engine.isPaused = true;
    _audioService.play(TetrisSfx.gameOver);

    final oppTeam = _effectiveOpponentTeamId;

    if (widget.matchId != null && widget.realtimeService != null) {
      widget.realtimeService?.sendKnockout();
      if (oppTeam != null && oppTeam.isNotEmpty) {
        widget.realtimeService?.sendMatchEnd(oppTeam);
      }

      if (surrender) {
        final myUserId = SupabaseConfig.client.auth.currentUser?.id;
        if (myUserId != null) {
          _matchService.penalizarAbandono(matchId: widget.matchId!, userId: myUserId).catchError((_) {});
        }
      }

      final cruceId = widget.torneoPartidaId ?? widget.tournamentId;
      if (cruceId != null && cruceId.isNotEmpty) {
        _matchService.reportarResultadoCruceTorneo(
          partidaId: cruceId,
          ganadorInscripcionId: widget.opponentInscripcionId,
          matchId: widget.matchId!,
        );
      } else if (oppTeam != null && oppTeam.isNotEmpty) {
        final matchSecs = _ambientTime > 0 ? _ambientTime : 60.0;
        final winnerDelta = TetrisMatchService.calcularEloDeltaGanador(
          durationSeconds: matchSecs,
          linesSent: _engine.linesSent,
          maxCombo: max(_engine.maxCombo, _maxCombo),
          linesCleared: _engine.linesCleared,
        );
        final loserDelta = TetrisMatchService.calcularEloDeltaPerdedor(
          durationSeconds: matchSecs,
          linesSent: _engine.linesSent,
          maxCombo: max(_engine.maxCombo, _maxCombo),
          linesCleared: _engine.linesCleared,
          isSurrender: surrender,
        );

        _matchService.reportMatchResult(
          matchId: widget.matchId!,
          winnerTeamId: oppTeam,
          payload: {
            'duration_seconds': matchSecs,
            'lines_sent': _engine.linesSent,
            'max_combo': max(_engine.maxCombo, _maxCombo),
            'lines_cleared': _engine.linesCleared,
            'is_surrender': surrender,
            'elo_delta_winner': winnerDelta,
            'elo_delta_loser': loserDelta,
          },
        );
      }
    }
    _terminateMatch(isWinner: false, isSurrender: surrender);
  }

  /// Cartel prominente de GANADOR o PERDEDOR según el resultado
  void _showResultDialog({required bool isWinner, int eloDelta = 0}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0B1024),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: isWinner ? const Color(0xFF00E5FF) : const Color(0xFFFF1744),
            width: 2.0,
          ),
        ),
        title: Column(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: const Color(0xFF101735),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: (isWinner ? const Color(0xFFFACC15) : const Color(0xFFFF1744)).withOpacity(0.7),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: (isWinner ? const Color(0xFFFACC15) : const Color(0xFFFF1744)).withOpacity(0.3),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: Icon(
                isWinner ? Icons.emoji_events_rounded : Icons.sentiment_very_dissatisfied_rounded,
                color: isWinner ? const Color(0xFFFACC15) : const Color(0xFFFF1744),
                size: 34,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              isWinner ? '¡GANADOR!' : 'PERDEDOR',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isWinner ? const Color(0xFF00E5FF) : const Color(0xFFFF1744),
                fontWeight: FontWeight.w900,
                fontSize: 26,
                letterSpacing: 3.5,
                shadows: [
                  Shadow(
                    color: (isWinner ? const Color(0xFF00E5FF) : const Color(0xFFFF1744)).withOpacity(0.8),
                    blurRadius: 16,
                  ),
                  Shadow(
                    color: (isWinner ? const Color(0xFF00E5FF) : const Color(0xFFFF1744)).withOpacity(0.5),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: (isWinner ? const Color(0xFF00E5FF) : const Color(0xFFFF1744)).withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isWinner ? const Color(0xFF00E5FF) : const Color(0xFFFF1744),
                  width: 1.2,
                ),
              ),
              child: Text(
                isWinner ? '+$eloDelta PTS ELO' : '$eloDelta PTS ELO',
                style: TextStyle(
                  color: isWinner ? const Color(0xFF00E5FF) : const Color(0xFFFF1744),
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  letterSpacing: 1.0,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              isWinner
                  ? '¡Victoria indiscutida! Has superado al rival.'
                  : 'Partida finalizada. ¡Sigue entrenando!',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF070B19),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.25), width: 1.0),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00E5FF).withOpacity(0.06),
                blurRadius: 8,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildResultStatRow('Rating ELO:', isWinner ? '+$eloDelta pts' : '$eloDelta pts'),
              const SizedBox(height: 6),
              _buildResultStatRow('Puntuación:', '${_engine.score} pts'),
              const SizedBox(height: 6),
              _buildResultStatRow('Líneas limpiadas:', '${_engine.linesCleared}'),
              const SizedBox(height: 6),
              _buildResultStatRow('Ataques enviados:', '${_engine.linesSent}'),
              const SizedBox(height: 6),
              _buildResultStatRow('Combo máximo:', 'x${max(_engine.maxCombo, _maxCombo)}'),
            ],
          ),
        ),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 6.0),
              child: GestureDetector(
                onTap: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).pop();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isWinner
                          ? const [Color(0xFF00E5FF), Color(0xFF00B4D8)]
                          : const [Color(0xFFFF2A85), Color(0xFFD80064)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isWinner ? const Color(0xFF38BDF8) : const Color(0xFFFF6EB4),
                      width: 1.2,
                    ),
                    boxShadow: [
                      // Sombra inferior biselada para relieve 3D arcade
                      BoxShadow(
                        color: isWinner ? const Color(0xFF007799) : const Color(0xFF88003E),
                        offset: const Offset(0, 4),
                        blurRadius: 0,
                      ),
                      // Resplandor neón
                      BoxShadow(
                        color: (isWinner ? const Color(0xFF00E5FF) : const Color(0xFFFF2A85)).withOpacity(0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.home_rounded,
                        size: 16,
                        color: isWinner ? const Color(0xFF070B19) : Colors.white,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'VOLVER AL LOBBY',
                        style: TextStyle(
                          color: isWinner ? const Color(0xFF070B19) : Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultStatRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF94A3B8),
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Color(0xFFFACC15),
            fontWeight: FontWeight.w900,
            fontSize: 12.5,
            letterSpacing: 0.8,
          ),
        ),
      ],
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

  void _onPresenceChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _audioService.stopMusic();
    PresenceService.instance.statusesNotifier.removeListener(_onPresenceChanged);
    _ticker.dispose();
    _shieldTimer?.cancel();
    _crtDamageFlashTimer?.cancel();
    _lineScoreFlashTimer?.cancel();
    _focusNode.dispose();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    super.dispose();
  }

  Future<void> _confirmExitMatch() async {
    if (_isMatchEnded) {
      Navigator.of(context).pop();
      return;
    }

    final bool isMultiplayer = widget.matchId != null || widget.mode == GameMode.duel1v1 || widget.mode == GameMode.tournament;
    final wasPaused = _engine.isPaused;
    if (!isMultiplayer) {
      setState(() => _engine.isPaused = true);
    }

    final shouldExit = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F141C),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFFF1744), width: 1.8),
        ),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFFF1744), size: 26),
            SizedBox(width: 8),
            Text(
              '¿ABANDONAR PARTIDA?',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 15,
                letterSpacing: 1.0,
              ),
            ),
          ],
        ),
        content: Text(
          isMultiplayer
              ? 'Si abandonas ahora, la partida terminará de inmediato para ambos jugadores, tu rival obtendrá la victoria y se te descontarán -90 PTS de ELO por abandono.'
              : '¿Deseas salir al menú principal? Se perderá el progreso de tu partida actual.',
          style: const TextStyle(
            color: Color(0xFF94A3B8),
            fontSize: 12.5,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              'CONTINUAR JUGANDO',
              style: TextStyle(
                color: Color(0xFF00E5FF),
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF1744),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: const Text(
              'ABANDONAR',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
            ),
          ),
        ],
      ),
    );

    if (shouldExit == true) {
      if (isMultiplayer) {
        _handleGameOver(surrender: true);
      } else {
        _ticker.stop();
        _engine.isGameOver = true;
      }
      if (mounted) {
        Navigator.of(context).pop();
      }
    } else {
      if (mounted && !isMultiplayer && !wasPaused) {
        setState(() => _engine.isPaused = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _isMatchEnded,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _confirmExitMatch();
      },
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _handleKeyEvent,
        child: Scaffold(
          backgroundColor: const Color(0xFF151820), // Carcasa gris oscuro texturizado mate de arcade
          body: SafeArea(
            child: _buildPortraitLayout(),
          ),
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
        _buildSpecialAttackGauge(),

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
                                  _buildCard(
                                    title: 'PUNTOS',
                                    value: '${_engine.score}',
                                    isHighlighting: true,
                                  ),
                                  const SizedBox(height: 3),
                                  _buildCard(title: 'HI-SCORE', value: '$_hiScore'),
                                  const SizedBox(height: 3),
                                  _buildCard(
                                    title: 'LÍNEAS',
                                    value: '${_engine.linesCleared}',
                                    isHighlighting: true,
                                  ),
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
                                  if (widget.mode == GameMode.duel1v1 || widget.mode == GameMode.tournament) ...[
                                    const SizedBox(height: 3),
                                    _buildOpponentMinimapCard(),
                                  ],
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
          isShieldActive: _engine.isShieldActive,
          enabled: !_isMatchEnded && !_engine.isGameOver,
          isVsMode: widget.matchId != null || widget.mode == GameMode.duel1v1 || widget.mode == GameMode.tournament,
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
    final bool isLowHp = myHp <= 20 && myHp > 0;
    final myHpRatio = (myHp / 100.0).clamp(0.0, 1.0);
    // HP propio en Amarillo Citrino brillante o Rojo Neón si está en estado crítico (<=20 HP)
    final myHpColor = isLowHp ? const Color(0xFFFF1744) : const Color(0xFFFACC15);

    final oppHpRatio = (_opponentHp / 100.0).clamp(0.0, 1.0);
    // HP del rival en Rojo Neón intenso
    const oppHpColor = Color(0xFFFF1744);
    final oppLabel = (_opponentDisplayName != null && _opponentDisplayName!.trim().isNotEmpty)
        ? _opponentDisplayName!.trim().toUpperCase()
        : 'RIVAL';

    return Container(
      height: 24,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1118),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isLowHp ? const Color(0xFFFF1744) : const Color(0xFF2B3144),
          width: isLowHp ? 1.5 : 1.2,
        ),
        boxShadow: [
          if (isLowHp)
            BoxShadow(
              color: const Color(0xFFFF1744).withOpacity(0.4),
              blurRadius: 8,
              spreadRadius: 1,
            ),
          const BoxShadow(
            color: Colors.black54,
            offset: Offset(0, 2),
            blurRadius: 4,
          ),
        ],
      ),
      child: Row(
        children: [
          // Tu Barra de Vida (HP)
          Expanded(
            child: Row(
              children: [
                Icon(
                  isLowHp ? Icons.warning_amber_rounded : Icons.favorite,
                  size: 11,
                  color: myHpColor,
                ),
                const SizedBox(width: 3),
                Text(
                  'HP: $myHp',
                  style: TextStyle(
                    color: myHpColor,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: myHpRatio,
                      backgroundColor: isLowHp ? const Color(0xFF330B10) : const Color(0xFF262010),
                      valueColor: AlwaysStoppedAnimation<Color>(myHpColor),
                      minHeight: 4.5,
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (widget.matchId != null) ...[
            const SizedBox(width: 10),
            // Barra de Vida del Rival (1v1) con Nombre real del adversario
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: oppHpRatio,
                        backgroundColor: const Color(0xFF261014),
                        valueColor: const AlwaysStoppedAnimation<Color>(oppHpColor),
                        minHeight: 4.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                  UserStatusDot(
                    status: _isOpponentReconnecting
                        ? UserPresenceStatus.away
                        : (_opponentUserId != null
                            ? PresenceService.instance.getStatusForUser(_opponentUserId!)
                            : UserPresenceStatus.online),
                    size: 6.5,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      '$oppLabel: $_opponentHp',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: oppHpColor,
                        fontSize: 8.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 3),
                  const Icon(Icons.flash_on_rounded, size: 11, color: Color(0xFFFF1744)),
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

  /// Barra visual de 4 segmentos de Ataque Especial (cargada con TETRIS)
  Widget _buildSpecialAttackGauge() {
    final bars = _engine.specialChargeBars;

    Color activeColor;
    String attackTitle;
    switch (bars) {
      case 1:
        activeColor = const Color(0xFFFB923C);
        attackTitle = 'GIRO ⟲ (20s)';
        break;
      case 2:
        activeColor = const Color(0xFFC084FC);
        attackTitle = 'INVISIBLE 👻 (20s)';
        break;
      case 3:
        activeColor = const Color(0xFF38BDF8);
        attackTitle = 'VELOCIDAD x4 ⚡';
        break;
      case 4:
        activeColor = const Color(0xFFFBBF24);
        attackTitle = 'ESTRELLAS ⭐';
        break;
      default:
        activeColor = const Color(0xFF64748B);
        attackTitle = 'HAZ TETRIS (4L)';
        break;
    }

    return GestureDetector(
      onTap: _handleSpecialAttack,
      child: Container(
        height: 22,
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFF0F1118),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: bars > 0 ? activeColor.withOpacity(0.9) : const Color(0xFF2B3144),
            width: bars > 0 ? 1.2 : 1.0,
          ),
          boxShadow: [
            const BoxShadow(color: Colors.black54, offset: Offset(0, 1), blurRadius: 3),
            if (bars > 0)
              BoxShadow(color: activeColor.withOpacity(0.35), blurRadius: 6),
          ],
        ),
        child: Row(
          children: [
            Icon(Icons.bolt, size: 12, color: activeColor),
            const SizedBox(width: 3),
            Text(
              bars > 0 ? 'ATAQUE ($bars/4):' : 'ATAQUE:',
              style: TextStyle(
                color: bars > 0 ? activeColor : const Color(0xFF8B949E),
                fontSize: 8.0,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              attackTitle,
              style: TextStyle(
                color: bars > 0 ? Colors.white : const Color(0xFF64748B),
                fontSize: 8.0,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            // 4 BARRAS DE CARGA
            Row(
              children: List.generate(4, (i) {
                final isFilled = i < bars;
                final Color barColor = [
                  const Color(0xFFFB923C), // Barra 1: Giro
                  const Color(0xFFC084FC), // Barra 2: Invisible
                  const Color(0xFF38BDF8), // Barra 3: Caída x4
                  const Color(0xFFFBBF24), // Barra 4: Estrellas
                ][i];

                return Container(
                  width: 14,
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 1.2),
                  decoration: BoxDecoration(
                    color: isFilled ? barColor : const Color(0xFF21262D),
                    borderRadius: BorderRadius.circular(2),
                    border: Border.all(
                      color: isFilled ? Colors.white.withOpacity(0.6) : const Color(0xFF30363D),
                      width: 0.5,
                    ),
                    boxShadow: isFilled
                        ? [BoxShadow(color: barColor.withOpacity(0.6), blurRadius: 4)]
                        : null,
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  /// Minimapa de la pantalla del rival en vivo con LED indicador de estado
  Widget _buildOpponentMinimapCard() {
    final stackHeight = _opponentStackHeight;
    Color ledColor;
    String statusDesc;
    if (stackHeight >= 15) {
      ledColor = const Color(0xFFFF1744); // Rojo: al límite de perder
      statusDesc = 'PELIGRO';
    } else if (stackHeight >= 8) {
      ledColor = const Color(0xFFFFD700); // Amarillo: advertencia
      statusDesc = 'ALERTA';
    } else {
      ledColor = const Color(0xFF00D26A); // Verde: normal
      statusDesc = 'SEGURO';
    }

    final double pulse = (sin(_ambientTime * 7.0) * 0.35 + 0.65);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 2.5, horizontal: 2.0),
      decoration: BoxDecoration(
        color: const Color(0xFF0F141C),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: ledColor.withOpacity(0.7), width: 1.0),
        boxShadow: [
          BoxShadow(
            color: ledColor.withOpacity(0.35 * pulse),
            blurRadius: 5,
            spreadRadius: 0.5,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ledColor.withOpacity(pulse),
                  boxShadow: [
                    BoxShadow(
                      color: ledColor.withOpacity(pulse),
                      blurRadius: 4,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 3),
              const Text(
                'RIVAL',
                style: TextStyle(
                  color: Color(0xFF8B949E),
                  fontSize: 7.0,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0A0D12),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: const Color(0xFF21262D), width: 0.8),
            ),
            child: CustomPaint(
              size: const Size(34, 68),
              painter: OpponentBoardMinimapPainter(matrix: _opponentGrid),
            ),
          ),
          const SizedBox(height: 1.5),
          Text(
            '$stackHeight/20 ($statusDesc)',
            style: TextStyle(
              color: ledColor,
              fontSize: 6.0,
              fontWeight: FontWeight.bold,
            ),
          ),
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
      child: Builder(
        builder: (context) {
          final bool isLowHp = _engine.currentHp <= 20 && _engine.currentHp > 0;
          final double pulse = sin(_ambientTime * 8).abs();

          return Container(
            decoration: BoxDecoration(
              color: const Color(0xFF070B19), // Pantalla Central (CRT): Azul noche
              borderRadius: BorderRadius.circular(8),
              // Borde de neón: rojo pulsante si HP <= 20, destello si recibe daño o violeta en reposo
              border: Border.all(
                color: isLowHp
                    ? const Color(0xFFFF1744)
                    : (_isCrtDamageFlashing
                        ? const Color(0xFFFF1744) // Rojo Neón de daño
                        : const Color(0xFFA855F7).withOpacity(0.85)),
                width: isLowHp ? 3.0 : (_isCrtDamageFlashing ? 2.5 : 2.0),
              ),
              boxShadow: [
                // Resplandor neón: rojo neón pulsante en vida crítica
                BoxShadow(
                  color: isLowHp
                      ? const Color(0xFFFF1744).withOpacity(0.65 + 0.35 * pulse)
                      : (_isCrtDamageFlashing
                          ? const Color(0xFFFF1744).withOpacity(0.95) // Resplandor rojo neón de impacto
                          : const Color(0xFFA855F7).withOpacity(0.35)),
                  blurRadius: isLowHp ? (18.0 + 8.0 * pulse) : (_isCrtDamageFlashing ? 22 : 12),
                  spreadRadius: isLowHp ? (2.5 + 2.0 * pulse) : (_isCrtDamageFlashing ? 3.5 : 1),
                ),
                // Marco exterior hundido en la carcasa
                const BoxShadow(
                  color: Colors.black87,
                  offset: Offset(0, 4),
                  blurRadius: 10,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
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
                  // Overlay sutil de scanlines y curvatura simulando monitor CRT viejo
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        size: Size(width, height),
                        painter: const CrtScanlinesOverlayPainter(),
                      ),
                    ),
                  ),
                  // Indicador perimetral interno en rojo para alerta de vida crítica (<= 20 HP)
                  if (isLowHp)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: const Color(0xFFFF1744).withOpacity(0.40 + 0.40 * pulse),
                              width: 2.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (_impactBannerText != null)
                    _buildCenterImpactBanner(),
                  // Cartel prominente de fin de partida (PERDEDOR / ¡GANADOR!) sobre el mapa freezado
                  if (_isMatchEnded || _engine.isGameOver)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black.withOpacity(0.60),
                        alignment: Alignment.center,
                        child: _buildMatchEndOverlayBanner(),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Banner de overlay arcade centrado sobre el tablero CRT congelado
  Widget _buildMatchEndOverlayBanner() {
    final bool isWinner = _isWinnerResult;
    final Color mainColor = isWinner ? const Color(0xFF00E5FF) : const Color(0xFFFF1744);
    final String title = isWinner ? '¡GANADOR!' : 'PERDEDOR';
    final String subtitle = isWinner ? '¡VICTORIA TOTAL!' : 'HP AGOTADO • FIN DE PARTIDA';
    final String eloText = isWinner ? '+$_appliedEloDelta PTS ELO' : '$_appliedEloDelta PTS ELO';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF070B19).withOpacity(0.95),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: mainColor, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: mainColor.withOpacity(0.55),
            blurRadius: 18,
            spreadRadius: 2.5,
          ),
          const BoxShadow(
            color: Colors.black87,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isWinner ? Icons.emoji_events_rounded : Icons.sentiment_very_dissatisfied_rounded,
            color: isWinner ? const Color(0xFFFACC15) : const Color(0xFFFF1744),
            size: 38,
          ),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: mainColor,
              fontWeight: FontWeight.w900,
              fontSize: 26,
              letterSpacing: 3.5,
              shadows: [
                Shadow(
                  color: mainColor.withOpacity(0.85),
                  blurRadius: 16,
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: mainColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: mainColor.withOpacity(0.5), width: 1.0),
            ),
            child: Text(
              eloText,
              style: TextStyle(
                color: mainColor,
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.0,
              ),
            ),
          ),
        ],
      ),
    );
  }

    /// Tarjeta de Escudo compacta para la columna izquierda (debajo de LÍNEAS) - Hueco hundido
  Widget _buildShieldCard() {
    final bool isActive = _engine.isShieldActive;
    final int energy = _engine.defenseEnergy;
    final bool isReady = energy >= 5;

    final Color glowColor = isActive
        ? const Color(0xFFFACC15)
        : isReady
            ? const Color(0xFF00E5FF)
            : const Color(0xFF38BDF8);

    return GestureDetector(
      onTap: () => _handleAction(GameAction.activateShield),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 3.0, horizontal: 2.0),
        decoration: BoxDecoration(
          color: const Color(0xFF0A0D16), // Hueco hundido en la carcasa
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: glowColor.withOpacity(isActive || isReady ? 0.9 : 0.45),
            width: isActive ? 1.5 : 1.0,
          ),
          boxShadow: [
            const BoxShadow(
              color: Color(0xCC000000),
              offset: Offset(1.5, 2.0),
              blurRadius: 3.0,
            ),
            if (isActive || isReady)
              BoxShadow(
                color: glowColor.withOpacity(0.35),
                blurRadius: 6,
                spreadRadius: 1,
              ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'ESCUDO',
                style: TextStyle(color: Color(0xFF38BDF8), fontSize: 7.0, fontWeight: FontWeight.w900, letterSpacing: 0.5),
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
                  color: isActive ? const Color(0xFFFACC15) : (isReady ? const Color(0xFF00E5FF) : const Color(0xFFFACC15)),
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
                    color: filled ? (isActive ? const Color(0xFFFACC15) : const Color(0xFF00E5FF)) : const Color(0xFF1E2333),
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

  /// Tarjeta de Panel Lateral (Hold, Next, Score, Hi-Score, Líneas) simulando un hueco hundido en el plástico
  Widget _buildCard({
    required String title,
    String? value,
    Widget? child,
    bool isHighlighting = false,
  }) {
    final bool flashActive = isHighlighting && _isLineScoreFlashing;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 2.5, vertical: 3.0),
      decoration: BoxDecoration(
        color: flashActive ? const Color(0xFF221E0A) : const Color(0xFF0A0D16), // Hueco con destello citrino
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: flashActive
              ? const Color(0xFFFACC15) // Amarillo Citrino brillante
              : const Color(0xFF00E5FF).withOpacity(0.55), // Borde cian normal
          width: flashActive ? 1.8 : 1.0,
        ),
        boxShadow: [
          // Sombra interior / inset simulado
          const BoxShadow(
            color: Color(0xCC000000),
            offset: Offset(1.5, 2.0),
            blurRadius: 3.0,
          ),
          if (flashActive) ...[
            BoxShadow(
              color: const Color(0xFFFACC15).withOpacity(0.90), // Fogonazo Amarillo Citrino
              blurRadius: 14.0,
              spreadRadius: 2.5,
            ),
            const BoxShadow(
              color: Colors.white,
              blurRadius: 4.0,
              spreadRadius: 1.0,
            ),
          ] else
            BoxShadow(
              color: const Color(0xFF00E5FF).withOpacity(0.08),
              blurRadius: 4.0,
            ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              title,
              style: TextStyle(
                color: flashActive ? const Color(0xFFFEF08A) : const Color(0xFF38BDF8),
                fontSize: 7.0,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.4,
              ),
              maxLines: 1,
            ),
          ),
          const SizedBox(height: 1.5),
          if (value != null)
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: TextStyle(
                  // PUNTOS, HI-SCORE, LÍNEAS en Amarillo Citrino brillante
                  color: flashActive ? Colors.white : const Color(0xFFFACC15),
                  fontSize: 10.0,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.6,
                  shadows: [
                    Shadow(
                      color: flashActive ? const Color(0xFFFACC15) : const Color(0x66FACC15),
                      blurRadius: flashActive ? 12 : 6,
                    ),
                  ],
                ),
                maxLines: 1,
              ),
            )
          else if (child != null)
            child,
        ],
      ),
    );
  }
}

/// Overlay sutil de scanlines CRT y curvatura simulando un monitor de tubo recreativo de los 90
class CrtScanlinesOverlayPainter extends CustomPainter {
  const CrtScanlinesOverlayPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // Líneas horizontales de barrido CRT semitransparentes
    final linePaint = Paint()
      ..color = const Color(0x15000000)
      ..strokeWidth = 1.0;

    for (double y = 0; y < size.height; y += 3.0) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }

    // Efecto de viñeteado / curvatura en los bordes del monitor CRT
    final vignettePaint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 0.95,
        colors: [
          Colors.transparent,
          Colors.black.withOpacity(0.24),
        ],
        stops: const [0.78, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), vignettePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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

    // 3. Sombra Holográfica de Caída (Ghost Piece) y 4. Pieza Activa en el Aire
    if (engine.currentPiece != null && !engine.isGameOver) {
      final piece = engine.currentPiece!;
      final shape = tetrominoShapes[piece.type]![piece.rotation];
      final ghostPos = engine.getGhostPosition();
      final pieceColor = tetrominoColors[piece.type] ?? const Color(0xFF00E5FF);

      // Barra 2: Fichas invisibles titilando si invisibleFlickerTimer > 0
      final bool isInvisibleMode = engine.invisibleFlickerTimer > 0;
      final double flickerVal = (sin(ambientTime * 14.0) * 0.5 + 0.5);
      final double activeOpacity = isInvisibleMode ? (flickerVal > 0.65 ? 0.30 : 0.02) : 1.0;

      // Sombra Ghost Piece: oculta en modo invisible para no delatar la posición
      if (!isInvisibleMode) {
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
      }

      // 4. Pieza Activa en el Aire (CUBITOS INDIVIDUALES MIENTRAS CAE)
      final smoothY = engine.getRenderY();
      if (activeOpacity < 1.0) {
        canvas.saveLayer(
          Rect.fromLTWH(0, 0, size.width, size.height),
          Paint()..color = Color.fromRGBO(255, 255, 255, activeOpacity),
        );
      }

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

      if (activeOpacity < 1.0) {
        canvas.restore();
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
    if (cell.cubeType == CubeType.star) {
      _drawStarCube(canvas, cellRect);
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

  /// Renderizado de Minicubo Estrella de Lluvia Cósmica (Barra 4)
  void _drawStarCube(Canvas canvas, Rect rect) {
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(2.5));
    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF3B0764), Color(0xFF1E1B4B)],
      ).createShader(rect);
    canvas.drawRRect(rrect, bgPaint);

    final borderPaint = Paint()
      ..color = const Color(0xFFFFD700).withOpacity(0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawRRect(rrect, borderPaint);

    final haloPaint = Paint()
      ..color = const Color(0xFFFFD700).withOpacity(0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
    canvas.drawCircle(rect.center, rect.width * 0.35, haloPaint);

    final starPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final c = rect.center;
    final r = rect.width * 0.35;
    final Path path = Path();
    path.moveTo(c.dx, c.dy - r);
    path.quadraticBezierTo(c.dx, c.dy, c.dx + r, c.dy);
    path.quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r);
    path.quadraticBezierTo(c.dx, c.dy, c.dx - r, c.dy);
    path.quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r);
    path.close();
    canvas.drawPath(path, starPaint);
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

/// CustomPainter para el minimapa en vivo del rival (10 columnas x 20 filas visibles)
class OpponentBoardMinimapPainter extends CustomPainter {
  final List<List<int>> matrix;

  OpponentBoardMinimapPainter({required this.matrix});

  @override
  void paint(Canvas canvas, Size size) {
    final cellW = size.width / 10.0;
    final cellH = size.height / 20.0;

    // Fondo oscuro profundo
    final bgPaint = Paint()..color = const Color(0xFF0D1117);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // Línea de alerta roja a las 4 filas superiores (zona crítica)
    final dangerPaint = Paint()
      ..color = const Color(0xFFFF1744).withOpacity(0.40)
      ..strokeWidth = 0.6;
    canvas.drawLine(Offset(0, 4 * cellH), Offset(size.width, 4 * cellH), dangerPaint);

    if (matrix.isEmpty) {
      // Rejilla sutil vacía de espera
      final linePaint = Paint()
        ..color = const Color(0xFF1F2937).withOpacity(0.5)
        ..strokeWidth = 0.4;
      for (int c = 1; c < 10; c++) {
        canvas.drawLine(Offset(c * cellW, 0), Offset(c * cellW, size.height), linePaint);
      }
      for (int r = 1; r < 20; r++) {
        canvas.drawLine(Offset(0, r * cellH), Offset(size.width, r * cellH), linePaint);
      }
      return;
    }

    final blockPaint = Paint()..color = const Color(0xFF38BDF8);
    final starPaint = Paint()..color = const Color(0xFFFFD700);

    final rows = matrix.length;
    for (int y = 0; y < rows && y < 20; y++) {
      final row = matrix[y];
      for (int x = 0; x < row.length && x < 10; x++) {
        final val = row[x];
        if (val > 0) {
          final rect = Rect.fromLTWH(
            x * cellW + 0.35,
            y * cellH + 0.35,
            cellW - 0.7,
            cellH - 0.7,
          );
          if (val == 2) {
            canvas.drawRect(rect, starPaint);
          } else {
            canvas.drawRect(rect, blockPaint);
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant OpponentBoardMinimapPainter oldDelegate) => true;
}

