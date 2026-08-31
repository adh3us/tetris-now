import 'package:flutter_test/flutter_test.dart';
import '../lib/game/tetris_engine.dart';
import '../lib/game/tetris_types.dart';

void main() {
  group('TetrisEngine - Inicialización y Bag', () {
    test('El tablero inicia vacío (10x20) y con estado correcto', () {
      final engine = TetrisEngine();
      expect(TetrisEngine.cols, 10);
      expect(TetrisEngine.rows, 20);
      expect(engine.linesCleared, 0);
      expect(engine.linesSent, 0);
      expect(engine.isGameOver, false);
      expect(engine.currentPiece, isNotNull);
    });

    test('Random 7-Bag genera secuencias balanceadas', () {
      final engine = TetrisEngine();
      final seenTypes = <TetrominoType>{};
      for (int i = 0; i < 7; i++) {
        seenTypes.add(engine.currentPiece!.type);
        engine.hardDrop();
      }
      expect(seenTypes.length, 7);
    });
  });

  group('TetrisEngine - Movimientos y Colisiones', () {
    test('Movimiento lateral respeta límites del tablero', () {
      final engine = TetrisEngine();
      for (int i = 0; i < 10; i++) {
        engine.moveLeft();
      }
      final minX = engine.currentPiece!.position.x;
      expect(engine.moveLeft(), false);
      expect(engine.currentPiece!.position.x, minX);

      for (int i = 0; i < 15; i++) {
        engine.moveRight();
      }
      final maxX = engine.currentPiece!.position.x;
      expect(engine.moveRight(), false);
      expect(engine.currentPiece!.position.x, maxX);
    });

    test('Hard drop fija la pieza en el fondo inmediatamente', () {
      final engine = TetrisEngine();
      final result = engine.hardDrop();
      
      expect(result, isNotNull);
      expect(engine.currentPiece, isNotNull);
      expect(engine.canHold, true);
    });
  });

  group('TetrisEngine - Sistema de Hold', () {
    test('Hold reserva la pieza actual y saca la siguiente', () {
      final engine = TetrisEngine();
      final firstType = engine.currentPiece!.type;
      
      expect(engine.hold(), true);
      expect(engine.holdPiece, firstType);
      expect(engine.canHold, false);

      expect(engine.hold(), false);
    });

    test('Bloquear pieza reinicia la capacidad de Hold', () {
      final engine = TetrisEngine();
      engine.hold();
      expect(engine.canHold, false);
      
      engine.hardDrop();
      expect(engine.canHold, true);
    });
  });

  group('TetrisEngine - Mega Estructuras (Oro y Plata)', () {
    test('Detecta Mega Bloque de Oro al juntar 4x4 piezas iguales', () {
      final engine = TetrisEngine();
      for (int y = 16; y < 20; y++) {
        for (int x = 0; x < 4; x++) {
          engine.grid[y][x] = Cell(type: TetrominoType.O, armor: 0, tier: ArmorTier.none);
        }
      }

      engine.detectMegaStructures();

      for (int y = 16; y < 20; y++) {
        for (int x = 0; x < 4; x++) {
          expect(engine.grid[y][x]!.tier, ArmorTier.gold);
          expect(engine.grid[y][x]!.armor, 3);
        }
      }
    });

    test('Detecta Mega Bloque de Plata al juntar 4x4 piezas mixtas', () {
      final engine = TetrisEngine();
      for (int y = 16; y < 20; y++) {
        for (int x = 0; x < 4; x++) {
          final type = (x < 2) ? TetrominoType.I : TetrominoType.O;
          engine.grid[y][x] = Cell(type: type, armor: 0, tier: ArmorTier.none);
        }
      }

      engine.detectMegaStructures();

      for (int y = 16; y < 20; y++) {
        for (int x = 0; x < 4; x++) {
          expect(engine.grid[y][x]!.tier, ArmorTier.silver);
          expect(engine.grid[y][x]!.armor, 1);
        }
      }
    });
  });

  group('TetrisEngine - Escudo de Defensa e Invulnerabilidad', () {
    test('Carga de energía con Triples (+1) y Tetris (+2) hasta tope de 5', () {
      final engine = TetrisEngine();
      expect(engine.defenseEnergy, 0);

      engine.addDefenseEnergy(1);
      expect(engine.defenseEnergy, 1);

      engine.addDefenseEnergy(2);
      expect(engine.defenseEnergy, 3);

      engine.addDefenseEnergy(4);
      expect(engine.defenseEnergy, 5);
    });

    test('Activación de Escudo otorga 20 segundos de inmunidad y bloquea basura', () {
      final engine = TetrisEngine();
      engine.defenseEnergy = 5;

      expect(engine.activateShield(), true);
      expect(engine.isShieldActive, true);
      expect(engine.shieldSecondsRemaining, 20);
      expect(engine.defenseEnergy, 0);

      final initialGridState = engine.grid[19].every((c) => c == null);
      engine.receiveGarbage(4);
      expect(engine.grid[19].every((c) => c == null), initialGridState);

      for (int i = 0; i < 20; i++) {
        engine.updateShieldTimer();
      }
      expect(engine.isShieldActive, false);
      expect(engine.shieldSecondsRemaining, 0);
    });

    test('Recepción de basura normal cuando no hay escudo', () {
      final engine = TetrisEngine();
      expect(engine.isShieldActive, false);

      engine.receiveGarbage(2);
      final lastRowHasGarbage = engine.grid[19].any((c) => c?.type == TetrominoType.GARBAGE);
      expect(lastRowHasGarbage, true);
    });
  });

  group('TetrisEngine - Sombra de Caída (Ghost Piece)', () {
    test('Ghost position calcula correctamente la posición de impacto', () {
      final engine = TetrisEngine();
      final ghostPos = engine.getGhostPosition();

      expect(ghostPos.x, engine.currentPiece!.position.x);
      expect(ghostPos.y, greaterThanOrEqualTo(engine.currentPiece!.position.y));
    });
  });
}
