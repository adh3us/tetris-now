import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';

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
  combo,
}

class TetrisAudioService {
  static final TetrisAudioService _instance = TetrisAudioService._internal();
  factory TetrisAudioService() => _instance;
  TetrisAudioService._internal() {
    _initPlayers();
  }

  bool isSoundEnabled = true;
  bool isHapticsEnabled = true;

  // Pool de reproductores para baja latencia a 60 FPS
  final List<AudioPlayer> _sfxPool = [];
  int _poolIndex = 0;
  static const int _poolSize = 4;

  final Map<TetrisSfx, String> _sfxFiles = {
    TetrisSfx.move: 'audio/move.wav',
    TetrisSfx.rotate: 'audio/rotate.wav',
    TetrisSfx.hold: 'audio/hold.wav',
    TetrisSfx.softDrop: 'audio/soft_drop.wav',
    TetrisSfx.hardDrop: 'audio/hard_drop.wav',
    TetrisSfx.lineClear: 'audio/line_clear.wav',
    TetrisSfx.tetris: 'audio/tetris.wav',
    TetrisSfx.shieldActivate: 'audio/shield_activate.wav',
    TetrisSfx.shieldExpire: 'audio/shield_expire.wav',
    TetrisSfx.damageReceived: 'audio/damage_received.wav',
    TetrisSfx.gameOver: 'audio/game_over.wav',
    TetrisSfx.combo: 'audio/combo.wav',
  };

  void _initPlayers() {
    for (int i = 0; i < _poolSize; i++) {
      final player = AudioPlayer();
      player.setReleaseMode(ReleaseMode.stop);
      _sfxPool.add(player);
    }
  }

  /// Reproduce feedback sonoro y háptico con baja latencia
  void play(TetrisSfx sfx) {
    // 1. Hápticos de vibración
    if (isHapticsEnabled) {
      switch (sfx) {
        case TetrisSfx.move:
        case TetrisSfx.rotate:
          HapticFeedback.selectionClick();
          break;
        case TetrisSfx.hold:
        case TetrisSfx.softDrop:
          HapticFeedback.lightImpact();
          break;
        case TetrisSfx.hardDrop:
        case TetrisSfx.lineClear:
        case TetrisSfx.combo:
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

    // 2. Audio SFX
    if (!isSoundEnabled) return;

    final fileName = _sfxFiles[sfx];
    if (fileName == null) return;

    try {
      if (_sfxPool.isEmpty) return;
      final player = _sfxPool[_poolIndex];
      _poolIndex = (_poolIndex + 1) % _poolSize;

      player.play(AssetSource(fileName), volume: _getVolume(sfx));
    } catch (_) {}
  }

  double _getVolume(TetrisSfx sfx) {
    switch (sfx) {
      case TetrisSfx.move:
      case TetrisSfx.softDrop:
        return 0.45;
      case TetrisSfx.rotate:
      case TetrisSfx.hold:
        return 0.60;
      case TetrisSfx.hardDrop:
      case TetrisSfx.lineClear:
      case TetrisSfx.combo:
        return 0.85;
      case TetrisSfx.tetris:
      case TetrisSfx.shieldActivate:
      case TetrisSfx.gameOver:
      case TetrisSfx.damageReceived:
        return 1.0;
      default:
        return 0.70;
    }
  }
}
