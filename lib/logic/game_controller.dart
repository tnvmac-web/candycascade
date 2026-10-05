import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/candy_tile.dart';
import '../models/level_data.dart';
import '../services/audio_service.dart';
import '../services/iap_service.dart';
import '../services/persistence_service.dart';
import 'match_engine.dart';

/// Which booster is armed and waiting for a tap on the board.
enum BoosterMode { none, hammer, freeSwitch }

/// Phase of a single level attempt.
enum GamePhase { ready, playing, resolving, won, lost }

/// A visual request the view layer should animate. The controller does not know
/// how to draw, it only says what happened.
class EffectRequest {
  EffectRequest({
    required this.cleared,
    required this.blasts,
    required this.spawns,
    required this.comboMessage,
    required this.cascadeIndex,
    required this.score,
  });

  final List<ClearedCandy> cleared;
  final Set<int> blasts;
  final List<SpecialSpawn> spawns;
  final String? comboMessage;
  final int cascadeIndex;
  final int score;
}

/// Immutable snapshot of the level in progress, consumed by the board view.
class GameState {
  const GameState({
    required this.level,
    required this.board,
    required this.phase,
    required this.score,
    required this.movesLeft,
    required this.blockersLeft,
    required this.jelliesDropped,
    required this.jelliesOnBoard,
    required this.objectives,
    required this.booster,
    required this.busy,
    this.comboMessage,
    this.lastDrops = const <DropRecord>[],
    this.effects,
    this.shuffleCount = 0,
    this.hint,
  });

  final LevelData level;

  /// Flat board, row major. Null means an empty cell mid animation.
  final List<CandyTile?> board;

  final GamePhase phase;
  final int score;
  final int movesLeft;
  final int blockersLeft;
  final int jelliesDropped;
  final int jelliesOnBoard;
  final List<LevelObjective> objectives;
  final BoosterMode booster;

  /// True while candies are falling or a cascade is resolving, so input is
  /// ignored.
  final bool busy;

  final String? comboMessage;

  /// Candies that moved on the last gravity step, for the fall tween.
  final List<DropRecord> lastDrops;

  /// The most recent clear, for the particle burst.
  final EffectRequest? effects;

  final int shuffleCount;

  /// Two cell indices the player could swap, drawn as a gentle pulse.
  final List<int>? hint;

  int get rows => level.rows;
  int get cols => level.cols;

  CandyTile? at(int row, int col) => board[row * cols + col];

  CandyTile? atIdx(int index) =>
      index >= 0 && index < board.length ? board[index] : null;

  BlockerCell? blockerFor(int row, int col) {
    for (final BlockerCell b in level.blockers) {
      if (b.row == row && b.col == col) return b;
    }
    return null;
  }

  int get stars => level.stars.starsFor(score);

  double get objectiveRatio {
    if (objectives.isEmpty) return 1.0;
    double sum = 0;
    for (final LevelObjective o in objectives) {
      sum += o.ratio;
    }
    return sum / objectives.length;
  }

  bool get allObjectivesDone =>
      objectives.every((LevelObjective o) => o.isComplete);

  GameState copyWith({
    LevelData? level,
    List<CandyTile?>? board,
    GamePhase? phase,
    int? score,
    int? movesLeft,
    int? blockersLeft,
    int? jelliesDropped,
    int? jelliesOnBoard,
    List<LevelObjective>? objectives,
    BoosterMode? booster,
    bool? busy,
    String? comboMessage,
    List<DropRecord>? lastDrops,
    EffectRequest? effects,
    int? shuffleCount,
    List<int>? hint,
  }) {
    return GameState(
      level: level ?? this.level,
      board: board ?? this.board,
      phase: phase ?? this.phase,
      score: score ?? this.score,
      movesLeft: movesLeft ?? this.movesLeft,
      blockersLeft: blockersLeft ?? this.blockersLeft,
      jelliesDropped: jelliesDropped ?? this.jelliesDropped,
      jelliesOnBoard: jelliesOnBoard ?? this.jelliesOnBoard,
      objectives: objectives ?? this.objectives,
      booster: booster ?? this.booster,
      busy: busy ?? this.busy,
      comboMessage: comboMessage,
      lastDrops: lastDrops ?? this.lastDrops,
      effects: effects,
      shuffleCount: shuffleCount ?? this.shuffleCount,
      hint: hint,
    );
  }
}

