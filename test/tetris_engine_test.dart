import 'package:flutter_test/flutter_test.dart';
import '../lib/game/tetris_engine.dart';
import '../lib/game/tetris_types.dart';

void main() {
  group('TetrisEngine - Inicialización y Bag', () {
    test('El tablero inicia vacío (10x40 con Vanish Zone) y con estado correcto', () {
      final engine = TetrisEngine();
      expect(engine.cols, 10);
      expect(engine.rows, 40);
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

  group('TetrisEngine - Sistema de Combate (HP)', () {
    test('takeDamage reduce HP y activa Game Over al llegar a 0', () {
      final engine = TetrisEngine();
      expect(engine.currentHp, 100);

      engine.takeDamage(40);
      expect(engine.currentHp, 60);
      expect(engine.isGameOver, false);

      engine.takeDamage(100);
      expect(engine.currentHp, 0);
      expect(engine.isGameOver, true);
    });

    test('healHp no supera el máximo de 100', () {
      final engine = TetrisEngine();
      engine.takeDamage(30);
      expect(engine.currentHp, 70);

      final healed = engine.healHp(50);
      expect(healed, 30);
      expect(engine.currentHp, 100);
    });

    test('Escudo activo bloquea el daño', () {
      final engine = TetrisEngine();
      engine.defenseEnergy = 5;
      expect(engine.activateShield(), true);
      expect(engine.isShieldActive, true);

      engine.takeDamage(50);
      expect(engine.currentHp, 100);
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

    test('Activación de Escudo otorga inmunidad y bloquea basura', () {
      final engine = TetrisEngine();
      engine.defenseEnergy = 5;

      expect(engine.activateShield(), true);
      expect(engine.isShieldActive, true);
      expect(engine.defenseEnergy, 0);

      // receiveGarbage encola las líneas en pendingGarbageLines (se vuelcan
      // al grid recién al bloquear la pieza actual); con escudo activo no
      // debe ni siquiera encolarlas.
      engine.receiveGarbage(4);
      expect(engine.pendingGarbageLines, 0);

      for (int i = 0; i < 25; i++) {
        engine.updateShieldTimer();
      }
      expect(engine.isShieldActive, false);
    });

    test('Recepción de basura normal cuando no hay escudo', () {
      final engine = TetrisEngine();
      expect(engine.isShieldActive, false);

      engine.receiveGarbage(2);
      expect(engine.pendingGarbageLines, 2);
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

  group('TetrisEngine - Sistema de Combo y Combo Máximo', () {
    test('Inicia con combo 0 y maxCombo 0', () {
      final engine = TetrisEngine();
      expect(engine.combo, 0);
      expect(engine.maxCombo, 0);
    });

    test('Limpiar líneas consecutivas incrementa combo y actualiza maxCombo', () {
      final engine = TetrisEngine();
      final targetRow = engine.rows - 1;

      for (int x = 0; x < engine.cols; x++) {
        engine.grid[targetRow][x] = Cell(type: TetrominoType.I);
      }
      final res1 = engine.clearLines();
      expect(res1.linesCleared, 1);
      expect(engine.combo, 1);
      expect(engine.maxCombo, 1);

      for (int x = 0; x < engine.cols; x++) {
        engine.grid[targetRow][x] = Cell(type: TetrominoType.I);
      }
      final res2 = engine.clearLines();
      expect(res2.linesCleared, 1);
      expect(engine.combo, 2);
      expect(engine.maxCombo, 2);

      for (int x = 0; x < engine.cols; x++) {
        engine.grid[targetRow][x] = Cell(type: TetrominoType.I);
      }
      final res3 = engine.clearLines();
      expect(res3.linesCleared, 1);
      expect(engine.combo, 3);
      expect(engine.maxCombo, 3);
    });

    test('Al expirar comboGraceTime el combo actual vuelve a 0 pero maxCombo retiene el récord', () {
      final engine = TetrisEngine();
      final targetRow = engine.rows - 1;

      for (int i = 0; i < 3; i++) {
        for (int x = 0; x < engine.cols; x++) {
          engine.grid[targetRow][x] = Cell(type: TetrominoType.I);
        }
        engine.clearLines();
      }
      expect(engine.combo, 3);
      expect(engine.maxCombo, 3);

      engine.update(3.5);
      expect(engine.combo, 0);
      expect(engine.maxCombo, 3);

      for (int x = 0; x < engine.cols; x++) {
        engine.grid[targetRow][x] = Cell(type: TetrominoType.I);
      }
      engine.clearLines();
      expect(engine.combo, 1);
      expect(engine.maxCombo, 3);
    });

    test('reset() reinicia tanto combo como maxCombo a 0', () {
      final engine = TetrisEngine();
      final targetRow = engine.rows - 1;

      for (int x = 0; x < engine.cols; x++) {
        engine.grid[targetRow][x] = Cell(type: TetrominoType.I);
      }
      engine.clearLines();
      expect(engine.combo, 1);
      expect(engine.maxCombo, 1);

      engine.reset();
      expect(engine.combo, 0);
      expect(engine.maxCombo, 0);
    });
  });
}
