import 'package:flutter_test/flutter_test.dart';
import 'package:tetris_app/game/tetris_engine.dart';
import 'package:tetris_app/game/tetris_types.dart';
import 'package:tetris_app/services/tetris_match_service.dart';

void main() {
  group('Sistema ELO Dinámico', () {
    test('Ganador recibe entre 60 y 100 puntos', () {
      // Caso 1: Victoria ultrarrápida y muy intensa (KO < 45s, combos altos, muchas líneas)
      final maxWin = TetrisMatchService.calcularEloDeltaGanador(
        durationSeconds: 35.0,
        linesSent: 16,
        maxCombo: 6,
        linesCleared: 24,
      );
      expect(maxWin, equals(100));

      // Caso 2: Victoria lenta con baja intensidad (> 180s, pocas líneas)
      final minWin = TetrisMatchService.calcularEloDeltaGanador(
        durationSeconds: 210.0,
        linesSent: 1,
        maxCombo: 0,
        linesCleared: 2,
      );
      expect(minWin, equals(60));

      // Caso 3: Victoria intermedia
      final midWin = TetrisMatchService.calcularEloDeltaGanador(
        durationSeconds: 90.0,
        linesSent: 6,
        maxCombo: 2,
        linesCleared: 10,
      );
      expect(midWin, inInclusiveRange(60, 100));
    });

    test('Perdedor pierde entre 50 y 90 puntos', () {
      // Caso 1: Derrota fulminante con nula respuesta (< 45s, 0 líneas enviadas)
      final maxLoss = TetrisMatchService.calcularEloDeltaPerdedor(
        durationSeconds: 30.0,
        linesSent: 0,
        maxCombo: 0,
        linesCleared: 0,
      );
      expect(maxLoss, equals(-90));

      // Caso 2: Derrota peleada en partida larga y muy disputada (> 180s, muchas líneas y combos)
      final minLoss = TetrisMatchService.calcularEloDeltaPerdedor(
        durationSeconds: 200.0,
        linesSent: 14,
        maxCombo: 5,
        linesCleared: 20,
      );
      expect(minLoss, equals(-50));

      // Caso 3: Abandono / Rendición (siempre -90 puntos)
      final surrenderLoss = TetrisMatchService.calcularEloDeltaPerdedor(
        durationSeconds: 120.0,
        linesSent: 10,
        maxCombo: 3,
        linesCleared: 12,
        isSurrender: true,
      );
      expect(surrenderLoss, equals(-90));
    });
  });

  group('Guardas del Motor en Fin de Partida y Pausa', () {
    late TetrisEngine engine;

    setUp(() {
      engine = TetrisEngine(cols: 10, rows: 20);
      engine.spawnPiece();
    });

    test('Acciones bloqueadas cuando isGameOver es true', () {
      engine.isGameOver = true;

      expect(engine.moveLeft(), isFalse);
      expect(engine.moveRight(), isFalse);
      expect(engine.softDrop(), isFalse);
      expect(engine.rotate(1), isFalse);
      expect(engine.rotate(-1), isFalse);
      expect(engine.hold(), isFalse);
      expect(engine.activateShield(), isFalse);

      final dropRes = engine.hardDrop();
      expect(dropRes.linesCleared, equals(0));
      expect(dropRes.linesSent, equals(0));
    });

    test('Acciones bloqueadas cuando isPaused es true', () {
      engine.isPaused = true;

      expect(engine.moveLeft(), isFalse);
      expect(engine.moveRight(), isFalse);
      expect(engine.softDrop(), isFalse);
      expect(engine.rotate(1), isFalse);
      expect(engine.rotate(-1), isFalse);
      expect(engine.hold(), isFalse);
      expect(engine.activateShield(), isFalse);

      final dropRes = engine.hardDrop();
      expect(dropRes.linesCleared, equals(0));
      expect(dropRes.linesSent, equals(0));
    });
  });
}