/// The rules coordinator. Owns the [MatchEngine], the move counter, the
/// objectives, and the timers that drive cascades and life regeneration.
class GameController extends StateNotifier<GameState?> {
  GameController({
    required PersistenceService persistence,
    required IapService iap,
  })  : _persistence = persistence,
        _iap = iap,
        super(null);

  final PersistenceService _persistence;

  /// Kept so future purchase aware logic (for example gating a level behind the
  /// Remove Ads product) has a single place to reach the store from.
  // ignore: unused_field
  final IapService _iap;

  MatchEngine? _engine;
  Timer? _lifeTimer;
  Timer? _hintTimer;
  final Random _rng = Random();

  /// Guards against a second swap landing while a cascade is mid flight.
  bool _animating = false;

  /// Rows the view should treat as "spawned above the board" when tweening in.
  int get rows => _engine?.rows ?? 9;
  int get cols => _engine?.cols ?? 9;

  PlayerProgress get progress => _persistence.progress;

  // ---------------------------------------------------------------------------
  // Level lifecycle
  // ---------------------------------------------------------------------------

  /// Starts a level. [spendLife] is false when continuing a level the player
  /// already paid for, or when a booster/level start should not cost a life.
  Future<bool> startLevel(int levelId,
      {bool spendLife = true, bool useStartBomb = false}) async {
    final PlayerProgress p = _persistence.progress;
    if (spendLife) {
      if (!p.spendLife()) {
        return false;
      }
      await _persistence.save();
    }

    final LevelData level = LevelRepository.levelFor(levelId);
    _engine = MatchEngine(
      rows: level.rows,
      cols: level.cols,
      colorCount: level.colorCount,
      blockedCells: Set<int>.from(level.blockedCells),
      blockers: level.blockers,
      seed: level.seed,
    );
    _engine!.generateBoard();

    if (useStartBomb && p.startBombCount > 0) {
      final int? cell = _engine!.randomCandyCell();
      if (cell != null) {
        final CandyTile? t = _engine!.tileAtIdx(cell);
        if (t != null) {
          t.special = SpecialType.rainbow;
          t.color = CandyColorType.none;
          p.startBombCount--;
          await _persistence.save();
        }
      }
    }

    // Seed ingredient levels with their jelly tokens near the top.
    for (int i = 0; i < level.jellyCount; i++) {
      final int col = level.ingredientDropColumn == null
          ? _rng.nextInt(level.cols)
          : ((level.ingredientDropColumn! + i) % level.cols);
      _engine!.spawnJelly(col);
    }

    final List<LevelObjective> objectives = level.objectives
        .map((LevelObjective o) => o.copyWith(progress: 0))
        .toList();

    state = GameState(
      level: level,
      board: List<CandyTile?>.from(_engine!.cells),
      phase: GamePhase.playing,
      score: 0,
      movesLeft: level.moves,
      blockersLeft: _engine!.blockerCount,
      jelliesDropped: 0,
      jelliesOnBoard: _engine!.jellyOnBoard,
      objectives: objectives,
      booster: BoosterMode.none,
      busy: false,
    );

    _startHintTimer();
    return true;
  }

  /// Abandons the level without a result.
  void quitLevel() {
    _stopTimers();
    _engine = null;
    state = null;
  }

  // ---------------------------------------------------------------------------
  // Board interaction
  // ---------------------------------------------------------------------------

