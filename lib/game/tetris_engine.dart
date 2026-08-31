import 'dart:math';
import 'tetris_types.dart';

class TetrisEngine {
  final int cols;
  final int rows;
  final GameMode mode;

  late List<List<Cell?>> grid;
  PieceState? currentPiece;
  TetrominoType? holdPiece;
  bool canHold = true;
  List<TetrominoType> nextQueue = [];
  List<TetrominoType> _bag = [];
  int _pieceCounter = 1;

  int linesCleared = 0;
  int linesSent = 0;
  int combo = 0;
  int level = 1;
  bool isGameOver = false;
  bool isPaused = false;

  // Caida fluida continua a 60 FPS
  double fallProgress = 0.0;
  double dropSpeed = 1.0;

  // Escudo / Inmunidad Especial (Estilo Zone de Tetris Effect)
  int defenseEnergy = 0; // 0 a 5
  bool isShieldActive = false;
  int shieldSecondsRemaining = 0;
  final Random _rng = Random();

  TetrisEngine({
    this.cols = 10,
    this.rows = 20,
    this.mode = GameMode.solo,
  }) {
    reset();
  }

  void reset() {
    grid = List.generate(rows, (_) => List.generate(cols, (_) => null));
    _bag = [];
    nextQueue = [];
    _pieceCounter = 1;
    currentPiece = null;
    holdPiece = null;
    canHold = true;
    linesCleared = 0;
    linesSent = 0;
    combo = 0;
    level = 1;
    isGameOver = false;
    isPaused = false;
    defenseEnergy = 0;
    isShieldActive = false;
    shieldSecondsRemaining = 0;
    fallProgress = 0.0;
    _updateDropSpeed();

    _refillBag();
    spawnPiece();
  }

  void _updateDropSpeed() {
    dropSpeed = 1.0 + (level - 1) * 0.15;
  }

  void _refillBag() {
    final bagItems = [
      TetrominoType.I, TetrominoType.J, TetrominoType.L,
      TetrominoType.O, TetrominoType.S, TetrominoType.T, TetrominoType.Z,
    ];
    bagItems.shuffle(_rng);
    _bag.addAll(bagItems);
  }

  TetrominoType _getNextType() {
    if (_bag.length < 5) _refillBag();
    return _bag.removeAt(0);
  }

  bool spawnPiece() {
    while (nextQueue.length < 4) nextQueue.add(_getNextType());
    final nextType = nextQueue.removeAt(0);
    final startX = (cols ~/ 2) - 2;
    final piece = PieceState(type: nextType, rotation: 0, position: Position(startX, 0));

    if (checkCollision(piece, piece.position.x, piece.position.y)) {
      isGameOver = true;
      currentPiece = null;
      return false;
    }
    currentPiece = piece;
    canHold = true;
    fallProgress = 0.0;
    return true;
  }

  bool checkCollision(PieceState piece, int offsetX, int offsetY, [int? rotIndex]) {
    final rotation = rotIndex ?? piece.rotation;
    final shape = tetrominoShapes[piece.type]![rotation];
    for (int r = 0; r < shape.length; r++) {
      for (int c = 0; c < shape[r].length; c++) {
        if (shape[r][c] != 0) {
          final nx = offsetX + c;
          final ny = offsetY + r;
          if (nx < 0 || nx >= cols || ny >= rows) return true;
          if (ny >= 0 && grid[ny][nx] != null) return true;
        }
      }
    }
    return false;
  }

  AttackResult? update(double dt) {
    if (currentPiece == null || isGameOver || isPaused) return null;

    fallProgress += dropSpeed * dt;
    if (fallProgress >= 1.0) {
      final rowsToFall = fallProgress.floor();
      fallProgress -= rowsToFall;

      for (int i = 0; i < rowsToFall; i++) {
        if (!checkCollision(currentPiece!, currentPiece!.position.x, currentPiece!.position.y + 1)) {
          currentPiece!.position.y++;
        } else {
          fallProgress = 0.0;
          return lockPiece();
        }
      }
    }
    return null;
  }

  bool moveLeft() {
    if (currentPiece == null || isGameOver || isPaused) return false;
    if (!checkCollision(currentPiece!, currentPiece!.position.x - 1, currentPiece!.position.y)) {
      currentPiece!.position.x--;
      return true;
    }
    return false;
  }

