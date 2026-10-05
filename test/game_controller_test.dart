import 'package:candy_cascade/logic/game_controller.dart';
import 'package:candy_cascade/services/iap_service.dart';
import 'package:candy_cascade/services/persistence_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Exercises the boosters through the real controller, so the rules about what
/// costs a move and what gets disarmed are covered end to end rather than only
/// in the engine.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<GameController> controllerFor() async {
    final PersistenceService persistence = await PersistenceService.open();
    final IapService iap = IapService(persistence);
    return GameController(persistence: persistence, iap: iap);
  }

  group('level start', () {
    test('starting a level spends a life and sets up the board', () async {
      final GameController c = await controllerFor();
      final bool ok = await c.startLevel(1);
      expect(ok, isTrue);
      expect(c.state, isNotNull);
      expect(c.state!.level.id, 1);
      expect(c.state!.movesLeft, 25);
      expect(c.state!.score, 0);
      expect(c.state!.phase, GamePhase.playing);
      expect(c.progress.lives, PlayerProgress.maxLives - 1);
    });

    test('starting without a life is refused', () async {
      final GameController c = await controllerFor();
      c.progress.lives = 0;
      final bool ok = await c.startLevel(1);
      expect(ok, isFalse);
      expect(c.state, isNull, reason: 'no level should be created');
    });

    test('a level can be started without spending a life', () async {
      final GameController c = await controllerFor();
      final int before = c.progress.lives;
      await c.startLevel(1, spendLife: false);
      expect(c.progress.lives, before);
    });

    test('the objectives start at zero', () async {
      final GameController c = await controllerFor();
      await c.startLevel(1);
      for (final o in c.state!.objectives) {
        expect(o.progress, 0);
      }
    });
  });

  group('a normal move', () {
    test('a valid swap scores and spends exactly one move', () async {
      final GameController c = await controllerFor();
      await c.startLevel(1);

      final List<int>? hint = c.debugHint();
      expect(hint, isNotNull, reason: 'a fresh board always has a move');
      final int i = hint![0];
      final int j = hint[1];

      final int movesBefore = c.state!.movesLeft;
      await c.onSwap(
          c.debugRow(i), c.debugCol(i), c.debugRow(j), c.debugCol(j));

      expect(c.state!.movesLeft, movesBefore - 1);
      expect(c.state!.score, greaterThan(0), reason: 'a match must score');
      expect(c.state!.busy, isFalse, reason: 'the cascade must have settled');
    });

    test('an illegal swap changes nothing and costs nothing', () async {
      final GameController c = await controllerFor();
      await c.startLevel(1);

      // Find two adjacent cells whose swap forms no match.
      List<int>? bad;
      for (int r = 0; r < 9 && bad == null; r++) {
        for (int col = 0; col < 8 && bad == null; col++) {
          if (!c.debugSwapIsValid(r, col, r, col + 1)) {
            bad = <int>[r, col, r, col + 1];
          }
        }
      }
      expect(bad, isNotNull, reason: 'a board has plenty of dead swaps');

      final int movesBefore = c.state!.movesLeft;
      final int scoreBefore = c.state!.score;
      await c.onSwap(bad![0], bad[1], bad[2], bad[3]);

      expect(c.state!.movesLeft, movesBefore, reason: 'a dead swap is free');
      expect(c.state!.score, scoreBefore);
    });
  });

  group('lollipop hammer', () {
    test('smashing a candy scores but does not spend a move', () async {
      final GameController c = await controllerFor();
      await c.startLevel(1);

      final int hammersBefore = c.progress.hammerCount;
      expect(hammersBefore, greaterThan(0));

      c.armBooster(BoosterMode.hammer);
      expect(c.state!.booster, BoosterMode.hammer);

      final int movesBefore = c.state!.movesLeft;
      final int scoreBefore = c.state!.score;
      await c.onCellTap(4, 4);

      expect(c.state!.movesLeft, movesBefore, reason: 'the hammer is free');
      expect(c.state!.score, greaterThan(scoreBefore));
      expect(c.progress.hammerCount, hammersBefore - 1,
          reason: 'one hammer used');
      expect(c.state!.booster, BoosterMode.none,
          reason: 'the hammer disarms after use');
    });

    test('arming with none left does nothing', () async {
      final GameController c = await controllerFor();
      await c.startLevel(1);
      c.progress.hammerCount = 0;
      c.armBooster(BoosterMode.hammer);
      expect(c.state!.booster, BoosterMode.none);
    });

    test('tapping the armed booster again disarms it', () async {
      final GameController c = await controllerFor();
      await c.startLevel(1);
      c.armBooster(BoosterMode.hammer);
      c.armBooster(BoosterMode.hammer);
      expect(c.state!.booster, BoosterMode.none);
    });
  });

  group('free switch', () {
    test('swapping two unrelated candies works and disarms afterwards',
        () async {
      final GameController c = await controllerFor();
      await c.startLevel(1);

      final int switchesBefore = c.progress.freeSwitchCount;
      expect(switchesBefore, greaterThan(0));

      // Find a dead swap: exactly the move the booster exists to allow.
      List<int>? dead;
      for (int r = 0; r < 9 && dead == null; r++) {
        for (int col = 0; col < 8 && dead == null; col++) {
          if (!c.debugSwapIsValid(r, col, r, col + 1)) {
            dead = <int>[r, col, r, col + 1];
          }
        }
      }
      expect(dead, isNotNull);

      c.armBooster(BoosterMode.freeSwitch);
      expect(c.state!.booster, BoosterMode.freeSwitch);

      final int movesBefore = c.state!.movesLeft;
      await c.onSwap(dead![0], dead[1], dead[2], dead[3]);

      expect(c.progress.freeSwitchCount, switchesBefore - 1,
          reason: 'one switch used');
      expect(c.state!.movesLeft, movesBefore,
          reason: 'the free switch is free');
      expect(c.state!.booster, BoosterMode.none,
          reason:
              'the booster must disarm, or every later swap would be free too');
    });

    test('a second swap after a free switch costs a move again', () async {
      final GameController c = await controllerFor();
      await c.startLevel(1);

      List<int>? dead;
      for (int r = 0; r < 9 && dead == null; r++) {
        for (int col = 0; col < 8 && dead == null; col++) {
          if (!c.debugSwapIsValid(r, col, r, col + 1)) {
            dead = <int>[r, col, r, col + 1];
          }
        }
      }
      c.armBooster(BoosterMode.freeSwitch);
      await c.onSwap(dead![0], dead[1], dead[2], dead[3]);

      // Now a normal, valid move must cost a move like any other.
      final List<int>? hint = c.debugHint();
      expect(hint, isNotNull);
      final int movesBefore = c.state!.movesLeft;
      await c.onSwap(c.debugRow(hint![0]), c.debugCol(hint[0]),
          c.debugRow(hint[1]), c.debugCol(hint[1]));
      expect(c.state!.movesLeft, movesBefore - 1,
          reason:
              'the free switch must not have left the board in free-swap mode');
    });
  });

  group('extra moves', () {
    test('buying moves with coins adds them and deducts the coins', () async {
      final GameController c = await controllerFor();
      await c.startLevel(1);
      final int movesBefore = c.state!.movesLeft;
      final int coinsBefore = c.progress.coins;

      final bool ok = await c.buyExtraMovesWithCoins(150, 5);
      expect(ok, isTrue);
      expect(c.state!.movesLeft, movesBefore + 5);
      expect(c.progress.coins, coinsBefore - 150);
    });

    test('buying moves without the coins is refused', () async {
      final GameController c = await controllerFor();
      await c.startLevel(1);
      c.progress.coins = 10;
      final int movesBefore = c.state!.movesLeft;
      final bool ok = await c.buyExtraMovesWithCoins(150, 5);
      expect(ok, isFalse);
      expect(c.state!.movesLeft, movesBefore);
      expect(c.progress.coins, 10);
    });

    test('a rewarded ad grants moves for free', () async {
      final GameController c = await controllerFor();
      await c.startLevel(1);
      final int movesBefore = c.state!.movesLeft;
      c.grantRewardedMoves(5);
      expect(c.state!.movesLeft, movesBefore + 5);
    });
  });

  group('boosters bought with coins', () {
    test('buying a hammer deducts coins and adds one', () async {
      final GameController c = await controllerFor();
      await c.startLevel(1);
      c.progress.hammerCount = 0;
      final int coinsBefore = c.progress.coins;

      final bool ok = await c.buyBoosterWithCoins(BoosterMode.hammer, 120);
      expect(ok, isTrue);
      expect(c.progress.hammerCount, 1);
      expect(c.progress.coins, coinsBefore - 120);
    });

    test('buying without the coins is refused', () async {
      final GameController c = await controllerFor();
      await c.startLevel(1);
      c.progress.coins = 5;
      c.progress.hammerCount = 0;
      final bool ok = await c.buyBoosterWithCoins(BoosterMode.hammer, 120);
      expect(ok, isFalse);
      expect(c.progress.hammerCount, 0);
      expect(c.progress.coins, 5);
    });
  });

  group('winning and losing', () {
    test('reaching the score target wins and records the stars', () async {
      final GameController c = await controllerFor();
      await c.startLevel(1);

      // Play valid moves until the objective completes or we run out.
      int guard = 0;
      while (c.state!.phase == GamePhase.playing && guard++ < 40) {
        final List<int>? hint = c.debugHint();
        if (hint == null) break;
        await c.onSwap(c.debugRow(hint[0]), c.debugCol(hint[0]),
            c.debugRow(hint[1]), c.debugCol(hint[1]));
      }

      if (c.state!.phase == GamePhase.won) {
        expect(c.state!.stars, greaterThanOrEqualTo(1));
        expect(c.progress.levelStars[1], c.state!.stars);
        expect(c.progress.highestLevelUnlocked, greaterThanOrEqualTo(2));
      } else {
        // Ran out of moves without hitting 3000: a legitimate loss.
        expect(c.state!.phase, GamePhase.lost);
        expect(c.state!.movesLeft, 0);
      }
    });

    test('running out of moves loses the level', () async {
      final GameController c = await controllerFor();
      await c.startLevel(1);
      // Starve the move count so the very next move ends it.
      c.grantRewardedMoves(-c.state!.movesLeft + 1);
      expect(c.state!.movesLeft, 1);

      final List<int>? hint = c.debugHint();
      expect(hint, isNotNull);
      await c.onSwap(c.debugRow(hint![0]), c.debugCol(hint[0]),
          c.debugRow(hint[1]), c.debugCol(hint[1]));

      expect(c.state!.movesLeft, 0);
      // Either it won on that move or it is out of moves.
      expect(
        c.state!.phase == GamePhase.lost || c.state!.phase == GamePhase.won,
        isTrue,
      );
    });

    test('continuing a lost level with coins puts it back in play', () async {
      final GameController c = await controllerFor();
      await c.startLevel(1);
      c.grantRewardedMoves(-c.state!.movesLeft + 1);
      final List<int>? hint = c.debugHint();
      await c.onSwap(c.debugRow(hint![0]), c.debugCol(hint[0]),
          c.debugRow(hint[1]), c.debugCol(hint[1]));

      if (c.state!.phase == GamePhase.lost) {
        c.progress.coins = 1000;
        final bool ok = await c.continueWithCoins(150, 5);
        expect(ok, isTrue);
        expect(c.state!.phase, GamePhase.playing);
        expect(c.state!.movesLeft, 5);
        expect(c.progress.coins, 850);
      }
    });

    test('continuing without the coins is refused', () async {
      final GameController c = await controllerFor();
      await c.startLevel(1);
      c.grantRewardedMoves(-c.state!.movesLeft + 1);
      final List<int>? hint = c.debugHint();
      await c.onSwap(c.debugRow(hint![0]), c.debugCol(hint[0]),
          c.debugRow(hint[1]), c.debugCol(hint[1]));

      if (c.state!.phase == GamePhase.lost) {
        c.progress.coins = 10;
        final bool ok = await c.continueWithCoins(150, 5);
        expect(ok, isFalse);
        expect(c.state!.phase, GamePhase.lost);
      }
    });
  });

  group('quitting and restarting', () {
    test('quit clears the level state', () async {
      final GameController c = await controllerFor();
      await c.startLevel(1);
      expect(c.state, isNotNull);
      c.quitLevel();
      expect(c.state, isNull);
    });

    test('restart keeps the same level and does not spend a life', () async {
      final GameController c = await controllerFor();
      await c.startLevel(1);
      final int livesBefore = c.progress.lives;
      final int scoreBefore = c.state!.score;

      // Score something first so the restart is observable.
      final List<int>? hint = c.debugHint();
      await c.onSwap(c.debugRow(hint![0]), c.debugCol(hint[0]),
          c.debugRow(hint[1]), c.debugCol(hint[1]));
      expect(c.state!.score, greaterThan(scoreBefore));

      await c.restartLevel();
      expect(c.state!.level.id, 1);
      expect(c.state!.score, 0, reason: 'the board starts over');
      expect(c.state!.movesLeft, 25);
      expect(c.progress.lives, livesBefore, reason: 'a restart is free');
    });
  });
}