  /// The player dragged from one cell to an adjacent one.
  Future<void> onSwap(int r1, int c1, int r2, int c2) async {
    final GameState? s = state;
    final MatchEngine? engine = _engine;
    if (s == null || engine == null) return;
    if (s.phase != GamePhase.playing || _animating) return;
    if (!engine.areAdjacent(r1, c1, r2, c2)) return;

    final CandyTile? a = engine.tileAt(r1, c1);
    final CandyTile? b = engine.tileAt(r2, c2);
    if (a == null || b == null) return;

    // Free switch booster: swap anything, no match needed.
    if (s.booster == BoosterMode.freeSwitch) {
      // Disarm first. _consumeBooster only decrements the saved count, so the
      // booster mode has to be cleared here or it would stay armed and every
      // later swap in the level would also be free.
      state = s.copyWith(booster: BoosterMode.none);
      engine.rawSwap(r1, c1, r2, c2);
      _consumeBooster(BoosterMode.freeSwitch);
      _hapticLight();
      _publish(boardOnly: true);
      await _resolveBoard(consumeMove: false, force: true);
      return;
    }

    _hapticLight();
    AudioService.instance.play(Sfx.swap);

    final SwapOutcome outcome = engine.applySwap(r1, c1, r2, c2);
    if (!outcome.valid) {
      AudioService.instance.play(Sfx.invalidSwap);
      _hapticMedium();
      // The engine already reverted; just republish so the view snaps back.
      _publish(boardOnly: true);
      return;
    }

    if (outcome.message != null && outcome.message!.isNotEmpty) {
      _hapticHeavy();
    }

    _publish(boardOnly: true);
    await _resolveBoard(
      consumeMove: true,
      comboSeed: outcome.comboSeed,
      rainbowTarget: outcome.rainbowTarget,
      comboMessage: outcome.message,
    );
  }

  /// The player tapped a cell while a booster was armed.
  Future<void> onCellTap(int row, int col) async {
    final GameState? s = state;
    final MatchEngine? engine = _engine;
    if (s == null || engine == null) return;
    if (s.phase != GamePhase.playing || _animating) return;

    if (s.booster == BoosterMode.hammer) {
      final int idx = engine.indexOf(row, col);
      final ClearedCandy? removed = engine.smash(idx);
      if (removed == null) return;
      _consumeBooster(BoosterMode.hammer);
      AudioService.instance.play(Sfx.special);
      _hapticHeavy();
      state = state!.copyWith(
        effects: EffectRequest(
          cleared: <ClearedCandy>[removed],
          blasts: const <int>{},
          spawns: const <SpecialSpawn>[],
          comboMessage: null,
          cascadeIndex: 0,
          score: ScoreRules.perCandy,
        ),
        score: state!.score + ScoreRules.perCandy,
        booster: BoosterMode.none,
      );
      // A hammer hit does not cost a move, but gravity and cascades still run.
      await _resolveBoard(consumeMove: false, force: true);
    }
  }

  void armBooster(BoosterMode mode) {
    final GameState? s = state;
    if (s == null || s.phase != GamePhase.playing) return;
    final PlayerProgress p = _persistence.progress;
    final int available =
        mode == BoosterMode.hammer ? p.hammerCount : p.freeSwitchCount;
    if (available <= 0) return;
    AudioService.instance.hapticSelection();
    state = s.copyWith(booster: s.booster == mode ? BoosterMode.none : mode);
  }

  void cancelBooster() {
    final GameState? s = state;
    if (s == null) return;
    state = s.copyWith(booster: BoosterMode.none);
  }

  void _consumeBooster(BoosterMode mode) {
    final PlayerProgress p = _persistence.progress;
    if (mode == BoosterMode.hammer && p.hammerCount > 0) {
      p.hammerCount--;
    } else if (mode == BoosterMode.freeSwitch && p.freeSwitchCount > 0) {
      p.freeSwitchCount--;
    }
    unawaited(_persistence.save());
  }

  // ---------------------------------------------------------------------------
  // The cascade loop
  // ---------------------------------------------------------------------------