  bool moveRight() {
    if (currentPiece == null || isGameOver || isPaused) return false;
    if (!checkCollision(currentPiece!, currentPiece!.position.x + 1, currentPiece!.position.y)) {
      currentPiece!.position.x++;
      return true;
    }
    return false;
  }

  bool softDrop() {
    if (currentPiece == null || isGameOver || isPaused) return false;
    if (!checkCollision(currentPiece!, currentPiece!.position.x, currentPiece!.position.y + 1)) {
      currentPiece!.position.y++;
      fallProgress = 0.0;
      return true;
    } else {
      lockPiece();
      return false;
    }
  }

  bool rotate(int direction) {
    if (currentPiece == null || isGameOver || isPaused) return false;
    final newRot = (currentPiece!.rotation + direction + 4) % 4;
    final kicks = [Position(0, 0), Position(direction, 0), Position(direction, -1), Position(0, 2)];

    for (final offset in kicks) {
      final testX = currentPiece!.position.x + offset.x;
      final testY = currentPiece!.position.y + offset.y;
      if (!checkCollision(currentPiece!, testX, testY, newRot)) {
        currentPiece!.position.x = testX;
        currentPiece!.position.y = testY;
        currentPiece!.rotation = newRot;
        return true;
      }
    }
    return false;
  }

  AttackResult hardDrop() {
    if (currentPiece == null || isGameOver || isPaused) {
      return AttackResult(linesCleared: 0, linesSent: 0, energyGained: 0);
    }
    while (!checkCollision(currentPiece!, currentPiece!.position.x, currentPiece!.position.y + 1)) {
      currentPiece!.position.y++;
    }
    fallProgress = 0.0;
    return lockPiece();
  }

  bool hold() {
    if (currentPiece == null || !canHold || isGameOver || isPaused) return false;
    final startX = (cols ~/ 2) - 2;
    if (holdPiece == null) {
      holdPiece = currentPiece!.type;
      spawnPiece();
    } else {
      final temp = holdPiece!;
      holdPiece = currentPiece!.type;
      currentPiece = PieceState(type: temp, rotation: 0, position: Position(startX, 0));
    }
    canHold = false;
    fallProgress = 0.0;
    return true;
  }

  AttackResult lockPiece() {
    if (currentPiece == null) return AttackResult(linesCleared: 0, linesSent: 0, energyGained: 0);

    final pieceId = _pieceCounter++;
    final shape = tetrominoShapes[currentPiece!.type]![currentPiece!.rotation];
    for (int r = 0; r < shape.length; r++) {
      for (int c = 0; c < shape[r].length; c++) {
        if (shape[r][c] != 0) {
          final px = currentPiece!.position.x + c;
          final py = currentPiece!.position.y + r;
          if (py >= 0 && py < rows && px >= 0 && px < cols) {
            // Guardar pieza lisa estilo The New Tetris
            grid[py][px] = Cell(type: currentPiece!.type, cubeType: CubeType.none, pieceId: pieceId);
          }
        }
      }
    }
    currentPiece = null;

    // Detectar si se formó un Cubo Dorado (Monocube) o Plateado (Multicube) 4x4
    detectNewTetrisCubes();

    final result = clearLines();
    spawnPiece();
    return result;
  }

  /// Mecánica oficial de 'The New Tetris' (N64): Detección de Monocubos (Oro) y Multicubos (Plata) 4x4
  void detectNewTetrisCubes() {
    for (int y = 0; y <= rows - 4; y++) {
      for (int x = 0; x <= cols - 4; x++) {
        bool isFullSquare = true;
        bool alreadyFormed = false;
        final Set<int> pieceIds = {};
        final Set<TetrominoType> pieceTypes = {};

        for (int r = 0; r < 4; r++) {
          for (int c = 0; c < 4; c++) {
            final cell = grid[y + r][x + c];
            if (cell == null || cell.type == TetrominoType.GARBAGE) {
              isFullSquare = false;
              break;
            }
            if (cell.cubeType != CubeType.none) {
              alreadyFormed = true;
            }
            pieceIds.add(cell.pieceId);
            pieceTypes.add(cell.type);
          }
          if (!isFullSquare) break;
        }

        // Un cubo 4x4 válido en The New Tetris se compone de 4 tetrominoes que encajan perfectamente (16 bloques)
        if (isFullSquare && !alreadyFormed && pieceIds.length == 4) {
          // Monocube (Oro): Las 4 piezas son idénticas
          final isMonocube = pieceTypes.length == 1;
          final targetCube = isMonocube ? CubeType.gold : CubeType.silver;

          for (int r = 0; r < 4; r++) {
            for (int c = 0; c < 4; c++) {
              grid[y + r][x + c]!.cubeType = targetCube;
            }
          }
        }
      }
    }
  }

