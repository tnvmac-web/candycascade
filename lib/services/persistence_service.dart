import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Everything about the player that has to survive an app restart.
class PlayerProgress {
  PlayerProgress({
    this.highestLevelUnlocked = 1,
    this.coins = 500,
    this.lives = maxLives,
    this.lastLifeAt,
    this.soundOn = true,
    this.musicOn = true,
    this.hapticsOn = true,
    this.adsRemoved = false,
    this.hammerCount = 1,
    this.freeSwitchCount = 1,
    this.extraMovesCount = 1,
    this.startBombCount = 1,
    this.totalStars = 0,
  });

  static const int maxLives = 5;

  /// 20 minutes per life, in milliseconds.
  static const int lifeRegenMs = 20 * 60 * 1000;

  int highestLevelUnlocked;
  int coins;
  int lives;

  /// When the next life is due. Null means the bar is full.
  int? lastLifeAt;

  bool soundOn;
  bool musicOn;
  bool hapticsOn;
  bool adsRemoved;

  int hammerCount;
  int freeSwitchCount;
  int extraMovesCount;
  int startBombCount;

  int totalStars;

  /// Stars per level id, so the level map can show earned stars.
  Map<int, int> levelStars = <int, int>{};

  bool get livesFull => lives >= maxLives;

  /// Milliseconds until the next life arrives, or 0 when full.
  int msToNextLife([DateTime? now]) {
    if (livesFull || lastLifeAt == null) return 0;
    final int nowMs = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final int due = lastLifeAt! + lifeRegenMs;
    final int delta = due - nowMs;
    return delta > 0 ? delta : 0;
  }

  /// Applies offline life regeneration. Returns true when anything changed.
  ///
  /// This is the only place time is consumed, so calling it on resume, on
  /// launch, and on a tick gives the same answer no matter how often it runs.
  bool regenerateLives([DateTime? now]) {
    if (livesFull) {
      lastLifeAt = null;
      return false;
    }
    final DateTime t = now ?? DateTime.now();
    final int nowMs = t.millisecondsSinceEpoch;
    if (lastLifeAt == null) {
      lastLifeAt = nowMs;
      return true;
    }
    bool changed = false;
    while (lives < maxLives) {
      final int due = lastLifeAt! + lifeRegenMs;
      if (nowMs < due) break;
      lives++;
      changed = true;
      if (lives >= maxLives) {
        lastLifeAt = null;
      } else {
        lastLifeAt = due;
      }
    }
    return changed;
  }

  /// Spends one life. Returns false when the player has none.
  bool spendLife([DateTime? now]) {
    if (lives <= 0) return false;
    if (livesFull) {
      lastLifeAt = (now ?? DateTime.now()).millisecondsSinceEpoch;
    }
    lives--;
    return true;
  }

  void refillLives([DateTime? now]) {
    lives = maxLives;
    lastLifeAt = null;
  }

  void addLife([DateTime? now]) {
    if (lives >= maxLives) return;
    lives++;
    if (lives >= maxLives) lastLifeAt = null;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'highestLevelUnlocked': highestLevelUnlocked,
        'coins': coins,
        'lives': lives,
        'lastLifeAt': lastLifeAt,
        'soundOn': soundOn,
        'musicOn': musicOn,
        'hapticsOn': hapticsOn,
        'adsRemoved': adsRemoved,
        'hammerCount': hammerCount,
        'freeSwitchCount': freeSwitchCount,
        'extraMovesCount': extraMovesCount,
        'startBombCount': startBombCount,
        'totalStars': totalStars,
        'levelStars':
            levelStars.map((int k, int v) => MapEntry<String, int>('$k', v)),
      };

  static PlayerProgress fromJson(Map<String, dynamic> j) {
    final PlayerProgress p = PlayerProgress(
      highestLevelUnlocked: j['highestLevelUnlocked'] as int? ?? 1,
      coins: j['coins'] as int? ?? 500,
      lives: j['lives'] as int? ?? maxLives,
      lastLifeAt: j['lastLifeAt'] as int?,
      soundOn: j['soundOn'] as bool? ?? true,
      musicOn: j['musicOn'] as bool? ?? true,
      hapticsOn: j['hapticsOn'] as bool? ?? true,
      adsRemoved: j['adsRemoved'] as bool? ?? false,
      hammerCount: j['hammerCount'] as int? ?? 1,
      freeSwitchCount: j['freeSwitchCount'] as int? ?? 1,
      extraMovesCount: j['extraMovesCount'] as int? ?? 1,
      startBombCount: j['startBombCount'] as int? ?? 1,
      totalStars: j['totalStars'] as int? ?? 0,
    );
    final Map<String, dynamic>? stars =
        j['levelStars'] as Map<String, dynamic>?;
    if (stars != null) {
      p.levelStars = stars.map(
          (String k, dynamic v) => MapEntry<int, int>(int.parse(k), v as int));
    }
    return p;
  }
}

/// Thin wrapper over [SharedPreferences].
///
/// Reads once at startup into memory and writes back on every mutation, so the
/// rest of the app never awaits a disk hit.
class PersistenceService {
  PersistenceService(this._prefs);

  static const String _key = 'candy_cascade.progress.v1';

  final SharedPreferences _prefs;
  PlayerProgress _progress = PlayerProgress();

  PlayerProgress get progress => _progress;

  static Future<PersistenceService> open() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final PersistenceService service = PersistenceService(prefs);
    service._load();
    return service;
  }

  void _load() {
    final String? raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) {
      _progress = PlayerProgress();
      _progress.regenerateLives();
      return;
    }
    try {
      final Map<String, dynamic> j = jsonDecode(raw) as Map<String, dynamic>;
      _progress = PlayerProgress.fromJson(j);
    } catch (_) {
      _progress = PlayerProgress();
    }
    // Catch up on any lives earned while the app was closed.
    _progress.regenerateLives();
  }

  Future<void> save() async {
    await _prefs.setString(_key, jsonEncode(_progress.toJson()));
  }

  Future<void> resetAll() async {
    _progress = PlayerProgress();
    _progress.regenerateLives();
    await save();
  }

  /// Convenience used by the level map: best stars earned on a level.
  int starsFor(int levelId) => _progress.levelStars[levelId] ?? 0;

  /// Records a result, keeping the best star count. Returns the new total.
  Future<int> recordLevelResult({
    required int levelId,
    required int stars,
    required int coinsEarned,
  }) async {
    final int previous = _progress.levelStars[levelId] ?? 0;
    if (stars > previous) {
      _progress.totalStars += stars - previous;
      _progress.levelStars[levelId] = stars;
    }
    _progress.coins += coinsEarned;
    if (levelId >= _progress.highestLevelUnlocked) {
      _progress.highestLevelUnlocked = levelId + 1;
    }
    await save();
    return stars;
  }
}