  /// Runs match, clear, gravity, refill until the board is quiet, then checks
  /// the level result. This is the heart of the game.
  Future<void> _resolveBoard({
    required bool consumeMove,
    Set<int> comboSeed = const <int>{},
    CandyColorType? rainbowTarget,
    String? comboMessage,
    bool force = false,
  }) async {
    final MatchEngine? engine = _engine;
    if (engine == null || state == null) return;

    _animating = true;
    state = state!.copyWith(busy: true, comboMessage: comboMessage);
    await _persistBoard();

    int cascadeIndex = 0;
    final Set<int> accumulatedCleared = <int>{};
    final List<ClearedCandy> accumulatedRemoved = <ClearedCandy>[];
    final Set<int> accumulatedBlasts = <int>{};
    final List<SpecialSpawn> accumulatedSpawns = <SpecialSpawn>[];
    bool first = true;

    while (cascadeIndex < 40) {
      final List<MatchGroup> matches = engine.findMatches();
      if (matches.isEmpty && comboSeed.isEmpty && !first) break;
      if (matches.isEmpty && comboSeed.isEmpty) {
        // Nothing to do at all (for example a hammer hit that made no match).
        break;
      }

      final ClearPlan plan = engine.buildPlan(
        matches,
        comboSeed: first ? comboSeed : const <int>{},
        rainbowTarget: rainbowTarget,
        cascadeIndex: cascadeIndex,
      );
      first = false;

      if (plan.isEmpty) break;

      // Crack frosting next to everything that is about to clear.
      final int broken = engine.crackBlockers(plan.cells);
      accumulatedCleared.addAll(plan.cells);
      accumulatedBlasts.addAll(plan.blasts);
      accumulatedSpawns.addAll(plan.spawns);

      final List<ClearedCandy> removed = engine.applyClear(plan);
      accumulatedRemoved.addAll(removed);

      // Play a sound for what just happened, loudest special wins.
      _playClearSound(plan);

      state = state!.copyWith(
        board: List<CandyTile?>.from(engine.cells),
        score: state!.score + plan.score + broken * ScoreRules.blockerBonus,
        blockersLeft: engine.blockerCount,
        effects: EffectRequest(
          cleared: removed,
          blasts: plan.blasts,
          spawns: plan.spawns,
          comboMessage: cascadeIndex == 0 ? comboMessage : null,
          cascadeIndex: cascadeIndex,
          score: plan.score,
        ),
      );

      // Let the view play the burst before candies fall.
      await Future<void>.delayed(const Duration(milliseconds: 110));

      final List<DropRecord> drops = engine.applyGravity();
      engine.refill();

      state = state!.copyWith(
        board: List<CandyTile?>.from(engine.cells),
        lastDrops: drops,
      );

      // Jelly tokens that reached the bottom row are collected.
      _collectJellies();

      await Future<void>.delayed(const Duration(milliseconds: 170));

      cascadeIndex++;
      if (cascadeIndex > 1) {
        AudioService.instance.play(Sfx.cascade, throttle: true);
        if (cascadeIndex >= 2) {
          final String voice = ComboVoice.forCascade(cascadeIndex - 1);
          state = state!.copyWith(comboMessage: voice);
          AudioService.instance.hapticCombo(cascadeIndex - 1);
        }
      }
    }

    // The board is quiet. Make sure it is still solvable.
    int shuffleCount = state!.shuffleCount;
    if (engine.ensurePlayable()) {
      shuffleCount++;
      state = state!.copyWith(
        board: List<CandyTile?>.from(engine.cells),
        shuffleCount: shuffleCount,
        comboMessage: 'No moves left, reshuffling!',
      );
      await Future<void>.delayed(const Duration(milliseconds: 260));
    }

    // Update the score objective from the running total.
    _syncObjectives();

    int moves = state!.movesLeft;
    if (consumeMove) {
      moves = (moves - 1).clamp(0, 999);
    }

    state = state!.copyWith(
      movesLeft: moves,
      busy: false,
      jelliesOnBoard: engine.jellyOnBoard,
    );
    _animating = false;
    await _persistBoard();

    await _checkResult();
  }

  void _playClearSound(ClearPlan plan) {
    bool hasRainbow = false;
    bool hasBomb = false;
    bool hasRocket = false;
    for (final int idx in plan.blasts) {
      final CandyTile? t = _engine?.tileAtIdx(idx);
      if (t == null) continue;
      if (t.isRainbow) hasRainbow = true;
      if (t.isWrapped) hasBomb = true;
      if (t.isStriped) hasRocket = true;
    }
    if (hasRainbow) {
      AudioService.instance.play(Sfx.rainbow);
      AudioService.instance.hapticHeavy();
    } else if (hasBomb) {
      AudioService.instance.play(Sfx.bomb);
      AudioService.instance.hapticMedium();
    } else if (hasRocket) {
      AudioService.instance.play(Sfx.rocket);
      AudioService.instance.hapticLight();
    } else {
      AudioService.instance.play(Sfx.match);
    }
  }

