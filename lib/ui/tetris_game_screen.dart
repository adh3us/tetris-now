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

class TetrisGameScreen extends StatefulWidget {
  final String? matchId;
  final String? myTeamId;
  final String? opponentTeamId;
  final TetrisRealtimeService? realtimeService;
  final GameMode mode;

  const TetrisGameScreen({
    Key? key,
    this.matchId,
    this.myTeamId,
    this.opponentTeamId,
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

    if (widget.mode == GameMode.coop2v2Wide || widget.mode == GameMode.team2v2Combat) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }

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

      final res = _engine.update(dt);
      if (res != null) {
        _processAttackResult(res);
      }
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
      widget.realtimeService!.onIncomingAttack = (lines, tier) {
        if (!mounted) return;
        setState(() {
          if (_engine.isShieldActive) {
            _combatLog = '¡Ataque de $lines líneas bloqueado por tu Escudo!';
          } else {
            _engine.receiveGarbage(lines, tier == CubeType.gold ? CubeType.gold : (tier == CubeType.silver ? CubeType.silver : CubeType.none));
            _audioService.play(TetrisSfx.damageReceived);
            _combatLog = 'Recibiste +$lines líneas de basura.';
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
        _showEndDialog(isVictory ? '¡VICTORIA!' : 'DERROTA');
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
            _combatLog = '⚡ ¡ESCUDO ACTIVADO! (20s de inmunidad) ⚡';
          }
          break;
        case GameAction.pause:
          _engine.isPaused = !_engine.isPaused;
          _showPauseDialog();
          break;
        case GameAction.reset:
          _engine.reset();
          break;
      }
    });
  }

