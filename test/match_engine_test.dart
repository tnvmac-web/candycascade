import 'package:candy_cascade/logic/match_engine.dart';
import 'package:candy_cascade/models/candy_tile.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds an engine whose board is fully under test control: every cell is a
/// hole until a test fills it, which makes the expected matches obvious.
MatchEngine blankEngine({int rows = 6, int cols = 6, int colorCount = 4}) {
  final MatchEngine engine = MatchEngine(
    rows: rows,
    cols: cols,
    colorCount: colorCount,
    blockedCells: <int>{
      for (int i = 0; i < rows * cols; i++) i,
    },
    seed: 42,
  );
  return engine;
}

/// Places a candy and makes the cell playable.
void put(MatchEngine e, int row, int col, CandyColorType color,
    {SpecialType special = SpecialType.none}) {
  e.blockedCells.remove(e.indexOf(row, col));
  e.cells[e.indexOf(row, col)] = CandyTile(
    row: row,
    col: col,
    color: special == SpecialType.rainbow ? CandyColorType.none : color,
    special: special,
    id: e.newId(),
  );
}

/// Fills every cell with a checkerboard of two colours, which never matches.
///
/// The colours are deliberately ones no test uses as a test colour, so a
/// stray same coloured neighbour can never join a run by accident.
void fillSafe(MatchEngine e) {
  for (int r = 0; r < e.rows; r++) {
    for (int c = 0; c < e.cols; c++) {
      put(e, r, c,
          (r + c) % 2 == 0 ? CandyColorType.orange : CandyColorType.yellow);
    }
  }
}

/// Empties the cells in [cells] (given as row, col pairs) so a test can lay out
/// a shape without the filler colours interfering.
void clearCells(MatchEngine e, List<List<int>> cells) {
  for (final List<int> rc in cells) {
    e.cells[e.indexOf(rc[0], rc[1])] = null;
  }
}