  /// Moves any jelly token that has reached the bottom row off the board and
  /// counts it toward the objective.
  void _collectJellies() {
    final MatchEngine? engine = _engine;
    final GameState? s = state;
    if (engine == null || s == null) return;

    for (int c = 0; c < engine.cols; c++) {
      // Find the lowest playable row in this column.
      int bottom = -1;
      for (int r = engine.rows - 1; r >= 0; r--) {
        if (engine.isHole(r, c)) continue;
        bottom = r;
        break;
      }
      if (bottom < 0) continue;
      final CandyTile? t = engine.tileAt(bottom, c);
      if (t == null || !t.isJelly) continue;

      engine.cells[engine.indexOf(bottom, c)] = null;
      final int dropped = s.jelliesDropped + 1;
      AudioService.instance.play(Sfx.star);
      AudioService.instance.hapticHeavy();
      state = s.copyWith(
        jelliesDropped: dropped,
        score: s.score + ScoreRules.jellyBonus,
        board: List<CandyTile?>.from(engine.cells),
      );
    }
  }

  void _syncObjectives() {
    final GameState? s = state;
    if (s == null) return;
    final List<LevelObjective> updated = <LevelObjective>[];
    for (final LevelObjective o in s.objectives) {
      switch (o.type) {
        case ObjectiveType.score:
          updated.add(o.copyWith(progress: s.score));
          break;
        case ObjectiveType.ingredient:
          updated.add(o.copyWith(progress: s.jelliesDropped));
          break;
        case ObjectiveType.frosting:
          final int total = s.level.blockers.length;
          updated.add(o.copyWith(progress: total - s.blockersLeft));
          break;
      }
    }
    state = s.copyWith(objectives: updated);
  }

  // ---------------------------------------------------------------------------
  // Result
  // ---------------------------------------------------------------------------

  Future<void> _checkResult() async {
    final GameState? s = state;
    if (s == null) return;
    _syncObjectives();
    final GameState current = state!;

    if (current.allObjectivesDone) {
      await _win();
      return;
    }
    if (current.movesLeft <= 0) {
      await _lose();
    }
  }

  Future<void> _win() async {
    _stopTimers();
    final GameState s = state!;
    final int stars = s.level.stars.starsFor(s.score);
    final int coins = _coinReward(stars, s.score);
    AudioService.instance.play(Sfx.win);
    AudioService.instance.hapticHeavy();
    state = s.copyWith(phase: GamePhase.won);
    await _persistence.recordLevelResult(
      levelId: s.level.id,
      stars: stars,
      coinsEarned: coins,
    );
  }

  Future<void> _lose() async {
    _stopTimers();
    AudioService.instance.play(Sfx.lose);
    AudioService.instance.hapticMedium();
    state = state!.copyWith(phase: GamePhase.lost);
  }

  /// Coins awarded for a win: a base, a star bonus, and a score bonus.
  int _coinReward(int stars, int score) {
    const int base = 25;
    final int starBonus = stars * 20;
    final int scoreBonus = (score / 500).floor().clamp(0, 100);
    return base + starBonus + scoreBonus;
  }

  /// Continues a lost level by spending coins, keeping the board as it is.
  Future<bool> continueWithCoins(int cost, int extraMoves) async {
    final GameState? s = state;
    final PlayerProgress p = _persistence.progress;
    if (s == null || s.phase != GamePhase.lost) return false;
    if (p.coins < cost) return false;
    p.coins -= cost;
    await _persistence.save();
    state = s.copyWith(
      phase: GamePhase.playing,
      movesLeft: extraMoves,
      comboMessage: '+$extraMoves moves!',
    );
    _startHintTimer();
    return true;
  }

  /// Grants extra moves from a rewarded ad. Only call after the ad reports the
  /// reward was earned.
  void grantRewardedMoves(int moves) {
    final GameState? s = state;
    if (s == null) return;
    state = s.copyWith(
      movesLeft: s.movesLeft + moves,
      phase: s.phase == GamePhase.lost ? GamePhase.playing : s.phase,
      comboMessage: '+$moves moves!',
    );
    if (s.phase == GamePhase.lost) _startHintTimer();
  }

  /// Grants a free booster from a rewarded ad or a purchase.
  Future<void> grantBooster(BoosterMode mode, {int count = 1}) async {
    final PlayerProgress p = _persistence.progress;
    if (mode == BoosterMode.hammer) {
      p.hammerCount += count;
    } else if (mode == BoosterMode.freeSwitch) {
      p.freeSwitchCount += count;
    }
    await _persistence.save();
    state = state?.copyWith(booster: BoosterMode.none);
  }

  /// Restarts the current level without spending a life.
  Future<void> restartLevel() async {
    final GameState? s = state;
    if (s == null) return;
    await startLevel(s.level.id, spendLife: false);
  }