  void _showPauseDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        title: const Text('PAUSA', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Partida en pausa', style: TextStyle(color: Color(0xFF8B949E))),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(ctx).pop();
                setState(() => _engine.isPaused = false);
              },
              icon: const Icon(Icons.play_arrow),
              label: const Text('CONTINUAR', style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF238636)),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(ctx).pop();
                _handleAction(GameAction.reset);
              },
              icon: const Icon(Icons.refresh),
              label: const Text('REINICIAR PARTIDA', style: TextStyle(color: Colors.white)),
              style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFF30363D))),
            ),
          ],
        ),
      ),
    );
  }

  void _processAttackResult(AttackResult res) {
    if (res.linesCleared == 4) {
      _audioService.play(TetrisSfx.tetris);
    } else if (res.linesCleared > 0) {
      _audioService.play(TetrisSfx.lineClear);
    }

    if (res.linesSent > 0 && widget.realtimeService != null) {
      widget.realtimeService!.sendAttack(lines: res.linesSent);
      _combatLog = 'Enviaste +${res.linesSent} líneas al rival.';
    }
    if (res.goldCubeLines > 0 && widget.realtimeService != null) {
      widget.realtimeService!.sendAttack(lines: 8, tier: CubeType.gold);
      _combatLog = '¡ATAQUE DE CUBO DORADO (+8 líneas)!';
    }
    if (res.silverCubeLines > 0 && widget.realtimeService != null) {
      widget.realtimeService!.sendAttack(lines: 4, tier: CubeType.silver);
      _combatLog = '¡ATAQUE DE CUBO PLATEADO (+4 líneas)!';
    }
  }

  void _handleGameOver() {
    _ticker.stop();
    _audioService.play(TetrisSfx.gameOver);

    if (widget.matchId != null && widget.opponentTeamId != null) {
      widget.realtimeService?.sendKnockout();
      widget.realtimeService?.sendMatchEnd(widget.opponentTeamId!);

      _matchService.reportMatchResult(
        matchId: widget.matchId!,
        winnerTeamId: widget.opponentTeamId!,
      );
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
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return OrientationBuilder(
      builder: (context, orientation) {
        final isLandscape = orientation == Orientation.landscape || widget.mode == GameMode.coop2v2Wide;
        return Focus(
          focusNode: _focusNode,
          autofocus: true,
          onKeyEvent: _handleKeyEvent,
          child: Scaffold(
            backgroundColor: const Color(0xFF080A0F),
            body: SafeArea(
              child: isLandscape ? _buildLandscapeLayout() : _buildPortraitLayout(),
            ),
          ),
        );
      },
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableH = constraints.maxHeight - 195.0;
        final boardH = availableH.clamp(260.0, 440.0);
        final boardW = (boardH / 20.0) * 10.0;

        return Column(
          children: [
            _buildTopHeader(),
            _buildShieldBar(isCompact: false),
            Expanded(
              child: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Hold & Stats
                    SizedBox(
                      width: 56,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          GestureDetector(
                            onTap: () => _handleAction(GameAction.hold),
                            child: _buildCard(
                              title: 'HOLD (L1)',
                              child: CustomPaint(
                                size: const Size(38, 38),
                                painter: TetrominoPreviewPainter(type: _engine.holdPiece),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          _buildCard(title: 'LÍNEAS', value: '${_engine.linesCleared}'),
                          const SizedBox(height: 6),
                          _buildCard(title: 'ENVIADAS', value: '${_engine.linesSent}'),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),

                    _buildInteractiveBoard(boardW, boardH),
                    const SizedBox(width: 6),

                    // Next & Combo
                    SizedBox(
                      width: 56,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildCard(
                            title: 'NEXT',
                            child: Column(
                              children: _engine.nextQueue.take(3).map((type) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 2.5),
                                  child: CustomPaint(
                                    size: const Size(30, 24),
                                    painter: TetrominoPreviewPainter(type: type),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                          const SizedBox(height: 6),
                          _buildCard(title: 'COMBO', value: '${_engine.combo}'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              child: Text(
                _combatLog,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF8B949E), fontSize: 9.0, fontFamily: 'monospace'),
              ),
            ),

            VirtualControllerWrapper(
              onAction: _handleAction,
              initialTheme: _controllerTheme,
              opacity: _controllerOpacity,
              isVisible: _isControllerVisible,
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
      },
    );
  }

  Widget _buildTopHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Flexible(
            child: Text(
              'TETRIS NOW BY GAMEROS',
              style: TextStyle(color: Color(0xFF5865F2), fontWeight: FontWeight.w900, fontSize: 11.5, letterSpacing: 0.8),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          Row(
            children: [
              GestureDetector(
                onTap: _cycleOpacity,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: _isControllerVisible ? const Color(0xFF238636) : const Color(0xFFDA3633),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.gamepad, size: 11, color: Colors.white),
                      const SizedBox(width: 2),
                      Text(
                        _isControllerVisible ? '${(_controllerOpacity * 100).toInt()}%' : 'OFF',
                        style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF161B22),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFF30363D)),
                ),
                child: const Text('Manba one / PS5', style: TextStyle(color: Colors.white70, fontSize: 8)),
              ),
            ],
          ),
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
        child: CustomPaint(
          size: Size(width, height),
          painter: TetrisBoardPainter(engine: _engine),
        ),
      ),
    );
  }

  Widget _buildCard({required String title, String? value, Widget? child}) {
    return Container(
      padding: const EdgeInsets.all(3.5),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Column(
        children: [
          Text(title, style: const TextStyle(color: Color(0xFF8B949E), fontSize: 7.0, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          if (value != null)
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold))
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

  TetrisBoardPainter({required this.engine});

  @override
  void paint(Canvas canvas, Size size) {
    final blockW = size.width / engine.cols;
    final blockH = size.height / engine.rows;

    // 0. Fondo Cyber Board con Profundidad Radial
    final bgRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final bgPaint = Paint()
      ..shader = const RadialGradient(
        center: Alignment(0.0, -0.2),
        radius: 1.25,
        colors: [
          Color(0xFF111827),
          Color(0xFF070A0F),
        ],
      ).createShader(bgRect);
    canvas.drawRect(bgRect, bgPaint);

    // Grilla Cyber-Laser
    final gridLinePaint = Paint()
      ..color = const Color(0xFF1F2937).withOpacity(0.40)
      ..strokeWidth = 0.5;
    for (int c = 1; c < engine.cols; c++) {
      canvas.drawLine(Offset(c * blockW, 0), Offset(c * blockW, size.height), gridLinePaint);
    }
    for (int r = 1; r < engine.rows; r++) {
      canvas.drawLine(Offset(0, r * blockH), Offset(size.width, r * blockH), gridLinePaint);
    }

    // Línea de Alerta / Peligro (Top 4 rows)
    final dangerPaint = Paint()
      ..color = const Color(0xFFEF4444).withOpacity(0.35)
      ..strokeWidth = 0.8;
    canvas.drawLine(Offset(0, 4 * blockH), Offset(size.width, 4 * blockH), dangerPaint);

    // 1. Celdas Bloqueadas en la Grilla
    for (int y = 0; y < engine.rows; y++) {
      for (int x = 0; x < engine.cols; x++) {
        final cell = engine.grid[y][x];
        if (cell != null) {
          _draw3DBlock(
            canvas: canvas,
            x: x * blockW,
            y: y * blockH,
            w: blockW,
            h: blockH,
            type: cell.type,
            cubeType: cell.cubeType,
          );
        }
      }
    }

    // 2. Sombra Holográfica de Caída (Ghost Piece - Tetris Effect Glow)
    if (engine.currentPiece != null && !engine.isGameOver) {
      final piece = engine.currentPiece!;
      final shape = tetrominoShapes[piece.type]![piece.rotation];
      final ghostPos = engine.getGhostPosition();
      final pieceColor = tetrominoColors[piece.type] ?? const Color(0xFF00E5FF);

      for (int r = 0; r < shape.length; r++) {
        for (int c = 0; c < shape[r].length; c++) {
          if (shape[r][c] != 0) {
            final gx = (ghostPos.x + c) * blockW;
            final gy = (ghostPos.y + r) * blockH;
            _drawGhostCell(canvas, gx, gy, blockW, blockH, pieceColor);
          }
        }
      }

      // 3. Pieza Activa deslizándose de forma fluida a 60 FPS
      final smoothY = engine.getRenderY();
      for (int r = 0; r < shape.length; r++) {
        for (int c = 0; c < shape[r].length; c++) {
          if (shape[r][c] != 0) {
            final px = (piece.position.x + c) * blockW;
            final py = (smoothY + r) * blockH;
            _draw3DBlock(
              canvas: canvas,
              x: px,
              y: py,
              w: blockW,
              h: blockH,
              type: piece.type,
              cubeType: CubeType.none,
              isActive: true,
            );
          }
        }
      }
    }
  }

  /// Renderizado de Bloque 3D con Biseles, Volumen y Textura Metálica/Cristal
  void _draw3DBlock({
    required Canvas canvas,
    required double x,
    required double y,
    required double w,
    required double h,
    required TetrominoType type,
    required CubeType cubeType,
    bool isActive = false,
  }) {
    const margin = 0.7;
    final rect = Rect.fromLTWH(x + margin, y + margin, w - (margin * 2), h - (margin * 2));
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(2.2));

    // A. CUBO DORADO MONOLÍTICO (The New Tetris - Monocube 4x4)
    if (cubeType == CubeType.gold) {
      _drawGoldBlock(canvas, rect, rrect);
      return;
    }

    // B. CUBO PLATEADO CROMADO (The New Tetris - Multicube 4x4)
    if (cubeType == CubeType.silver) {
      _drawSilverBlock(canvas, rect, rrect);
      return;
    }

    // C. BLOQUES ESTÁNDAR / NEÓN 3D
    final baseColor = tetrominoColors[type] ?? const Color(0xFF00E5FF);
    final HSLColor hsl = HSLColor.fromColor(baseColor);
    final Color topLight = hsl.withLightness((hsl.lightness + 0.22).clamp(0.0, 1.0)).toColor();
    final Color mainColor = baseColor;
    final Color darkShadow = hsl.withLightness((hsl.lightness - 0.26).clamp(0.0, 1.0)).toColor();

    // 1. Bisel Base (Volumen y Sombras de Bordes)
    final Path bevelPath = Path()..addRRect(rrect);
    final Paint bevelPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          topLight.withOpacity(0.95),
          mainColor,
          darkShadow,
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(rect);
    canvas.drawPath(bevelPath, bevelPaint);

    // 2. Faceta Central Embossed
    const bevelInset = 2.2;
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
        colors: [
          mainColor,
          hsl.withLightness((hsl.lightness - 0.12).clamp(0.0, 1.0)).toColor(),
        ],
      ).createShader(innerRect);
    canvas.drawRRect(innerRRect, innerPaint);

    // 3. Brillo Especular de Cristal Superior Izquierdo
    final gleamPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withOpacity(0.55),
          Colors.white.withOpacity(0.0),
        ],
        stops: const [0.0, 0.7],
      ).createShader(innerRect);
    final gleamPath = Path()
      ..moveTo(innerRect.left, innerRect.top)
      ..lineTo(innerRect.left + (innerRect.width * 0.75), innerRect.top)
      ..lineTo(innerRect.left, innerRect.top + (innerRect.height * 0.75))
      ..close();
    canvas.drawPath(gleamPath, gleamPaint);

    // 4. Borde Perimetral Fino Neón
    final borderPaint = Paint()
      ..color = isActive ? Colors.white.withOpacity(0.6) : Colors.white.withOpacity(0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;
    canvas.drawRRect(rrect, borderPaint);
  }

  /// Renderizado de Monocubo Dorado (Oro Pulido 4x4)
  void _drawGoldBlock(Canvas canvas, Rect rect, RRect rrect) {
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

    final paint = Paint()..shader = goldGradient;
    canvas.drawRRect(rrect, paint);

    const inset = 2.0;
    final innerRect = Rect.fromLTWH(rect.left + inset, rect.top + inset, rect.width - inset * 2, rect.height - inset * 2);
    final innerRRect = RRect.fromRectAndRadius(innerRect, const Radius.circular(1.0));

    final innerGold = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFFFFD700),
          Color(0xFFC69214),
        ],
      ).createShader(innerRect);
    canvas.drawRRect(innerRRect, innerGold);

    final shinePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withOpacity(0.65),
          Colors.white.withOpacity(0.0),
        ],
      ).createShader(innerRect);
    final shinePath = Path()
      ..moveTo(innerRect.left, innerRect.top)
      ..lineTo(innerRect.left + innerRect.width * 0.8, innerRect.top)
      ..lineTo(innerRect.left, innerRect.top + innerRect.height * 0.8)
      ..close();
    canvas.drawPath(shinePath, shinePaint);

    final borderPaint = Paint()
      ..color = const Color(0xFFFFFBEA)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    canvas.drawRRect(rrect, borderPaint);
  }

  /// Renderizado de Multicubo Plateado (Cromo Reflectante 4x4)
  void _drawSilverBlock(Canvas canvas, Rect rect, RRect rrect) {
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
      stops: [0.0, 0.20, 0.45, 0.70, 0.90, 1.0],
    ).createShader(rect);

    final paint = Paint()..shader = silverGradient;
    canvas.drawRRect(rrect, paint);

    const inset = 2.0;
    final innerRect = Rect.fromLTWH(rect.left + inset, rect.top + inset, rect.width - inset * 2, rect.height - inset * 2);
    final innerRRect = RRect.fromRectAndRadius(innerRect, const Radius.circular(1.0));

    final innerSilver = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFFE2E8F0),
          Color(0xFF94A3B8),
        ],
      ).createShader(innerRect);
    canvas.drawRRect(innerRRect, innerSilver);

    final shinePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withOpacity(0.75),
          Colors.white.withOpacity(0.0),
        ],
      ).createShader(innerRect);
    final shinePath = Path()
      ..moveTo(innerRect.left, innerRect.top)
      ..lineTo(innerRect.left + innerRect.width * 0.8, innerRect.top)
      ..lineTo(innerRect.left, innerRect.top + innerRect.height * 0.8)
      ..close();
    canvas.drawPath(shinePath, shinePaint);

    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    canvas.drawRRect(rrect, borderPaint);
  }

  /// Renderizado de Ghost Piece Holográfico con Neón Glow (Tetris Effect)
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