  /// Limpieza de líneas con liberación inmediata del espacio vacío (Cero celdas fantasmas)
  AttackResult clearLines() {
    int cleared = 0;
    int goldLines = 0;
    int silverLines = 0;

    for (int y = rows - 1; y >= 0; y--) {
      // Si la fila entera está llena
      if (grid[y].every((cell) => cell != null)) {
        cleared++;

        // Verificar si la línea atraviesa cubos de Oro o Plata para bonificación de ataque
        for (int x = 0; x < cols; x++) {
          final cell = grid[y][x]!;
          if (cell.cubeType == CubeType.gold) goldLines++;
          if (cell.cubeType == CubeType.silver) silverLines++;
        }

        // Eliminar completamente la fila del grid (liberando el espacio al 100%)
        grid.removeAt(y);
        // Insertar fila limpia de celdas null arriba
        grid.insert(0, List<Cell?>.generate(cols, (_) => null));
        // Repetir evaluación para la fila que cayó
        y++;
      }
    }

    int attackLines = 0;
    int energyGain = 0;

    if (cleared > 0) {
      linesCleared += cleared;
      combo++;
      level = (linesCleared ~/ 10) + 1;
      _updateDropSpeed();

      // Ataque base por líneas
      if (cleared == 4) { attackLines = 4; energyGain = 2; }
      else if (cleared == 3) { attackLines = 2; energyGain = 1; }
      else if (cleared == 2) { attackLines = 1; }

      // Bonificación devastadora de The New Tetris: romper filas de cubos Oro/Plata
      if (goldLines > 0) {
        attackLines += (goldLines ~/ 4) * 8; // +8 líneas por cada segmento de Monocubo Oro
        energyGain += 2;
      }
      if (silverLines > 0) {
        attackLines += (silverLines ~/ 4) * 4; // +4 líneas por cada segmento de Multicubo Plata
        energyGain += 1;
      }

      // Combo bonus
      if (combo > 1) attackLines += min(combo ~/ 2, 4);

      // Multiplicador 2v2 Wide Co-op
      if (mode == GameMode.coop2v2Wide && cleared >= 2) attackLines *= 2;

      linesSent += attackLines;
      addDefenseEnergy(energyGain);
    } else {
      combo = 0;
    }

    return AttackResult(
      linesCleared: cleared,
      linesSent: attackLines,
      energyGained: energyGain,
      goldCubeLines: goldLines,
      silverCubeLines: silverLines,
    );
  }

  void addDefenseEnergy(int pts) {
    if (isShieldActive || pts <= 0) return;
    defenseEnergy = min(5, defenseEnergy + pts);
  }

  bool activateShield() {
    if (defenseEnergy < 5 || isShieldActive) return false;
    defenseEnergy = 0;
    isShieldActive = true;
    shieldSecondsRemaining = 20;
    return true;
  }

  void updateShieldTimer() {
    if (!isShieldActive) return;
    shieldSecondsRemaining--;
    if (shieldSecondsRemaining <= 0) {
      isShieldActive = false;
      shieldSecondsRemaining = 0;
    }
  }

  void receiveGarbage(int count, [CubeType cubeType = CubeType.none]) {
    if (isShieldActive) return;
    for (int i = 0; i < count; i++) {
      grid.removeAt(0);
      final row = List<Cell?>.generate(cols, (_) => null);
      final hole = _rng.nextInt(cols);
      for (int x = 0; x < cols; x++) {
        if (x != hole) {
          row[x] = Cell(type: TetrominoType.GARBAGE, cubeType: cubeType, pieceId: 0);
        }
      }
      grid.add(row);
    }
  }

  Position getGhostPosition() {
    if (currentPiece == null) return Position(0, 0);
    int ghostY = currentPiece!.position.y;
    while (!checkCollision(currentPiece!, currentPiece!.position.x, ghostY + 1)) ghostY++;
    return Position(currentPiece!.position.x, ghostY);
  }

  double getRenderY() {
    if (currentPiece == null) return 0.0;
    final ghost = getGhostPosition();
    final smooth = currentPiece!.position.y.toDouble() + fallProgress;
    return min(smooth, ghost.y.toDouble());
  }
}
