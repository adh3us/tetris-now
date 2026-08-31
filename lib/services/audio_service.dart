import 'package:flutter/services.dart';

enum TetrisSfx {
  move,
  rotate,
  hold,
  softDrop,
  hardDrop,
  lineClear,
  tetris,
  shieldActivate,
  shieldExpire,
  damageReceived,
  gameOver,
}

class TetrisAudioService {
  static final TetrisAudioService _instance = TetrisAudioService._internal();
  factory TetrisAudioService() => _instance;
  TetrisAudioService._internal();

  bool isSoundEnabled = true;
  bool isHapticsEnabled = true;

  /// Reproduce feedback háptico y efectos sonoros de acción
  void play(TetrisSfx sfx) {
    if (!isHapticsEnabled) return;

    switch (sfx) {
      case TetrisSfx.move:
      case TetrisSfx.rotate:
        HapticFeedback.selectionClick();
        break;
      case TetrisSfx.hold:
        HapticFeedback.lightImpact();
        break;
      case TetrisSfx.softDrop:
        HapticFeedback.lightImpact();
        break;
      case TetrisSfx.hardDrop:
        HapticFeedback.mediumImpact();
        break;
      case TetrisSfx.lineClear:
        HapticFeedback.mediumImpact();
        break;
      case TetrisSfx.tetris:
      case TetrisSfx.shieldActivate:
        HapticFeedback.heavyImpact();
        break;
      case TetrisSfx.damageReceived:
      case TetrisSfx.gameOver:
        HapticFeedback.vibrate();
        break;
      default:
        break;
    }
  }
}
