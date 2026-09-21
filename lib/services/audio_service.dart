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
  bool isMusicEnabled = true;
  double musicVolume = 0.50;

  static const String bgmBattle = 'audio/bgm_battle.mp3';
  static const String bgmLobby = 'audio/bgm_lobby.mp3';

  // Reproductor dedicado para Música de Fondo (BGM) en bucle
  AudioPlayer? _bgmPlayer;
  String? _currentMusicPath;

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
    _bgmPlayer = AudioPlayer();
    _bgmPlayer?.setReleaseMode(ReleaseMode.loop);
  }

  /// Reproduce música de fondo en bucle infinito (.mp3, .ogg o .wav)
  Future<void> playMusic(String assetRelativePath, {double? volume, bool loop = true}) async {
    if (!isMusicEnabled) return;
    _currentMusicPath = assetRelativePath;
    final vol = volume ?? musicVolume;

    try {
      _bgmPlayer ??= AudioPlayer();
      await _bgmPlayer!.setReleaseMode(loop ? ReleaseMode.loop : ReleaseMode.stop);
      await _bgmPlayer!.setVolume(vol);
      // assetRelativePath debe ser relativo a assets/ (ej: 'audio/bgm_battle.mp3')
      await _bgmPlayer!.play(AssetSource(assetRelativePath));
    } catch (_) {}
  }

  /// Pausa la música de fondo
  Future<void> pauseMusic() async {
    try {
      await _bgmPlayer?.pause();
    } catch (_) {}
  }

  /// Reanuda la música si estaba pausada
  Future<void> resumeMusic() async {
    if (!isMusicEnabled) return;
    try {
      await _bgmPlayer?.resume();
    } catch (_) {}
  }

  /// Detiene la música de fondo
  Future<void> stopMusic() async {
    try {
      await _bgmPlayer?.stop();
    } catch (_) {}
  }

  /// Cambia el volumen de la música (0.0 a 1.0)
  Future<void> setMusicVolume(double volume) async {
    musicVolume = volume.clamp(0.0, 1.0);
    try {
      await _bgmPlayer?.setVolume(musicVolume);
    } catch (_) {}
  }

  /// Activa o desactiva la música
  Future<void> setMusicEnabled(bool enabled) async {
    isMusicEnabled = enabled;
    if (!enabled) {
      await stopMusic();
    } else if (_currentMusicPath != null) {
      await playMusic(_currentMusicPath!);
    }
  }

  /// Reproduce feedback sonoro puro de baja latencia (sin vibración)
  void play(TetrisSfx sfx) {
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
