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

  int score = 0;
  int hiScore = 0;
  int linesCleared = 0;
  int linesSent = 0;
  int combo = 0;
  double comboTimer = 0.0;
  static const double comboGraceTime = 3.0; // 3 segundos de gracia para combos
  int level = 1;
  bool isGameOver = false;
  bool isPaused = false;
  int specialAttackCharges = 2;

  // Sistema de 4 Barras de Ataques Especiales (Cargadas con TETRIS)
  int specialChargeBars = 0; // 0 a 4 barras
  double invertedRotationTimer = 0.0; // Barra 1: Giro invertido (20s)
  double invisibleFlickerTimer = 0.0;  // Barra 2: Fichas invisibles titilantes (20s)
  double speedMultiplierTimer = 0.0;  // Barra 3: Caída x4 velocidad (20s)

  // Sistema de Combate y Salud (100 HP)
  int maxHp = 100;
  int currentHp = 100;

  void takeDamage(int damage) {
    if (isShieldActive || damage <= 0) return;
    currentHp = max(0, currentHp - damage);
    if (currentHp <= 0) {
      isGameOver = true;
    }
  }

  int healHp(int amount) {
    if (amount <= 0 || currentHp >= maxHp) return 0;
    final prev = currentHp;
    currentHp = min(maxHp, currentHp + amount);
    return currentHp - prev;
  }

  void receiveDiamondGarbage(int count) {
    if (isShieldActive || count <= 0) return;
    for (int i = 0; i < count; i++) {
      grid.removeAt(0);
      final row = List<Cell?>.generate(cols, (_) => null);
      final hole = _rng.nextInt(cols);
      for (int x = 0; x < cols; x++) {
        if (x != hole) {
          row[x] = Cell(type: TetrominoType.GARBAGE, cubeType: CubeType.diamond, pieceId: 0);
        }
      }
      grid.add(row);
    }
  }

  /// Barra 4: Lluvia de estrellas fijas aleatorias sobre la grilla visible
  void receiveStarShower([int count = 10]) {
    if (isShieldActive || isGameOver) return;
    final startRow = max(0, rows - 16);
    int placed = 0;
    for (int attempt = 0; attempt < 100 && placed < count; attempt++) {
      final r = startRow + _rng.nextInt(rows - startRow);
      final c = _rng.nextInt(cols);
      if (grid[r][c] == null) {
        grid[r][c] = Cell(
          type: TetrominoType.GARBAGE,
          cubeType: CubeType.star,
          pieceId: 0,
        );
        placed++;
      }
    }
  }

  /// Calcula la altura del apilado en las 20 filas visibles (0 a 20)
  int getStackHeight() {
    final visibleStart = max(0, rows - 20);
    for (int y = visibleStart; y < rows; y++) {
      if (grid[y].any((c) => c != null)) {
        return rows - y;
      }
    }
    return 0;
  }

  /// Matriz compacta 20x10 para el minimapa del rival en tiempo real
  List<List<int>> getCompactVisibleMatrix() {
    final visibleStart = max(0, rows - 20);
    final List<List<int>> res = [];
    for (int y = visibleStart; y < rows; y++) {
      final row = <int>[];
      for (int x = 0; x < cols; x++) {
        final cell = grid[y][x];
        if (cell == null) {
          row.add(0);
        } else if (cell.cubeType == CubeType.star) {
          row.add(2); // Estrella
        } else {
          row.add(1); // Bloque normal o basura
        }
      }
      res.add(row);
    }
    return res;
  }

  // Caída fluida continua a 60 FPS
  double fallProgress = 0.0;
  double dropSpeed = 1.0;

  // 1. Lock Delay oficial (500ms al tocar superficie + Move Reset)
  double lockDelayTimer = 0.0;
  static const double lockDelayDuration = 0.5; // 500ms
  int lockResetsRemaining = 15;
  bool isTouchingSurface = false;

  // 2. Detección oficial de T-Spins (Regla de las 3 esquinas)
  bool lastActionWasRotate = false;
  bool lastMoveWasTSpin = false;

  // 3. Mitigación de Basura (Garbage Cancelling / Buffer de daño)
  int pendingGarbageLines = 0;

  // 4. Estado de Cascada y Caída Libre (0.5s suspendida + deslizamiento suave)
  bool isCascading = false;
  double cascadeSuspendedTimer = 0.0;
  double cascadeSlideProgress = 0.0;
  Map<String, int> cascadeDropDistances = {};

  // Escudo / Inmunidad Especial (Estilo Zone de Tetris Effect)
  int defenseEnergy = 0; // 0 a 5
  bool isShieldActive = false;
  int shieldSecondsRemaining = 0;
  final Random _rng = Random();

  TetrisEngine({
    this.cols = 10,
    this.rows = 40, // Matriz 10x40 oficial: 20 superiores Vanish Zone, 20 inferiores visibles
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
    score = 0;
    linesCleared = 0;
    linesSent = 0;
    combo = 0;
    comboTimer = 0.0;
    level = 1;
    isGameOver = false;
    isPaused = false;
    defenseEnergy = 0;
    isShieldActive = false;
    currentHp = maxHp;
    shieldSecondsRemaining = 0;
    specialChargeBars = 0;
    invertedRotationTimer = 0.0;
    invisibleFlickerTimer = 0.0;
    speedMultiplierTimer = 0.0;
    fallProgress = 0.0;
    lockDelayTimer = 0.0;
    lockResetsRemaining = 15;
    isTouchingSurface = false;
    lastActionWasRotate = false;
    lastMoveWasTSpin = false;
    pendingGarbageLines = 0;
    isCascading = false;
    cascadeSuspendedTimer = 0.0;
    cascadeSlideProgress = 0.0;
    cascadeDropDistances.clear();
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

  /// Spawnea la pieza en la Vanish Zone (Fila 18, justo encima de la matriz visible)
  bool spawnPiece() {
    while (nextQueue.length < 4) nextQueue.add(_getNextType());
    final nextType = nextQueue.removeAt(0);
    final startX = (cols ~/ 2) - 2;
    // Fila 18 para matrices de 40 filas (Vanish Zone), o fila 0 para matrices estándar
    final startY = rows >= 40 ? 18 : 0;
    final piece = PieceState(type: nextType, rotation: 0, position: Position(startX, startY));

    if (checkCollision(piece, piece.position.x, piece.position.y)) {
      if (mode == GameMode.duel1v1) {
        // Penalización de 25 HP al tocar techo en 1v1 y despeje de emergencia de 4 filas
        // para evitar muerte súbita y permitir remontada táctica
        takeDamage(25);
        if (currentHp <= 0) {
          isGameOver = true;
          currentPiece = null;
          return false;
        }
        for (int y = 0; y < min(4, rows); y++) {
          for (int x = 0; x < cols; x++) {
            grid[y][x] = null;
          }
        }
        if (checkCollision(piece, piece.position.x, piece.position.y)) {
          isGameOver = true;
          currentPiece = null;
          return false;
        }
      } else {
        isGameOver = true;
        currentPiece = null;
        return false;
      }
    }
    currentPiece = piece;
    canHold = true;
    fallProgress = 0.0;
    lockDelayTimer = 0.0;
    lockResetsRemaining = 15;
    isTouchingSurface = false;
    lastActionWasRotate = false;
    lastMoveWasTSpin = false;
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

  /// Actualización del motor a 60 FPS con Lock Delay de 500ms y Animación de Cascada
  AttackResult? update(double dt) {
    if (isGameOver || isPaused) return null;

    // 1. Temporizador de Gracia de 3 Segundos para Combos y Efectos Especiales
    if (comboTimer > 0.0) {
      comboTimer -= dt;
      if (comboTimer <= 0.0) {
        combo = 0;
        comboTimer = 0.0;
      }
    }

    if (invertedRotationTimer > 0.0) {
      invertedRotationTimer = max(0.0, invertedRotationTimer - dt);
    }
    if (invisibleFlickerTimer > 0.0) {
      invisibleFlickerTimer = max(0.0, invisibleFlickerTimer - dt);
    }
    if (speedMultiplierTimer > 0.0) {
      speedMultiplierTimer = max(0.0, speedMultiplierTimer - dt);
    }

    // 2. Animación de Cascada / Caída Libre (0.5s suspendida + deslizamiento suave)
    if (isCascading) {
      if (cascadeSuspendedTimer > 0.0) {
        cascadeSuspendedTimer -= dt;
      } else {
        cascadeSlideProgress += dt * 3.5; // ~0.28s deslizándose hacia abajo
        if (cascadeSlideProgress >= 1.0) {
          cascadeSlideProgress = 1.0;
          applyGravityCascade();
          cascadeDropDistances.clear();

          // Evaluar si al caer se formó otra línea en cadena
          final subResult = checkAndClearCascadeLines();
          if (subResult.linesCleared > 0) {
            return subResult;
          } else {
            isCascading = false;
            // Aplicar basura pendiente acumulada tras estabilizarse la cascada
            _applyPendingGarbage();
            spawnPiece();
          }
        }
      }
      return null;
    }

    if (currentPiece == null) return null;

    // 3. Comprobación de Lock Delay cuando la pieza toca una superficie
    final bool onGround = checkCollision(currentPiece!, currentPiece!.position.x, currentPiece!.position.y + 1);

    if (onGround) {
      if (!isTouchingSurface) {
        isTouchingSurface = true;
        lockDelayTimer = lockDelayDuration; // Inicia los 500ms de margen
      } else {
        lockDelayTimer -= dt;
        if (lockDelayTimer <= 0.0) {
          lockDelayTimer = 0.0;
          isTouchingSurface = false;
          return lockPiece(); // Se cumplieron los 500ms sin mover -> se bloquea
        }
      }
    } else {
      isTouchingSurface = false;
      lockDelayTimer = 0.0;

      // Caída normal por gravedad (x4 si está activo el ataque especial)
      final effectiveDropSpeed = speedMultiplierTimer > 0.0 ? dropSpeed * 4.0 : dropSpeed;
      fallProgress += effectiveDropSpeed * dt;
      if (fallProgress >= 1.0) {
        final rowsToFall = fallProgress.floor();
        fallProgress -= rowsToFall;

        for (int i = 0; i < rowsToFall; i++) {
          if (!checkCollision(currentPiece!, currentPiece!.position.x, currentPiece!.position.y + 1)) {
            currentPiece!.position.y++;
          } else {
            fallProgress = 0.0;
            isTouchingSurface = true;
            lockDelayTimer = lockDelayDuration;
            break;
          }
        }
      }
    }

    return null;
  }

  void _onMoveOrRotateAction() {
    lastActionWasRotate = false;
    // Move Reset Rule: si está en el suelo y quedan reajustes, reinicia los 500ms
    if (isTouchingSurface && lockResetsRemaining > 0) {
      lockResetsRemaining--;
      lockDelayTimer = lockDelayDuration;
    }
  }

  bool moveLeft() {
    if (currentPiece == null || isGameOver || isPaused || isCascading) return false;
    if (!checkCollision(currentPiece!, currentPiece!.position.x - 1, currentPiece!.position.y)) {
      currentPiece!.position.x--;
      _onMoveOrRotateAction();
      return true;
    }
    return false;
  }

  bool moveRight() {
    if (currentPiece == null || isGameOver || isPaused || isCascading) return false;
    if (!checkCollision(currentPiece!, currentPiece!.position.x + 1, currentPiece!.position.y)) {
      currentPiece!.position.x++;
      _onMoveOrRotateAction();
      return true;
    }
    return false;
  }

  bool softDrop() {
    if (currentPiece == null || isGameOver || isPaused || isCascading) return false;
    if (!checkCollision(currentPiece!, currentPiece!.position.x, currentPiece!.position.y + 1)) {
      currentPiece!.position.y++;
      score += 1;
      _onMoveOrRotateAction();
      return true;
    } else {
      if (!isTouchingSurface) {
        isTouchingSurface = true;
        lockDelayTimer = lockDelayDuration;
      }
    }
    return false;
  }

  /// Rotación oficial Super Rotation System (SRS) con tabla completa de 5 Wall Kicks
  bool rotate(int dir) {
    if (currentPiece == null || isGameOver || isPaused || isCascading) return false;
    if (currentPiece!.type == TetrominoType.O) return true; // Pieza O no rota

    // Barra 1: Invertir sentido de giro si el ataque está activo
    final effectiveDir = invertedRotationTimer > 0.0 ? -dir : dir;
    final fromRot = currentPiece!.rotation;
    final toRot = (fromRot + effectiveDir) % 4 < 0 ? (fromRot + effectiveDir) % 4 + 4 : (fromRot + effectiveDir) % 4;

    final kicks = _getSrsKicks(currentPiece!.type, fromRot, toRot);

    for (final offset in kicks) {
      // Regla estricta: Una ficha en movimiento jamás puede trepar o saltar hacia arriba (offset[1] < 0).
      // Solo puede moverse hacia los costados o hacia abajo, nunca pasar por encima de bloques que ya pasó de largo.
      if (offset[1] < 0) continue;

      final testX = currentPiece!.position.x + offset[0];
      final testY = currentPiece!.position.y + offset[1];

      if (!checkCollision(currentPiece!, testX, testY, toRot)) {
        currentPiece!.position.x = testX;
        currentPiece!.position.y = testY;
        currentPiece!.rotation = toRot;
        lastActionWasRotate = true;

        if (isTouchingSurface && lockResetsRemaining > 0) {
          lockResetsRemaining--;
          lockDelayTimer = lockDelayDuration;
        }
        return true;
      }
    }

    return false;
  }

  /// Tabla oficial SRS de Wall Kicks (Tetris Guideline)
  List<List<int>> _getSrsKicks(TetrominoType type, int from, int to) {
    final key = '${from}_$to';

    if (type == TetrominoType.I) {
      const Map<String, List<List<int>>> srsKicksI = {
        '0_1': [[0, 0], [-2, 0], [1, 0], [-2, 1], [1, -2]],
        '1_0': [[0, 0], [2, 0], [-1, 0], [2, -1], [-1, 2]],
        '1_2': [[0, 0], [-1, 0], [2, 0], [-1, -2], [2, 1]],
        '2_1': [[0, 0], [1, 0], [-2, 0], [1, 2], [-2, -1]],
        '2_3': [[0, 0], [2, 0], [-1, 0], [2, -1], [-1, 2]],
        '3_2': [[0, 0], [-2, 0], [1, 0], [-2, 1], [1, -2]],
        '3_0': [[0, 0], [1, 0], [-2, 0], [1, 2], [-2, -1]],
        '0_3': [[0, 0], [-1, 0], [2, 0], [-1, -2], [2, 1]],
      };
      return srsKicksI[key] ?? [[0, 0]];
    } else {
      const Map<String, List<List<int>>> srsKicksJlstz = {
        '0_1': [[0, 0], [-1, 0], [-1, -1], [0, 2], [-1, 2]],
        '1_0': [[0, 0], [1, 0], [1, 1], [0, -2], [1, -2]],
        '1_2': [[0, 0], [1, 0], [1, 1], [0, -2], [1, -2]],
        '2_1': [[0, 0], [-1, 0], [-1, -1], [0, 2], [-1, 2]],
        '2_3': [[0, 0], [1, 0], [1, -1], [0, 2], [1, 2]],
        '3_2': [[0, 0], [-1, 0], [-1, 1], [0, -2], [-1, -2]],
        '3_0': [[0, 0], [-1, 0], [-1, 1], [0, -2], [-1, -2]],
        '0_3': [[0, 0], [1, 0], [1, -1], [0, 2], [1, 2]],
      };
      return srsKicksJlstz[key] ?? [[0, 0]];
    }
  }

  /// Detección oficial de T-Spin según la regla de las 3 esquinas
  bool checkTSpin(PieceState piece) {
    if (piece.type != TetrominoType.T || !lastActionWasRotate) return false;

    final cx = piece.position.x + 1;
    final cy = piece.position.y + 1;

    final corners = [
      [cx - 1, cy - 1], // Top-Left
      [cx + 1, cy - 1], // Top-Right
      [cx - 1, cy + 1], // Bottom-Left
      [cx + 1, cy + 1], // Bottom-Right
    ];

    int occupiedCount = 0;
    for (final c in corners) {
      final x = c[0];
      final y = c[1];
      if (x < 0 || x >= cols || y >= rows) {
        occupiedCount++;
      } else if (y >= 0 && grid[y][x] != null) {
        occupiedCount++;
      }
    }

    return occupiedCount >= 3;
  }

  AttackResult hardDrop() {
    if (currentPiece == null || isGameOver || isPaused || isCascading) {
      return AttackResult(linesCleared: 0, linesSent: 0, energyGained: 0);
    }
    int dropDistance = 0;
    while (!checkCollision(currentPiece!, currentPiece!.position.x, currentPiece!.position.y + 1)) {
      currentPiece!.position.y += 1;
      dropDistance++;
    }
    score += dropDistance * 2;
    if (score > hiScore) hiScore = score;

    lockDelayTimer = 0.0;
    isTouchingSurface = false;
    return lockPiece();
  }

  bool hold() {
    if (currentPiece == null || !canHold || isGameOver || isPaused || isCascading) return false;
    final currentType = currentPiece!.type;
    if (holdPiece == null) {
      holdPiece = currentType;
      spawnPiece();
    } else {
      final temp = holdPiece!;
      holdPiece = currentType;
      final startX = (cols ~/ 2) - 2;
      final startY = rows >= 40 ? 18 : 0;
      currentPiece = PieceState(type: temp, rotation: 0, position: Position(startX, startY));
    }
    canHold = false;
    fallProgress = 0.0;
    lockDelayTimer = 0.0;
    isTouchingSurface = false;
    return true;
  }

  AttackResult lockPiece() {
    if (currentPiece == null) return AttackResult(linesCleared: 0, linesSent: 0, energyGained: 0);

    // Verificar T-Spin antes de clavar la pieza
    lastMoveWasTSpin = checkTSpin(currentPiece!);

    final pieceId = _pieceCounter++;
    final shape = tetrominoShapes[currentPiece!.type]![currentPiece!.rotation];
    for (int r = 0; r < shape.length; r++) {
      for (int c = 0; c < shape[r].length; c++) {
        if (shape[r][c] != 0) {
          final px = currentPiece!.position.x + c;
          final py = currentPiece!.position.y + r;
          if (py >= 0 && py < rows && px >= 0 && px < cols) {
            grid[py][px] = Cell(type: currentPiece!.type, cubeType: CubeType.none, pieceId: pieceId);
          }
        }
      }
    }
    currentPiece = null;

    // Detectar si se formó un Cubo Dorado (Monocube) o Plateado (Multicube) 4x4
    detectNewTetrisCubes();

    final result = clearLines();

    if (!isCascading) {
      _applyPendingGarbage();
      spawnPiece();
    }

    return result;
  }

  void _applyPendingGarbage() {
    if (isShieldActive || pendingGarbageLines <= 0) return;
    final count = pendingGarbageLines;
    pendingGarbageLines = 0;

    for (int i = 0; i < count; i++) {
      grid.removeAt(0);
      final row = List<Cell?>.generate(cols, (_) => null);
      final hole = _rng.nextInt(cols);
      for (int x = 0; x < cols; x++) {
        if (x != hole) {
          row[x] = Cell(type: TetrominoType.GARBAGE, cubeType: CubeType.none, pieceId: 0);
        }
      }
      grid.add(row);
    }
  }

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

        if (isFullSquare && !alreadyFormed && pieceIds.length == 4) {
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

  Map<String, int> computeDropDistances() {
    final Map<String, int> distances = {};
    for (int x = 0; x < cols; x++) {
      int emptyCount = 0;
      for (int y = rows - 1; y >= 0; y--) {
        if (grid[y][x] == null) {
          emptyCount++;
        } else {
          if (emptyCount > 0) {
            distances['${x}_${y}'] = emptyCount;
          }
        }
      }
    }
    return distances;
  }

  bool applyGravityCascade() {
    bool movedAny = false;
    for (int x = 0; x < cols; x++) {
      int writeY = rows - 1;
      for (int y = rows - 1; y >= 0; y--) {
        if (grid[y][x] != null) {
          if (y != writeY) {
            grid[writeY][x] = grid[y][x];
            grid[y][x] = null;
            movedAny = true;
          }
          writeY--;
        }
      }
    }
    return movedAny;
  }

  AttackResult checkAndClearCascadeLines() {
    int cleared = 0;
    int goldLines = 0;
    int silverLines = 0;

    for (int y = rows - 1; y >= 0; y--) {
      if (grid[y].every((cell) => cell != null)) {
        cleared++;
        for (int x = 0; x < cols; x++) {
          final cell = grid[y][x]!;
          if (cell.cubeType == CubeType.gold) goldLines++;
          if (cell.cubeType == CubeType.silver) silverLines++;
        }
        grid.removeAt(y);
        grid.insert(0, List<Cell?>.generate(cols, (_) => null));
        y++;
      }
    }

    if (cleared > 0) {
      linesCleared += cleared;
      combo++;
      comboTimer = comboGraceTime;
      level = (linesCleared ~/ 10) + 1;
      _updateDropSpeed();

      int lineScore = (cleared >= 4 ? 800 : (cleared == 3 ? 500 : (cleared == 2 ? 300 : 100))) * level;
      lineScore += 350 * combo * level;
      score += lineScore;
      if (score > hiScore) hiScore = score;

      final distances = computeDropDistances();
      if (distances.isNotEmpty) {
        isCascading = true;
        cascadeSuspendedTimer = 0.5; // 0.5s suspendidas en el aire
        cascadeSlideProgress = 0.0;
        cascadeDropDistances = distances;
      } else {
        isCascading = false;
        _applyPendingGarbage();
        spawnPiece();
      }

      int hpHealed = 0;
      if (combo >= 6) {
        hpHealed = healHp(50);
      } else if (combo == 5) {
        hpHealed = healHp(20);
      } else if (combo >= 3) {
        hpHealed = healHp(5);
      }

      int damageHp = 0;
      int diamondLines = 0;
      if (cleared >= 4) {
        specialChargeBars = min(4, specialChargeBars + 1);
        damageHp = 10;
        if (goldLines > 0) diamondLines += 2;
        if (silverLines > 0) diamondLines += 1;
      } else if (cleared == 3) {
        damageHp = 7;
      } else if (cleared == 2) {
        damageHp = 4;
      } else if (cleared == 1) {
        damageHp = 2;
      }

      return AttackResult(
        linesCleared: cleared,
        linesSent: cleared,
        energyGained: 1,
        goldCubeLines: goldLines,
        silverCubeLines: silverLines,
        damageHp: damageHp,
        diamondLines: diamondLines,
        hpHealed: hpHealed,
      );
    }

    isCascading = false;
    return AttackResult(linesCleared: 0, linesSent: 0, energyGained: 0);
  }

  /// Limpieza de líneas con Cascada, T-Spins, y Mitigación de Basura
  AttackResult clearLines() {
    int totalCleared = 0;
    int totalGoldLines = 0;
    int totalSilverLines = 0;
    int cascadeRounds = 0;

    bool hadLinesInPass = true;
    while (hadLinesInPass) {
      hadLinesInPass = false;
      int clearedInPass = 0;

      for (int y = rows - 1; y >= 0; y--) {
        if (grid[y].every((cell) => cell != null)) {
          clearedInPass++;
          for (int x = 0; x < cols; x++) {
            final cell = grid[y][x]!;
            if (cell.cubeType == CubeType.gold) totalGoldLines++;
            if (cell.cubeType == CubeType.silver) totalSilverLines++;
          }
          grid.removeAt(y);
          grid.insert(0, List<Cell?>.generate(cols, (_) => null));
          y++;
        }
      }

      if (clearedInPass > 0) {
        hadLinesInPass = true;
        totalCleared += clearedInPass;
        cascadeRounds++;

        final distances = computeDropDistances();
        if (distances.isNotEmpty) {
          isCascading = true;
          cascadeSuspendedTimer = 0.5; // 0.5s suspendidas en el aire
          cascadeSlideProgress = 0.0;
          cascadeDropDistances = distances;
          break;
        } else {
          applyGravityCascade();
        }
      }
    }

    int attackLines = 0;
    int energyGain = 0;

    if (totalCleared > 0 || lastMoveWasTSpin) {
      linesCleared += totalCleared;
      if (totalCleared > 0) {
        combo++;
        comboTimer = comboGraceTime;
      }
      level = (linesCleared ~/ 10) + 1;
      _updateDropSpeed();

      int lineScore = 0;

      // Detección y Bonificación de T-Spin oficial
      if (lastMoveWasTSpin) {
        if (totalCleared == 3) {
          attackLines = 6;
          energyGain = 3;
          lineScore = 1600 * level;
        } else if (totalCleared == 2) {
          attackLines = 4;
          energyGain = 2;
          lineScore = 1200 * level;
        } else if (totalCleared == 1) {
          attackLines = 2;
          energyGain = 1;
          lineScore = 800 * level;
        } else {
          energyGain = 1;
          lineScore = 400 * level;
        }
      } else {
        if (totalCleared >= 4) {
          specialChargeBars = min(4, specialChargeBars + 1);
          attackLines = 4;
          energyGain = 2;
          lineScore = 800 * level;
        }
        else if (totalCleared == 3) { attackLines = 2; energyGain = 1; lineScore = 500 * level; }
        else if (totalCleared == 2) { attackLines = 1; lineScore = 300 * level; }
        else if (totalCleared == 1) { attackLines = 0; lineScore = 100 * level; }
      }

      if (cascadeRounds > 1) {
        lineScore += (cascadeRounds - 1) * 250 * level;
      }

      if (totalGoldLines > 0) {
        final segments = (totalGoldLines ~/ 4);
        attackLines += segments * 8;
        lineScore += segments * 2500;
        energyGain += 2;
      }
      if (totalSilverLines > 0) {
        final segments = (totalSilverLines ~/ 4);
        attackLines += segments * 4;
        lineScore += segments * 1000;
        energyGain += 1;
      }

      if (combo > 1) {
        attackLines += min(combo ~/ 2, 4);
        lineScore += (50 * combo * level);
      }

      if (mode == GameMode.coop2v2Wide && totalCleared >= 2) attackLines *= 2;

      // MITIGACIÓN DE BASURA (Garbage Cancelling)
      int effectiveAttack = attackLines;
      if (pendingGarbageLines > 0) {
        if (effectiveAttack >= pendingGarbageLines) {
          effectiveAttack -= pendingGarbageLines;
          pendingGarbageLines = 0;
        } else {
          pendingGarbageLines -= effectiveAttack;
          effectiveAttack = 0;
        }
      }

      score += lineScore;
      if (score > hiScore) hiScore = score;

      linesSent += effectiveAttack;
      addDefenseEnergy(energyGain);
      attackLines = effectiveAttack;
    }

    int hpHealed = 0;
    if (combo >= 6) {
      hpHealed = healHp(50);
    } else if (combo == 5) {
      hpHealed = healHp(20);
    } else if (combo >= 3) {
      hpHealed = healHp(5);
    }

    int damageHp = 0;
    int diamondLines = 0;
    if (totalCleared >= 4) {
      // Regla 2: Cada ataque TETRIS enemigo quita 10 de vida
      damageHp = 10;
      if (totalGoldLines > 0) {
        // Cubo dorado adiciona 2 líneas diamantadas
        diamondLines += 2;
      }
      if (totalSilverLines > 0) {
        // Cubo plateado adiciona 1 línea diamantada
        diamondLines += 1;
      }
    } else if (lastMoveWasTSpin) {
      if (totalCleared == 3) damageHp = 15;
      else if (totalCleared == 2) damageHp = 10;
      else if (totalCleared == 1) damageHp = 5;
      else damageHp = 3;
    } else if (totalCleared == 3) {
      damageHp = 7;
    } else if (totalCleared == 2) {
      damageHp = 4;
    } else if (totalCleared == 1) {
      damageHp = 2;
    }

    return AttackResult(
      linesCleared: totalCleared,
      linesSent: attackLines,
      energyGained: energyGain,
      goldCubeLines: totalGoldLines,
      silverCubeLines: totalSilverLines,
      damageHp: damageHp,
      diamondLines: diamondLines,
      hpHealed: hpHealed,
    );
  }

  void addDefenseEnergy(int pts) {
    if (isShieldActive || pts <= 0) return;
    defenseEnergy = min(5, defenseEnergy + pts);
  }

  bool activateShield([int seconds = 20]) {
    if (defenseEnergy >= 5 && !isShieldActive) {
      isShieldActive = true;
      defenseEnergy = 0;
      shieldSecondsRemaining = seconds;
      pendingGarbageLines = 0; // Cancela basura en cola
      return true;
    }
    return false;
  }

  void updateShieldTimer() => tickShield();

  void tickShield() {
    if (isShieldActive) {
      shieldSecondsRemaining--;
      if (shieldSecondsRemaining <= 0) {
        isShieldActive = false;
        shieldSecondsRemaining = 0;
      }
    }
  }

  /// Mitigación: La basura entrante primero se encola en pendingGarbageLines
  void receiveGarbage(int count, [CubeType cubeType = CubeType.none]) {
    if (isShieldActive || count <= 0) return;
    pendingGarbageLines += count;
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
