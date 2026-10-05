import 'package:candy_cascade/services/persistence_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Verifies that a level result survives a round trip through storage.
///
/// This is the path the level map reads when it draws the stars under each
/// level node, so a bug here shows up as stars that never appear.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('a fresh install starts with the documented defaults', () async {
    final PersistenceService p = await PersistenceService.open();
    expect(p.progress.highestLevelUnlocked, 1);
    expect(p.progress.coins, 500);
    expect(p.progress.lives, PlayerProgress.maxLives);
    expect(p.progress.totalStars, 0);
    expect(p.starsFor(1), 0);
  });

  test('recording a win stores the stars, coins and next level', () async {
    final PersistenceService p = await PersistenceService.open();

    await p.recordLevelResult(levelId: 1, stars: 2, coinsEarned: 77);

    expect(p.starsFor(1), 2,
        reason: 'stars for level 1 must be readable straight back');
    expect(p.progress.totalStars, 2);
    expect(p.progress.coins, 577);
    expect(p.progress.highestLevelUnlocked, 2);
  });

  test('the recorded result survives a reload from disk', () async {
    final PersistenceService first = await PersistenceService.open();
    await first.recordLevelResult(levelId: 1, stars: 2, coinsEarned: 77);

    // A second service reads whatever the first one wrote.
    final PersistenceService second = await PersistenceService.open();
    expect(second.starsFor(1), 2);
    expect(second.progress.totalStars, 2);
    expect(second.progress.coins, 577);
    expect(second.progress.highestLevelUnlocked, 2);
  });

  test('a worse replay does not overwrite a better score', () async {
    final PersistenceService p = await PersistenceService.open();
    await p.recordLevelResult(levelId: 3, stars: 3, coinsEarned: 100);
    await p.recordLevelResult(levelId: 3, stars: 1, coinsEarned: 10);

    expect(p.starsFor(3), 3, reason: 'the best star count must be kept');
    expect(p.progress.totalStars, 3);
    // Coins are earned every time, only the stars are best of.
    expect(p.progress.coins, 500 + 100 + 10);
  });

  test('a better replay raises the star count and the total', () async {
    final PersistenceService p = await PersistenceService.open();
    await p.recordLevelResult(levelId: 2, stars: 1, coinsEarned: 0);
    expect(p.progress.totalStars, 1);

    await p.recordLevelResult(levelId: 2, stars: 3, coinsEarned: 0);
    expect(p.starsFor(2), 3);
    expect(p.progress.totalStars, 3,
        reason: 'total must move by the delta only');
  });

  test('unlocking never goes backwards', () async {
    final PersistenceService p = await PersistenceService.open();
    await p.recordLevelResult(levelId: 5, stars: 1, coinsEarned: 0);
    expect(p.progress.highestLevelUnlocked, 6);

    // Replaying an early level must not lock the later ones again.
    await p.recordLevelResult(levelId: 1, stars: 1, coinsEarned: 0);
    expect(p.progress.highestLevelUnlocked, 6);
  });

  test('lives regenerate across a simulated absence', () async {
    final PersistenceService p = await PersistenceService.open();
    p.progress.lives = 2;
    p.progress.lastLifeAt = DateTime.now()
        .subtract(const Duration(minutes: 45))
        .millisecondsSinceEpoch;
    await p.save();

    final PersistenceService reloaded = await PersistenceService.open();
    // 45 minutes is two full 20 minute cycles.
    expect(reloaded.progress.lives, 4);
  });

  test('a very long absence fills the bar and clears the timer', () async {
    final PersistenceService p = await PersistenceService.open();
    p.progress.lives = 1;
    p.progress.lastLifeAt = DateTime.now()
        .subtract(const Duration(hours: 8))
        .millisecondsSinceEpoch;
    await p.save();

    final PersistenceService reloaded = await PersistenceService.open();
    expect(reloaded.progress.lives, PlayerProgress.maxLives);
    expect(reloaded.progress.lastLifeAt, isNull);
  });

  test('a full bar never reports a pending life', () async {
    final PersistenceService p = await PersistenceService.open();
    expect(p.progress.livesFull, isTrue);
    expect(p.progress.msToNextLife(), 0);
  });

  test('spending a life starts the timer only from a full bar', () async {
    final PersistenceService p = await PersistenceService.open();
    expect(p.progress.spendLife(), isTrue);
    expect(p.progress.lives, PlayerProgress.maxLives - 1);
    expect(p.progress.lastLifeAt, isNotNull,
        reason: 'the first life lost starts the clock');

    final int? firstStamp = p.progress.lastLifeAt;
    expect(p.progress.spendLife(), isTrue);
    expect(p.progress.lastLifeAt, firstStamp,
        reason: 'the clock must not restart on each loss');
  });

  test('the sound, music and haptic toggles round trip', () async {
    final PersistenceService p = await PersistenceService.open();
    p.progress.soundOn = false;
    p.progress.musicOn = false;
    p.progress.hapticsOn = false;
    p.progress.adsRemoved = true;
    await p.save();

    final PersistenceService reloaded = await PersistenceService.open();
    expect(reloaded.progress.soundOn, isFalse);
    expect(reloaded.progress.musicOn, isFalse);
    expect(reloaded.progress.hapticsOn, isFalse);
    expect(reloaded.progress.adsRemoved, isTrue);
  });

  test('booster counts round trip', () async {
    final PersistenceService p = await PersistenceService.open();
    p.progress.hammerCount = 7;
    p.progress.freeSwitchCount = 4;
    p.progress.extraMovesCount = 2;
    p.progress.startBombCount = 3;
    await p.save();

    final PersistenceService reloaded = await PersistenceService.open();
    expect(reloaded.progress.hammerCount, 7);
    expect(reloaded.progress.freeSwitchCount, 4);
    expect(reloaded.progress.extraMovesCount, 2);
    expect(reloaded.progress.startBombCount, 3);
  });

  test('a reset clears progress but the defaults come back', () async {
    final PersistenceService p = await PersistenceService.open();
    await p.recordLevelResult(levelId: 4, stars: 3, coinsEarned: 500);
    expect(p.starsFor(4), 3);

    await p.resetAll();
    expect(p.starsFor(4), 0);
    expect(p.progress.coins, 500);
    expect(p.progress.highestLevelUnlocked, 1);
  });

  test('corrupt stored json falls back to defaults instead of throwing',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'candy_cascade.progress.v1': 'not json at all {{{',
    });
    final PersistenceService p = await PersistenceService.open();
    expect(p.progress.coins, 500);
    expect(p.progress.highestLevelUnlocked, 1);
  });
}
