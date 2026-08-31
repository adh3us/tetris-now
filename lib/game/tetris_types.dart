import 'package:flutter/material.dart';

enum TetrominoType { I, J, L, O, S, T, Z, GARBAGE }

enum CubeType { none, silver, gold }

typedef ArmorTier = CubeType;

enum ControllerTheme { dualshock, moba }

enum GameMode { solo, duel1v1, team2v2Combat, coop2v2Wide, clanChallenge, tournament }

enum GameAction {
  moveLeft,
  moveRight,
  softDrop,
  hardDrop,
  rotateCW,
  rotateCCW,
  hold,
  activateShield,
  pause,
  reset,
}

class Cell {
  final TetrominoType type;
  CubeType cubeType; // none, silver (Multicube), gold (Monocube)
  int pieceId;

  Cell({
    required this.type,
    this.cubeType = CubeType.none,
    this.pieceId = 0,
  });

  Cell copy() => Cell(type: type, cubeType: cubeType, pieceId: pieceId);
}

class Position {
  int x;
  int y;
  Position(this.x, this.y);
}

class PieceState {
  final TetrominoType type;
  int rotation; // 0: 0°, 1: 90°, 2: 180°, 3: 270°
  Position position;

  PieceState({
    required this.type,
    this.rotation = 0,
    required this.position,
  });

  PieceState copy() => PieceState(
        type: type,
        rotation: rotation,
        position: Position(position.x, position.y),
      );
}

class AttackResult {
  final int linesCleared;
  final int linesSent;
  final int energyGained;
  final int goldCubeLines;
  final int silverCubeLines;

  AttackResult({
    required this.linesCleared,
    required this.linesSent,
    required this.energyGained,
    this.goldCubeLines = 0,
    this.silverCubeLines = 0,
  });
}

const Map<TetrominoType, Color> tetrominoColors = {
  TetrominoType.I: Color(0xFF00E5FF),
  TetrominoType.T: Color(0xFFA855F7),
  TetrominoType.O: Color(0xFFFFD600),
  TetrominoType.S: Color(0xFF10B981),
  TetrominoType.Z: Color(0xFFEF4444),
  TetrominoType.J: Color(0xFF2563EB),
  TetrominoType.L: Color(0xFFF97316),
  TetrominoType.GARBAGE: Color(0xFF475569),
};

const Map<TetrominoType, List<List<List<int>>>> tetrominoShapes = {
  TetrominoType.I: [
    [[0,0,0,0],[1,1,1,1],[0,0,0,0],[0,0,0,0]],
    [[0,0,1,0],[0,0,1,0],[0,0,1,0],[0,0,1,0]],
    [[0,0,0,0],[0,0,0,0],[1,1,1,1],[0,0,0,0]],
    [[0,1,0,0],[0,1,0,0],[0,1,0,0],[0,1,0,0]],
  ],
  TetrominoType.T: [
    [[0,1,0],[1,1,1],[0,0,0]],
    [[0,1,0],[0,1,1],[0,1,0]],
    [[0,0,0],[1,1,1],[0,1,0]],
    [[0,1,0],[1,1,0],[0,1,0]],
  ],
  TetrominoType.O: [
    [[1,1],[1,1]],
    [[1,1],[1,1]],
    [[1,1],[1,1]],
    [[1,1],[1,1]],
  ],
  TetrominoType.S: [
    [[0,1,1],[1,1,0],[0,0,0]],
    [[0,1,0],[0,1,1],[0,0,1]],
    [[0,0,0],[0,1,1],[1,1,0]],
    [[1,0,0],[1,1,0],[0,1,0]],
  ],
  TetrominoType.Z: [
    [[1,1,0],[0,1,1],[0,0,0]],
    [[0,0,1],[0,1,1],[0,1,0]],
    [[0,0,0],[1,1,0],[0,1,1]],
    [[0,1,0],[1,1,0],[1,0,0]],
  ],
  TetrominoType.J: [
    [[1,0,0],[1,1,1],[0,0,0]],
    [[0,1,1],[0,1,0],[0,1,0]],
    [[0,0,0],[1,1,1],[0,0,1]],
    [[0,1,0],[0,1,0],[1,1,0]],
  ],
  TetrominoType.L: [
    [[0,0,1],[1,1,1],[0,0,0]],
    [[0,1,0],[0,1,0],[0,1,1]],
    [[0,0,0],[1,1,1],[1,0,0]],
    [[1,1,0],[0,1,0],[0,1,0]],
  ],
};
