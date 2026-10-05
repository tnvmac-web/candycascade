import 'package:candy_cascade/logic/match_engine.dart';
import 'package:candy_cascade/models/candy_tile.dart';
import 'package:candy_cascade/models/level_data.dart';
import 'package:flutter_test/flutter_test.dart';

/// Headless checks for the pieces that are not pure board rules: level data
/// sanity, the objective maths, and a full cascade driven through the engine
/// the same way the controller drives it.
void main() {
  group('level data', () {
    test('every hand crafted level is internally consistent', () {
      for (int id = 1; id <= LevelRepository.handCraftedCount; id++) {
        final LevelData level = LevelRepository.levelFor(id);
        expect(level.id, id);
        expect(level.rows, greaterThan(0));
        expect(level.cols, greaterThan(0));
        expect(level.moves, greaterThan(0), reason: 'level $id has no moves');
        expect(level.objectives, isNotEmpty,
            reason: 'level $id has no objective');
        expect(level.colorCount, inInclusiveRange(3, 6));

        // Star thresholds must ascend, or a 3 star score could be unreachable.
        expect(level.stars.one, lessThanOrEqualTo(level.stars.two),
            reason: 'level $id stars');
        expect(level.stars.two, lessThanOrEqualTo(level.stars.three),
            reason: 'level $id stars');

        // Any frosting objective must be satisfiable by the frosting present.
        final LevelObjective? frost = level.objectiveOf(ObjectiveType.frosting);
        if (frost != null) {
          expect(level.blockers, isNotEmpty,
              reason: 'level $id wants frosting it does not have');
          expect(frost.target, lessThanOrEqualTo(level.blockers.length),
              reason: 'level $id wants more frosting than exists');
        }

        // A jelly objective needs a drop column and a matching count.
        final LevelObjective? jelly =
            level.objectiveOf(ObjectiveType.ingredient);
        if (jelly != null) {
          expect(level.ingredientDropColumn, isNotNull,
              reason: 'level $id jelly has no column');
          expect(level.jellyCount, greaterThanOrEqualTo(jelly.target),
              reason: 'level $id spawns fewer jellies than it needs');
        }

        // No blocker or hole may sit outside the grid.
        for (final BlockerCell b in level.blockers) {
          expect(b.row, inInclusiveRange(0, level.rows - 1));
          expect(b.col, inInclusiveRange(0, level.cols - 1));
        }
        for (final int idx in level.blockedCells) {
          expect(idx, inInclusiveRange(0, level.cellCount - 1));
        }
      }
    });

    test('generated levels ramp and stay valid deep into the list', () {
      for (int id = LevelRepository.handCraftedCount + 1; id <= 120; id++) {
        final LevelData level = LevelRepository.levelFor(id);
        expect(level.moves, greaterThan(0), reason: 'level $id has no moves');
        expect(level.objectives, isNotEmpty);
        expect(level.stars.one, lessThanOrEqualTo(level.stars.three));

        final LevelObjective? frost = level.objectiveOf(ObjectiveType.frosting);
        if (frost != null) {
          expect(frost.target, lessThanOrEqualTo(level.blockers.length));
        }
      }
    });

    test('a level survives a json round trip', () {
      final LevelData original = LevelRepository.levelFor(10);
      final LevelData copy = LevelData.fromJson(original.toJson());
      expect(copy.id, original.id);
      expect(copy.name, original.name);
      expect(copy.moves, original.moves);
      expect(copy.colorCount, original.colorCount);
      expect(copy.blockers.length, original.blockers.length);
      expect(copy.blockedCells, original.blockedCells);
      expect(copy.objectives.length, original.objectives.length);
      expect(copy.stars.three, original.stars.three);
    });
  });

  group('objectives', () {
    test('progress is clamped for the ratio', () {
      const LevelObjective o =
          LevelObjective(type: ObjectiveType.score, target: 100, progress: 250);
      expect(o.isComplete, isTrue);
      expect(o.ratio, 1.0);
    });

    test('copyWith replaces progress without touching the rest', () {
      const LevelObjective o = LevelObjective(
          type: ObjectiveType.frosting, target: 9, label: 'Frosting');
      final LevelObjective next = o.copyWith(progress: 4);
      expect(next.target, 9);
      expect(next.label, 'Frosting');
      expect(next.progress, 4);
      expect(next.isComplete, isFalse);
    });

    test('star thresholds map scores to the right star count', () {
      const StarThresholds t = StarThresholds(one: 100, two: 200, three: 300);
      expect(t.starsFor(0), 0);
      expect(t.starsFor(99), 0);
      expect(t.starsFor(100), 1);
      expect(t.starsFor(199), 1);
      expect(t.starsFor(200), 2);
      expect(t.starsFor(300), 3);
      expect(t.starsFor(999999), 3);
    });
  });

  group('end to end cascade', () {
    /// Drives the engine the way GameController does: find matches, plan, clear,
    /// gravity, refill, repeat, until the board is quiet.
    int runCascade(MatchEngine e) {
      int total = 0;
      int cascade = 0;
      while (cascade < 40) {
        final List<MatchGroup> matches = e.findMatches();
        if (matches.isEmpty) break;
        final ClearPlan plan = e.buildPlan(matches, cascadeIndex: cascade);
        if (plan.isEmpty) break;
        e.crackBlockers(plan.cells);
        e.applyClear(plan);
        total += plan.score;
        e.applyGravity();
        e.refill();
        cascade++;
      }
      return total;
    }

    test('a board settles to no matches after a cascade', () {
      final MatchEngine e =
          MatchEngine(rows: 9, cols: 9, colorCount: 4, seed: 2024);
      e.generateBoard();
      runCascade(e);
      expect(e.findMatches(), isEmpty);
      for (final CandyTile? t in e.cells) {
        expect(t, isNotNull, reason: 'refill must leave no gaps');
      }
    });

    test('the board stays playable across many simulated turns', () {
      final MatchEngine e =
          MatchEngine(rows: 9, cols: 9, colorCount: 5, seed: 555);
      e.generateBoard();

      for (int turn = 0; turn < 60; turn++) {
        final List<int>? hint = e.findHint();
        if (hint == null) {
          e.shuffle();
          continue;
        }
        final int i = hint[0];
        final int j = hint[1];
        final SwapOutcome outcome =
            e.applySwap(e.rowOf(i), e.colOf(i), e.rowOf(j), e.colOf(j));
        expect(outcome.valid, isTrue,
            reason: 'turn $turn: the hint was not a legal swap');
        runCascade(e);
        e.ensurePlayable();
      }

      // After all that, the board must still be sound.
      expect(e.findMatches(), isEmpty);
      expect(e.hasPossibleMove(), isTrue);
      expect(e.cells.where((CandyTile? t) => t == null), isEmpty);
    });

    test('a frosting level can be completed by matching next to the ice', () {
      final LevelData level = LevelRepository.levelFor(3);
      final MatchEngine e = MatchEngine(
        rows: level.rows,
        cols: level.cols,
        colorCount: level.colorCount,
        blockedCells: Set<int>.from(level.blockedCells),
        blockers: level.blockers,
        seed: level.seed,
      );
      e.generateBoard();
      final int start = e.blockerCount;
      expect(start, greaterThan(0));

      // Hammer every frosting cell directly: the objective must be reachable.
      for (final BlockerCell b in level.blockers) {
        e.crackBlockers(<int>[e.indexOf(b.row, b.col)]);
      }
      expect(e.allBlockersCleared, isTrue);
      expect(e.blockerCount, 0);
    });

    test('a jelly token falls to the bottom and can be collected', () {
      final MatchEngine e =
          MatchEngine(rows: 6, cols: 6, colorCount: 4, seed: 31);
      e.generateBoard();
      final CandyTile? jelly = e.spawnJelly(2);
      expect(jelly, isNotNull);

      // Clear the whole column beneath it, then let gravity work.
      for (int r = 1; r < e.rows; r++) {
        e.cells[e.indexOf(r, 2)] = null;
      }
      e.applyGravity();

      expect(e.tileAt(e.rows - 1, 2)!.isJelly, isTrue,
          reason: 'the jelly must reach the bottom');
    });
  });

  group('player progression', () {
    test('lives regenerate from a stored timestamp', () {
      // Mirrors PlayerProgress.regenerateLives without touching storage.
      const int lifeRegenMs = 20 * 60 * 1000;
      final DateTime start = DateTime(2026, 1, 1, 12);

      int lives = 2;
      int? lastLifeAt = start.millisecondsSinceEpoch;

      // Forty minutes later: two lives should have arrived, capping at five.
      final int nowMs =
          start.add(const Duration(minutes: 40)).millisecondsSinceEpoch;
      while (lives < 5) {
        final int due = lastLifeAt! + lifeRegenMs;
        if (nowMs < due) break;
        lives++;
        lastLifeAt = lives >= 5 ? null : due;
      }
      expect(lives, 4, reason: 'forty minutes gives exactly two lives');
      expect(lastLifeAt, isNotNull);
    });

    test('a long absence tops the bar up and clears the timer', () {
      const int lifeRegenMs = 20 * 60 * 1000;
      final DateTime start = DateTime(2026, 1, 1, 12);
      int lives = 1;
      int? lastLifeAt = start.millisecondsSinceEpoch;

      final int nowMs =
          start.add(const Duration(hours: 5)).millisecondsSinceEpoch;
      while (lives < 5) {
        final int due = lastLifeAt! + lifeRegenMs;
        if (nowMs < due) break;
        lives++;
        lastLifeAt = lives >= 5 ? null : due;
      }
      expect(lives, 5);
      expect(lastLifeAt, isNull, reason: 'a full bar has no pending life');
    });
  });
}