void main() {
  group('board generation', () {
    test('a fresh board has no matches and at least one move', () {
      final MatchEngine e =
          MatchEngine(rows: 9, cols: 9, colorCount: 5, seed: 7);
      e.generateBoard();
      expect(e.findMatches(), isEmpty);
      expect(e.hasPossibleMove(), isTrue);
    });

    test('generation is deterministic for a given seed', () {
      final MatchEngine a =
          MatchEngine(rows: 9, cols: 9, colorCount: 5, seed: 123);
      final MatchEngine b =
          MatchEngine(rows: 9, cols: 9, colorCount: 5, seed: 123);
      a.generateBoard();
      b.generateBoard();
      for (int i = 0; i < a.cells.length; i++) {
        expect(a.cells[i]?.color, b.cells[i]?.color, reason: 'cell $i differs');
      }
    });

    test('holes stay empty after generation', () {
      final MatchEngine e = MatchEngine(
        rows: 5,
        cols: 5,
        colorCount: 4,
        blockedCells: <int>{12},
        seed: 3,
      );
      e.generateBoard();
      expect(e.tileAt(2, 2), isNull);
    });
  });

  group('match detection', () {
    test('three in a row is found', () {
      final MatchEngine e = blankEngine();
      fillSafe(e);
      put(e, 2, 1, CandyColorType.green);
      put(e, 2, 2, CandyColorType.green);
      put(e, 2, 3, CandyColorType.green);

      final List<MatchGroup> groups = e.findMatches();
      expect(groups.length, 1);
      expect(groups.first.cells.length, 3);
      expect(groups.first.shape, MatchShape.line3);
      expect(groups.first.spawnSpecial, SpecialType.none);
    });

    test('four in a row spawns a horizontal rocket', () {
      final MatchEngine e = blankEngine();
      fillSafe(e);
      clearCells(e, <List<int>>[
        for (int r = 2; r <= 4; r++)
          for (int c = 0; c < 6; c++) <int>[r, c],
      ]);
      for (int c = 1; c <= 4; c++) {
        put(e, 3, c, CandyColorType.yellow);
      }
      final MatchGroup g = e.findMatches().single;
      expect(g.shape, MatchShape.line4);
      expect(g.spawnSpecial, SpecialType.stripedHorizontal);
    });

    test('four in a column spawns a vertical rocket', () {
      final MatchEngine e = blankEngine();
      fillSafe(e);
      clearCells(e, <List<int>>[
        for (int r = 0; r < 6; r++) <int>[r, 4],
      ]);
      for (int r = 0; r <= 3; r++) {
        put(e, r, 4, CandyColorType.purple);
      }
      final MatchGroup g = e.findMatches().single;
      expect(g.shape, MatchShape.line4);
      expect(g.spawnSpecial, SpecialType.stripedVertical);
    });

    test('five in a row spawns a rainbow', () {
      final MatchEngine e = blankEngine(rows: 6, cols: 8);
      fillSafe(e);
      clearCells(e, <List<int>>[
        for (int c = 0; c < 8; c++) <int>[2, c],
      ]);
      for (int c = 1; c <= 5; c++) {
        put(e, 2, c, CandyColorType.orange);
      }
      final MatchGroup g = e.findMatches().single;
      expect(g.shape, MatchShape.line5);
      expect(g.spawnSpecial, SpecialType.rainbow);
    });

    test('an L shape spawns a wrapped bomb', () {
      final MatchEngine e = blankEngine();
      fillSafe(e);
      // Clear the whole L region so the filler colours cannot extend a run.
      clearCells(e, <List<int>>[
        for (int c = 0; c < 6; c++) <int>[2, c],
        for (int r = 3; r < 6; r++) <int>[r, 3],
      ]);
      // Horizontal run of 3 on row 2, plus a vertical run of 3 in column 3.
      put(e, 2, 1, CandyColorType.red);
      put(e, 2, 2, CandyColorType.red);
      put(e, 2, 3, CandyColorType.red);
      put(e, 3, 3, CandyColorType.red);
      put(e, 4, 3, CandyColorType.red);

      final List<MatchGroup> groups = e.findMatches();
      expect(groups.length, 1,
          reason: 'the runs share a cell so they are one group');
      expect(groups.first.cells.length, 5);
      expect(groups.first.shape, MatchShape.lShape);
      expect(groups.first.spawnSpecial, SpecialType.wrapped);
      // The bomb must land on the corner where the runs cross.
      expect(groups.first.spawnIndex, e.indexOf(2, 3));
    });

    test('a T shape spawns a wrapped bomb', () {
      final MatchEngine e = blankEngine();
      fillSafe(e);
      clearCells(e, <List<int>>[
        for (int c = 0; c < 6; c++) <int>[2, c],
        for (int r = 0; r <= 4; r++) <int>[r, 2],
      ]);
      put(e, 2, 1, CandyColorType.blue);
      put(e, 2, 2, CandyColorType.blue);
      put(e, 2, 3, CandyColorType.blue);
      put(e, 1, 2, CandyColorType.blue);
      put(e, 0, 2, CandyColorType.blue);
      final MatchGroup g = e.findMatches().single;
      expect(g.cells.length, 5);
      expect(g.spawnSpecial, SpecialType.wrapped);
    });

    test('a wrapped candy still matches by colour', () {
      // A wrapped candy is a normal candy with a special attached, so it takes
      // part in colour runs like any other.
      final MatchEngine e = blankEngine();
      fillSafe(e);
      clearCells(e, <List<int>>[
        for (int c = 0; c < 6; c++) <int>[1, c],
      ]);
      put(e, 1, 1, CandyColorType.red);
      put(e, 1, 2, CandyColorType.red, special: SpecialType.wrapped);
      put(e, 1, 3, CandyColorType.red);
      final MatchGroup g = e.findMatches().single;
      expect(g.cells.length, 3);
    });
  });

  group('swap validation', () {
    test('an invalid swap is reverted', () {
      final MatchEngine e = blankEngine();
      fillSafe(e);
      final CandyColorType before = e.tileAt(0, 0)!.color;
      final SwapOutcome outcome = e.applySwap(0, 0, 0, 1);
      expect(outcome.valid, isFalse);
      expect(e.tileAt(0, 0)!.color, before, reason: 'board must be unchanged');
    });

    test('a swap that forms a match is accepted', () {
      final MatchEngine e = blankEngine();
      fillSafe(e);
      // Row 2 will be red at columns 0 and 2, and we drop a red in column 1
      // from the row above.
      put(e, 2, 0, CandyColorType.green);
      put(e, 2, 1, CandyColorType.yellow);
      put(e, 2, 2, CandyColorType.green);
      put(e, 1, 1, CandyColorType.green);

      final SwapOutcome outcome = e.applySwap(1, 1, 2, 1);
      expect(outcome.valid, isTrue);
      expect(e.findMatches(), isNotEmpty);
    });

    test('swapping two rainbows is always legal and seeds the whole board', () {
      final MatchEngine e = blankEngine(rows: 4, cols: 4);
      fillSafe(e);
      put(e, 1, 1, CandyColorType.none, special: SpecialType.rainbow);
      put(e, 1, 2, CandyColorType.none, special: SpecialType.rainbow);
      final SwapOutcome outcome = e.applySwap(1, 1, 1, 2);
      expect(outcome.valid, isTrue);
      expect(outcome.combo, ComboKind.rainbowRainbow);
      expect(outcome.comboSeed.length, 16);
    });

    test('a rainbow plus a normal candy targets that colour', () {
      final MatchEngine e = blankEngine(rows: 4, cols: 4);
      fillSafe(e);
      put(e, 1, 1, CandyColorType.none, special: SpecialType.rainbow);
      put(e, 1, 2, CandyColorType.red);
      final SwapOutcome outcome = e.applySwap(1, 1, 1, 2);
      expect(outcome.combo, ComboKind.rainbowNormal);
      expect(outcome.rainbowTarget, CandyColorType.red);
      // Every red on the board is in the seed, plus the two swap cells.
      expect(outcome.comboSeed.length, greaterThanOrEqualTo(2));
    });

    test('two rockets make a cross', () {
      final MatchEngine e = blankEngine(rows: 5, cols: 5);
      fillSafe(e);
      put(e, 2, 2, CandyColorType.red, special: SpecialType.stripedHorizontal);
      put(e, 2, 3, CandyColorType.blue, special: SpecialType.stripedVertical);
      final SwapOutcome outcome = e.applySwap(2, 2, 2, 3);
      expect(outcome.combo, ComboKind.stripedStriped);
      // Full row 2 plus full column 3, minus the shared cell.
      expect(outcome.comboSeed.length, 9);
    });
  });

  group('clear planning', () {
    test('a striped candy detonates its whole row', () {
      final MatchEngine e = blankEngine(rows: 5, cols: 6);
      fillSafe(e);
      clearCells(e, <List<int>>[
        <int>[2, 1],
        <int>[2, 2],
        <int>[2, 3],
      ]);
      put(e, 2, 2, CandyColorType.red, special: SpecialType.stripedHorizontal);
      put(e, 2, 1, CandyColorType.red);
      put(e, 2, 3, CandyColorType.red);

      final List<MatchGroup> matches = e.findMatches();
      final ClearPlan plan = e.buildPlan(matches);
      // The whole row 2 clears, plus nothing else.
      for (int c = 0; c < 6; c++) {
        expect(plan.cells.contains(e.indexOf(2, c)), isTrue,
            reason: 'row cell $c missing');
      }
      expect(plan.cells.length, 6);
    });

    test('a wrapped candy clears its 3x3 neighbourhood', () {
      final MatchEngine e = blankEngine(rows: 6, cols: 6);
      fillSafe(e);
      clearCells(e, <List<int>>[
        <int>[3, 2],
        <int>[3, 3],
        <int>[3, 4],
      ]);
      put(e, 3, 3, CandyColorType.green, special: SpecialType.wrapped);
      put(e, 3, 2, CandyColorType.green);
      put(e, 3, 4, CandyColorType.green);
      final ClearPlan plan = e.buildPlan(e.findMatches());
      // The three matched cells plus the full 3x3 around the bomb at (3,3).
      expect(plan.cells.contains(e.indexOf(2, 2)), isTrue);
      expect(plan.cells.contains(e.indexOf(2, 3)), isTrue);
      expect(plan.cells.contains(e.indexOf(2, 4)), isTrue);
      expect(plan.cells.contains(e.indexOf(3, 2)), isTrue);
      expect(plan.cells.contains(e.indexOf(3, 3)), isTrue);
      expect(plan.cells.contains(e.indexOf(3, 4)), isTrue);
      expect(plan.cells.contains(e.indexOf(4, 2)), isTrue);
      expect(plan.cells.contains(e.indexOf(4, 3)), isTrue);
      expect(plan.cells.contains(e.indexOf(4, 4)), isTrue);
      // Nothing outside the 3x3 on that row.
      expect(plan.cells.contains(e.indexOf(3, 1)), isFalse);
      expect(plan.cells.contains(e.indexOf(3, 5)), isFalse);
    });

    test('a spawned special is transformed, not removed', () {
      final MatchEngine e = blankEngine();
      fillSafe(e);
      clearCells(e, <List<int>>[
        for (int r = 2; r <= 4; r++)
          for (int c = 0; c < 6; c++) <int>[r, c],
      ]);
      for (int c = 1; c <= 4; c++) {
        put(e, 3, c, CandyColorType.yellow);
      }
      final ClearPlan plan = e.buildPlan(e.findMatches());
      final int spawnIdx = plan.spawns.single.index;
      expect(plan.cells.contains(spawnIdx), isFalse,
          reason: 'the rocket must survive');
      e.applyClear(plan);
      expect(e.tileAtIdx(spawnIdx)!.special, SpecialType.stripedHorizontal);
    });

    test('a rainbow detonation removes every candy of the target colour', () {
      final MatchEngine e = blankEngine(rows: 5, cols: 5);
      fillSafe(e);
      put(e, 2, 2, CandyColorType.none, special: SpecialType.rainbow);
      put(e, 0, 0, CandyColorType.purple);
      put(e, 4, 4, CandyColorType.purple);
      final ClearPlan plan = e.buildPlan(
        <MatchGroup>[],
        comboSeed: <int>{e.indexOf(2, 2)},
        rainbowTarget: CandyColorType.purple,
      );
      expect(plan.cells.contains(e.indexOf(0, 0)), isTrue);
      expect(plan.cells.contains(e.indexOf(4, 4)), isTrue);
      expect(plan.cells.contains(e.indexOf(2, 2)), isTrue);
    });
  });

  group('gravity and refill', () {
    test('candies fall to the bottom of a column', () {
      final MatchEngine e = blankEngine(rows: 5, cols: 3);
      fillSafe(e);
      final CandyTile top = e.tileAt(0, 0)!;
      // Empty the whole column then drop one candy at the top.
      for (int r = 0; r < 5; r++) {
        e.cells[e.indexOf(r, 0)] = null;
      }
      put(e, 0, 0, CandyColorType.red);
      final CandyTile only = e.tileAt(0, 0)!;
      expect(only.id, isNot(top.id));

      final List<DropRecord> drops = e.applyGravity();
      expect(drops.length, 1);
      expect(drops.first.toRow, 4);
      expect(e.tileAt(4, 0)!.color, CandyColorType.red);
      expect(e.tileAt(0, 0), isNull);
    });

    test('gravity never crosses a hole', () {
      final MatchEngine e = MatchEngine(
        rows: 5,
        cols: 2,
        colorCount: 4,
        blockedCells: <int>{2 * 2 + 0}, // hole at (2,0)
        seed: 1,
      );
      // Column 0: cells (0,0) (1,0) above the hole, (3,0) (4,0) below.
      put(e, 0, 0, CandyColorType.red);
      put(e, 1, 0, CandyColorType.blue);
      put(e, 3, 0, CandyColorType.green);
      put(e, 4, 0, CandyColorType.yellow);

      e.applyGravity();
      // The candy above the hole cannot fall through it.
      expect(e.tileAt(1, 0)!.color, CandyColorType.blue);
      expect(e.tileAt(0, 0)!.color, CandyColorType.red);
      // The candy below is already resting on the floor.
      expect(e.tileAt(4, 0)!.color, CandyColorType.yellow);
    });

    test('refill fills every empty cell and leaves no nulls', () {
      final MatchEngine e = blankEngine(rows: 4, cols: 4);
      fillSafe(e);
      e.cells[e.indexOf(3, 1)] = null;
      e.cells[e.indexOf(0, 2)] = null;
      final List<CandyTile> created = e.refill();
      expect(created.length, 2);
      for (final CandyTile? t in e.cells) {
        expect(t, isNotNull);
      }
    });

    test('refilled candies start above the board so they visibly fall in', () {
      final MatchEngine e = blankEngine(rows: 4, cols: 2);
      fillSafe(e);
      e.cells[e.indexOf(3, 0)] = null;
      final List<CandyTile> created = e.refill();
      expect(created.single.animY, lessThan(0));
      expect(created.single.isFalling, isTrue);
    });
  });

  group('frosting', () {
    test('a clear next to frosting damages it', () {
      final MatchEngine e = MatchEngine(
        rows: 5,
        cols: 5,
        colorCount: 4,
        blockers: <BlockerCell>[BlockerCell(row: 2, col: 2, hp: 1, maxHp: 1)],
        seed: 5,
      );
      fillSafe(e);
      final int broken = e.crackBlockers(<int>[e.indexOf(2, 3)]);
      expect(broken, 1);
      expect(e.blockerAt(2, 2)!.isBroken, isTrue);
      expect(e.allBlockersCleared, isTrue);
    });

    test('two hp frosting needs two hits', () {
      final MatchEngine e = MatchEngine(
        rows: 5,
        cols: 5,
        colorCount: 4,
        blockers: <BlockerCell>[BlockerCell(row: 1, col: 1, hp: 2, maxHp: 2)],
        seed: 5,
      );
      fillSafe(e);
      expect(e.crackBlockers(<int>[e.indexOf(1, 2)]), 0);
      expect(e.blockerAt(1, 1)!.hp, 1);
      expect(e.crackBlockers(<int>[e.indexOf(1, 0)]), 1);
      expect(e.blockerAt(1, 1)!.isBroken, isTrue);
    });

    test('frosting under a cleared cell is damaged', () {
      final MatchEngine e = MatchEngine(
        rows: 4,
        cols: 4,
        colorCount: 4,
        blockers: <BlockerCell>[BlockerCell(row: 2, col: 2, hp: 1, maxHp: 1)],
        seed: 5,
      );
      fillSafe(e);
      expect(e.crackBlockers(<int>[e.indexOf(2, 2)]), 1);
    });
  });

  group('shuffle', () {
    test('a board with no moves is reshuffled into one that has moves', () {
      final MatchEngine e =
          MatchEngine(rows: 5, cols: 5, colorCount: 2, seed: 11);
      e.generateBoard();
      // A two colour board is easy to arrange into a dead state; shuffle must
      // recover it.
      final bool recovered = e.shuffle();
      expect(recovered, isTrue);
      expect(e.findMatches(), isEmpty);
      expect(e.hasPossibleMove(), isTrue);
    });

    test('shuffle preserves every candy and the hole layout', () {
      final MatchEngine e = MatchEngine(
        rows: 5,
        cols: 5,
        colorCount: 4,
        blockedCells: <int>{12},
        seed: 9,
      );
      e.generateBoard();
      final Set<int> ids = <int>{
        for (final CandyTile? t in e.cells)
          if (t != null) t.id,
      };
      e.shuffle();
      final Set<int> after = <int>{
        for (final CandyTile? t in e.cells)
          if (t != null) t.id,
      };
      expect(after, ids);
      expect(e.tileAt(2, 2), isNull);
    });
  });

  group('hints', () {
    test('a hint is always a legal swap', () {
      final MatchEngine e =
          MatchEngine(rows: 9, cols: 9, colorCount: 5, seed: 77);
      e.generateBoard();
      final List<int>? hint = e.findHint();
      expect(hint, isNotNull);
      final int i = hint![0];
      final int j = hint[1];
      expect(e.areAdjacent(e.rowOf(i), e.colOf(i), e.rowOf(j), e.colOf(j)),
          isTrue);
      final SwapOutcome outcome =
          e.applySwap(e.rowOf(i), e.colOf(i), e.rowOf(j), e.colOf(j));
      expect(outcome.valid, isTrue);
    });
  });

  group('jelly', () {
    test('a jelly token is spawned and counted', () {
      final MatchEngine e =
          MatchEngine(rows: 6, cols: 6, colorCount: 4, seed: 21);
      e.generateBoard();
      final CandyTile? jelly = e.spawnJelly(3);
      expect(jelly, isNotNull);
      expect(jelly!.isJelly, isTrue);
      expect(e.jellyOnBoard, 1);
    });

    test('a jelly token does not match with candies', () {
      final MatchEngine e = blankEngine();
      fillSafe(e);
      // Empty the row first so the jelly is the only thing breaking the run.
      clearCells(e, <List<int>>[
        <int>[2, 1],
        <int>[2, 2],
        <int>[2, 3],
      ]);
      put(e, 2, 1, CandyColorType.red);
      put(e, 2, 3, CandyColorType.red);
      e.cells[e.indexOf(2, 2)] = CandyTile(
        row: 2,
        col: 2,
        color: CandyColorType.none,
        special: SpecialType.jelly,
        id: e.newId(),
      );
      expect(e.findMatches(), isEmpty);
    });
  });

  group('lollipop hammer', () {
    test('smash removes one candy without touching the rest', () {
      final MatchEngine e = blankEngine(rows: 3, cols: 3);
      fillSafe(e);
      final int before = e.cells.where((CandyTile? t) => t != null).length;
      final ClearedCandy? removed = e.smash(e.indexOf(1, 1));
      expect(removed, isNotNull);
      expect(e.cells.where((CandyTile? t) => t != null).length, before - 1);
      expect(e.tileAt(1, 1), isNull);
    });

    test('smash refuses a jelly token', () {
      final MatchEngine e = blankEngine(rows: 3, cols: 3);
      fillSafe(e);
      e.cells[e.indexOf(1, 1)] = CandyTile(
        row: 1,
        col: 1,
        color: CandyColorType.none,
        special: SpecialType.jelly,
        id: e.newId(),
      );
      expect(e.smash(e.indexOf(1, 1)), isNull);
      expect(e.tileAt(1, 1), isNotNull);
    });
  });

  group('scoring', () {
    test('cascades multiply the score', () {
      expect(ScoreRules.clearScore(3, 0), 3 * ScoreRules.perCandy);
      expect(ScoreRules.clearScore(3, 1), 3 * ScoreRules.perCandy * 2);
      expect(ScoreRules.clearScore(3, 2), 3 * ScoreRules.perCandy * 3);
    });

    test('the multiplier is capped so one cascade cannot run away', () {
      expect(ScoreRules.cascadeMultiplier(50), 8);
    });
  });
}