  Future<void> nextLevel() async {
    final GameState? s = state;
    if (s == null) return;
    await startLevel(s.level.id + 1, spendLife: true);
  }

  // ---------------------------------------------------------------------------
  // Boosters bought with coins
  // ---------------------------------------------------------------------------

  Future<bool> buyBoosterWithCoins(BoosterMode mode, int cost) async {
    final PlayerProgress p = _persistence.progress;
    if (p.coins < cost) return false;
    p.coins -= cost;
    await grantBooster(mode);
    return true;
  }

  Future<bool> buyExtraMovesWithCoins(int cost, int moves) async {
    final GameState? s = state;
    final PlayerProgress p = _persistence.progress;
    if (s == null || p.coins < cost) return false;
    p.coins -= cost;
    await _persistence.save();
    state = s.copyWith(movesLeft: s.movesLeft + moves);
    return true;
  }

  // ---------------------------------------------------------------------------
  // Hint
  // ---------------------------------------------------------------------------

  void _startHintTimer() {
    _hintTimer?.cancel();
    _hintTimer = Timer.periodic(const Duration(seconds: 6), (Timer t) {
      final GameState? s = state;
      final MatchEngine? engine = _engine;
      if (s == null || engine == null) return;
      if (s.phase != GamePhase.playing || s.busy || _animating) return;
      final List<int>? hint = engine.findHint();
      if (hint != null) {
        state = s.copyWith(hint: hint);
        Timer(const Duration(milliseconds: 1600), () {
          if (state != null && mounted) state = state!.copyWith(hint: null);
        });
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Lives
  // ---------------------------------------------------------------------------

  /// Ticks offline life regeneration and pushes a new state so the HUD updates.
  void startLifeTimer(VoidCallback onChanged) {
    _lifeTimer?.cancel();
    _lifeTimer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      final bool changed = _persistence.progress.regenerateLives();
      if (changed) {
        unawaited(_persistence.save());
      }
      onChanged();
    });
  }

  void refreshLives() {
    if (_persistence.progress.regenerateLives()) {
      unawaited(_persistence.save());
    }
  }

  Future<void> refillLives() async {
    _persistence.progress.refillLives();
    await _persistence.save();
  }

  // ---------------------------------------------------------------------------
  // Plumbing
  // ---------------------------------------------------------------------------

  void _publish({bool boardOnly = false}) {
    final GameState? s = state;
    final MatchEngine? engine = _engine;
    if (s == null || engine == null) return;
    state = s.copyWith(board: List<CandyTile?>.from(engine.cells));
  }

  Future<void> _persistBoard() async {
    // Board persistence is intentionally light: the level restarts cleanly from
    // its seed, so only the meta progression is written to disk.
    await _persistence.save();
  }

  void _hapticLight() => AudioService.instance.hapticLight();
  void _hapticMedium() => AudioService.instance.hapticMedium();
  void _hapticHeavy() => AudioService.instance.hapticHeavy();

  // ---------------------------------------------------------------------------
  // Test seams
  //
  // Small read only accessors so tests can drive the controller without
  // reaching into its private engine. They are cheap and have no side effects.
  // ---------------------------------------------------------------------------

  /// The engine's hint, as two cell indices, or null when the board is dead.
  List<int>? debugHint() => _engine?.findHint();

  int debugRow(int index) => _engine?.rowOf(index) ?? 0;

  int debugCol(int index) => _engine?.colOf(index) ?? 0;

  /// Whether a swap between two cells would form a match, without applying it.
  bool debugSwapIsValid(int r1, int c1, int r2, int c2) {
    final MatchEngine? engine = _engine;
    if (engine == null) return false;
    if (!engine.areAdjacent(r1, c1, r2, c2)) return false;
    final SwapOutcome outcome = engine.applySwap(r1, c1, r2, c2);
    if (outcome.valid) {
      // Undo, so the probe leaves the board untouched.
      engine.rawSwap(r1, c1, r2, c2);
    }
    return outcome.valid;
  }

  void _stopTimers() {
    _hintTimer?.cancel();
    _hintTimer = null;
  }

  /// Called by the app when the lifecycle resumes, to catch up on lives.
  void onResume() {
    refreshLives();
  }

  @override
  void dispose() {
    _stopTimers();
    _lifeTimer?.cancel();
    super.dispose();
  }
}
