import 'dart:math';

import '../models/candy_tile.dart';

/// The shape a group of matched candies forms. Drives which special spawns.
enum MatchShape { line3, line4, line5, lShape, tShape }

/// How two special candies combine when swapped into each other.
enum ComboKind {
  none,
  stripedStriped,
  stripedWrapped,
  wrappedWrapped,
  rainbowStriped,
  rainbowWrapped,
  rainbowRainbow,
  rainbowNormal,
}

/// Scoring constants, kept in one place so the HUD and the engine agree.
class ScoreRules {
  ScoreRules._();

  /// Base points for one cleared candy.
  static const int perCandy = 60;

  /// Extra points for clearing a candy with a special attached.
  static const int specialCandyBonus = 120;

  /// Extra points for spawning a new special.
  static const int spawnBonus = 200;

  /// Extra points for a blocker hit.
  static const int blockerBonus = 40;

  /// Points for one jelly token reaching the bottom row.
  static const int jellyBonus = 2000;

  /// Cascade multiplier: the first clear of a turn is 1x, the next 2x, then 3x.
  static int cascadeMultiplier(int cascadeIndex) =>
      (1 + cascadeIndex).clamp(1, 8);

  /// Score for a clear of [count] candies at cascade depth [cascadeIndex].
  static int clearScore(int count, int cascadeIndex) =>
      count * perCandy * cascadeMultiplier(cascadeIndex);
}

/// One candy that vanished, kept so the view can spawn particles at its spot.
class ClearedCandy {
  ClearedCandy({
    required this.row,
    required this.col,
    required this.color,
    required this.special,
  });

  final int row;
  final int col;
  final CandyColorType color;
  final SpecialType special;
}

/// A special candy that gets written into the board after a match resolves.
class SpecialSpawn {
  SpecialSpawn(
      {required this.index, required this.color, required this.special});

  final int index;
  final CandyColorType color;
  final SpecialType special;
}

/// A single candy travelling between two rows, used to drive the fall tween.
class DropRecord {
  DropRecord(
      {required this.tileId,
      required this.col,
      required this.fromRow,
      required this.toRow});

  final int tileId;
  final int col;
  final int fromRow;
  final int toRow;
}

/// Everything that happens in one cascade iteration.
class ClearPlan {
  ClearPlan({
    required this.cells,
    required this.spawns,
    required this.blasts,
    required this.score,
  });

  /// Flat cell indices that are cleared this iteration.
  final Set<int> cells;

  /// Special candies written back into the board (their cells are not cleared).
  final List<SpecialSpawn> spawns;

  /// Indices of special candies that detonated, for the view to flash them.
  final Set<int> blasts;

  /// Points earned by this iteration.
  final int score;

  bool get isEmpty => cells.isEmpty && spawns.isEmpty;
}

/// The result of attempting a swap.
class SwapOutcome {
  SwapOutcome({
    required this.valid,
    this.combo = ComboKind.none,
    this.rainbowTarget,
    this.comboSeed = const <int>{},
    this.message,
  });

  /// False when the swap formed no match and involved no rainbow: revert it.
  final bool valid;

  /// Which special combo fired, if any.
  final ComboKind combo;

  /// For a rainbow + normal swap, the colour the rainbow will erase.
  final CandyColorType? rainbowTarget;

  /// Pre-seeded cells a combo will clear before normal match resolution runs.
  final Set<int> comboSeed;

  /// Optional flavour text for the combo banner.
  final String? message;

  bool get isCombo => combo != ComboKind.none;
}

/// A run of same coloured candies in a single line.
class _Run {
  _Run(this.cells, this.horizontal, this.color);

  final List<int> cells;
  final bool horizontal;
  final CandyColorType color;
}

/// A connected group of runs, i.e. one match the player made.
class MatchGroup {
  MatchGroup({
    required this.cells,
    required this.color,
    required this.shape,
    required this.spawnSpecial,
    required this.spawnIndex,
  });

  final Set<int> cells;
  final CandyColorType color;
  final MatchShape shape;
  final SpecialType spawnSpecial;
  final int spawnIndex;

  bool get spawnsSomething => spawnSpecial != SpecialType.none;
}

/// The board model plus every rule that operates on it.
///
/// The engine is deliberately free of Flutter imports: it is pure Dart so it can
/// be unit tested headlessly and so the view layer never has to know the rules.
class MatchEngine {
  MatchEngine({
    required this.rows,
    required this.cols,
    required int colorCount,
    Set<int>? blockedCells,
    List<BlockerCell>? blockers,
    int? seed,
  })  : colorCount = colorCount.clamp(3, CandyPalette.playable.length),
        blockedCells = blockedCells ?? <int>{},
        rng = Random(seed) {
    cells = List<CandyTile?>.filled(rows * cols, null);
    this.blockers = <int, BlockerCell>{};
    for (final BlockerCell b in blockers ?? const <BlockerCell>[]) {
      if (inBounds(b.row, b.col)) {
        this.blockers[b.row * cols + b.col] = BlockerCell(
          row: b.row,
          col: b.col,
          hp: b.hp,
          maxHp: b.maxHp,
        );
      }
    }
  }

  final int rows;
  final int cols;
  final Set<int> blockedCells;
  final Random rng;

  int colorCount;
  late List<CandyTile?> cells;
  late Map<int, BlockerCell> blockers;

  int _nextId = 0;

  /// Allocates a fresh stable tile id.
  int newId() => _nextId++;

  /// Guarantees ids stay unique after loading a saved board.
  void bumpIdFloor(int floor) {
    if (floor > _nextId) _nextId = floor;
  }

  int indexOf(int row, int col) => row * cols + col;

  int rowOf(int index) => index ~/ cols;

  int colOf(int index) => index % cols;

  bool inBounds(int row, int col) =>
      row >= 0 && row < rows && col >= 0 && col < cols;

  bool isHole(int row, int col) => blockedCells.contains(indexOf(row, col));

  /// A cell that can hold a candy.
  bool isPlayable(int row, int col) => inBounds(row, col) && !isHole(row, col);

  CandyTile? tileAt(int row, int col) =>
      inBounds(row, col) ? cells[indexOf(row, col)] : null;

  CandyTile? tileAtIdx(int index) =>
      index >= 0 && index < cells.length ? cells[index] : null;

  BlockerCell? blockerAt(int row, int col) =>
      inBounds(row, col) ? blockers[indexOf(row, col)] : null;

  int get blockerCount {
    int n = 0;
    for (final BlockerCell b in blockers.values) {
      if (!b.isBroken) n++;
    }
    return n;
  }

  /// Every cell index that is not a hole.
  List<int> get playableIndices {
    final List<int> out = <int>[];
    for (int i = 0; i < cells.length; i++) {
      if (!blockedCells.contains(i)) out.add(i);
    }
    return out;
  }

  /// Colours actually present on the board right now, for rainbow targeting.
  List<CandyColorType> get presentColors {
    final Set<CandyColorType> seen = <CandyColorType>{};
    for (final CandyTile? t in cells) {
      if (t != null && !t.isColorless && !t.isJelly) seen.add(t.color);
    }
    final List<CandyColorType> out = seen.toList();
    if (out.isEmpty) out.add(CandyColorType.red);
    return out;
  }

  /// The palette the generator draws from, capped to [colorCount].
  List<CandyColorType> get palette =>
      CandyPalette.playable.take(colorCount).toList(growable: false);

  // ---------------------------------------------------------------------------
  // Board construction
  // ---------------------------------------------------------------------------

  /// Builds a fresh, immediately playable board with no starting matches.
  void generateBoard() {
    cells = List<CandyTile?>.filled(rows * cols, null);
    final List<CandyColorType> pal = palette;
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        if (isHole(r, c)) continue;
        cells[indexOf(r, c)] = CandyTile(
          row: r,
          col: c,
          color: pal[rng.nextInt(pal.length)],
          id: newId(),
        );
      }
    }
    _removeStartingMatches();
    if (!hasPossibleMove()) shuffle();
  }

  /// Re-rolls candies that would start the level already matched, and never
  /// re-rolls a cell in a way that creates a new match (single pass, bounded).
  void _removeStartingMatches() {
    final List<CandyColorType> pal = palette;
    for (int pass = 0; pass < 40; pass++) {
      bool changed = false;
      for (int r = 0; r < rows; r++) {
        for (int c = 0; c < cols; c++) {
          final CandyTile? t = tileAt(r, c);
          if (t == null) continue;
          if (_createsRun(r, c, t.color)) {
            t.color = pal[rng.nextInt(pal.length)];
            changed = true;
          }
        }
      }
      if (!changed) break;
    }
  }

  /// True when the candy at (r,c) is part of a run of 3 or more, looking left
  /// and up only (so it is cheap and safe to call mid-construction).
  bool _createsRun(int r, int c, CandyColorType color) {
    if (color == CandyColorType.none) return false;
    int h = 1;
    for (int i = c - 1; i >= 0; i--) {
      final CandyTile? t = tileAt(r, i);
      if (t == null || t.color != color) break;
      h++;
    }
    for (int i = c + 1; i < cols; i++) {
      final CandyTile? t = tileAt(r, i);
      if (t == null || t.color != color) break;
      h++;
    }
    if (h >= 3) return true;

    int v = 1;
    for (int i = r - 1; i >= 0; i--) {
      final CandyTile? t = tileAt(i, c);
      if (t == null || t.color != color) break;
      v++;
    }
    for (int i = r + 1; i < rows; i++) {
      final CandyTile? t = tileAt(i, c);
      if (t == null || t.color != color) break;
      v++;
    }
    return v >= 3;
  }

  /// Drops a jelly objective token into the given column, at the top.
  ///
  /// The token replaces whatever candy sits in the topmost playable cell of the
  /// column. It then falls with gravity as the player clears the candies beneath
  /// it, which is what makes an ingredient level a puzzle rather than a lottery.
  CandyTile? spawnJelly(int column) {
    if (column < 0 || column >= cols) return null;
    for (int r = 0; r < rows; r++) {
      if (isHole(r, column)) continue;
      final CandyTile existing = CandyTile(
        row: r,
        col: column,
        color: CandyColorType.none,
        special: SpecialType.jelly,
        id: newId(),
      );
      cells[indexOf(r, column)] = existing;
      return existing;
    }
    return null;
  }

  /// Counts jelly tokens currently on the board.
  int get jellyOnBoard {
    int n = 0;
    for (final CandyTile? t in cells) {
      if (t != null && t.isJelly) n++;
    }
    return n;
  }

  // ---------------------------------------------------------------------------
  // Swap validation
  // ---------------------------------------------------------------------------

  bool areAdjacent(int r1, int c1, int r2, int c2) =>
      (r1 == r2 && (c1 - c2).abs() == 1) || (c1 == c2 && (r1 - r2).abs() == 1);

  /// Swaps two tiles in the model without any validation.
  void rawSwap(int r1, int c1, int r2, int c2) {
    final int i1 = indexOf(r1, c1);
    final int i2 = indexOf(r2, c2);
    final CandyTile? a = cells[i1];
    final CandyTile? b = cells[i2];
    cells[i1] = b;
    cells[i2] = a;
    if (a != null) {
      a.row = r2;
      a.col = c2;
    }
    if (b != null) {
      b.row = r1;
      b.col = c1;
    }
  }

  /// Validates and applies a swap.
  ///
  /// A swap is legal when it forms a match, or when either candy is a rainbow
  /// bomb (rainbows never match, they detonate). When illegal the swap is
  /// reverted before returning, so the board is always left consistent.
  SwapOutcome applySwap(int r1, int c1, int r2, int c2) {
    if (!isPlayable(r1, c1) || !isPlayable(r2, c2)) {
      return SwapOutcome(valid: false);
    }
    final CandyTile? a = tileAt(r1, c1);
    final CandyTile? b = tileAt(r2, c2);
    if (a == null || b == null) return SwapOutcome(valid: false);
    if (a.isJelly || b.isJelly) return SwapOutcome(valid: false);

    rawSwap(r1, c1, r2, c2);

    // Special + special, or rainbow + anything: always legal.
    final ComboKind combo = _classifyCombo(a, b);
    if (combo != ComboKind.none) {
      return _withSwapCells(
        _buildComboOutcome(combo, a, b, r1, c1, r2, c2),
        indexOf(r1, c1),
        indexOf(r2, c2),
      );
    }

    final List<MatchGroup> groups = findMatches();
    if (groups.isEmpty) {
      rawSwap(r1, c1, r2, c2); // revert
      return SwapOutcome(valid: false);
    }
    return SwapOutcome(valid: true);
  }

  ComboKind _classifyCombo(CandyTile a, CandyTile b) {
    final bool ar = a.isRainbow;
    final bool br = b.isRainbow;
    if (ar && br) return ComboKind.rainbowRainbow;
    if (ar || br) {
      final CandyTile other = ar ? b : a;
      if (other.isStriped) return ComboKind.rainbowStriped;
      if (other.isWrapped) return ComboKind.rainbowWrapped;
      return ComboKind.rainbowNormal;
    }
    if (a.isStriped && b.isStriped) return ComboKind.stripedStriped;
    if (a.isWrapped && b.isWrapped) return ComboKind.wrappedWrapped;
    if ((a.isStriped && b.isWrapped) || (a.isWrapped && b.isStriped)) {
      return ComboKind.stripedWrapped;
    }
    return ComboKind.none;
  }

  SwapOutcome _buildComboOutcome(
    ComboKind combo,
    CandyTile a,
    CandyTile b,
    int r1,
    int c1,
    int r2,
    int c2,
  ) {
    final Set<int> seed = <int>{};
    CandyColorType? rainbowTarget;
    String message;

    switch (combo) {
      case ComboKind.rainbowRainbow:
        message = 'BOARD WIPE!';
        for (int i = 0; i < cells.length; i++) {
          if (cells[i] != null && !cells[i]!.isJelly) seed.add(i);
        }
        break;
      case ComboKind.rainbowStriped:
        message = 'STRIPED STORM!';
        final CandyTile striped = a.isStriped ? a : b;
        rainbowTarget = striped.color;
        // Every candy of that colour becomes a striped candy, then all detonate.
        for (final int i in playableIndices) {
          final CandyTile? t = cells[i];
          if (t == null || t.isJelly || t.isRainbow) continue;
          if (t.color == rainbowTarget) {
            t.special = t.special == SpecialType.stripedHorizontal
                ? SpecialType.stripedVertical
                : SpecialType.stripedHorizontal;
            if (!t.isStriped) t.special = SpecialType.stripedHorizontal;
            seed.add(i);
          }
        }
        break;
      case ComboKind.rainbowWrapped:
        message = 'MEGA BOMB!';
        final CandyTile wrapped = a.isWrapped ? a : b;
        rainbowTarget = wrapped.color;
        for (final int i in playableIndices) {
          final CandyTile? t = cells[i];
          if (t == null || t.isJelly || t.isRainbow) continue;
          if (t.color == rainbowTarget) {
            t.special = SpecialType.wrapped;
            seed.add(i);
          }
        }
        break;
      case ComboKind.rainbowNormal:
        final CandyTile normal = a.isRainbow ? b : a;
        rainbowTarget = normal.color;
        message = '${normal.color.name.toUpperCase()} CRUSH!';
        for (final int i in playableIndices) {
          final CandyTile? t = cells[i];
          if (t == null || t.isJelly) continue;
          if (t.color == rainbowTarget) seed.add(i);
        }
        break;
      case ComboKind.stripedStriped:
        message = 'GIANT CROSS!';
        for (int c = 0; c < cols; c++) {
          if (!isHole(r2, c)) seed.add(indexOf(r2, c));
        }
        for (int r = 0; r < rows; r++) {
          if (!isHole(r, c2)) seed.add(indexOf(r, c2));
        }
        break;
      case ComboKind.stripedWrapped:
        message = 'SUGAR QUAKE!';
        for (int dr = -1; dr <= 1; dr++) {
          final int r = r2 + dr;
          if (r < 0 || r >= rows) continue;
          for (int c = 0; c < cols; c++) {
            if (!isHole(r, c)) seed.add(indexOf(r, c));
          }
        }
        for (int dc = -1; dc <= 1; dc++) {
          final int c = c2 + dc;
          if (c < 0 || c >= cols) continue;
          for (int r = 0; r < rows; r++) {
            if (!isHole(r, c)) seed.add(indexOf(r, c));
          }
        }
        break;
      case ComboKind.wrappedWrapped:
        message = 'DOUBLE BLAST!';
        for (int dr = -2; dr <= 2; dr++) {
          for (int dc = -2; dc <= 2; dc++) {
            final int r = r2 + dr;
            final int c = c2 + dc;
            if (isPlayable(r, c)) seed.add(indexOf(r, c));
          }
        }
        break;
      case ComboKind.none:
        message = '';
        break;
    }

    return SwapOutcome(
      valid: true,
      combo: combo,
      rainbowTarget: rainbowTarget,
      comboSeed: seed,
      message: message,
    );
  }

  /// Every combo consumes both swapped candies, so the two cells always join
  /// the clear set regardless of which branch built it.
  SwapOutcome _withSwapCells(SwapOutcome outcome, int i1, int i2) {
    final Set<int> seed = Set<int>.from(outcome.comboSeed)
      ..addAll(<int>[i1, i2]);
    return SwapOutcome(
      valid: outcome.valid,
      combo: outcome.combo,
      rainbowTarget: outcome.rainbowTarget,
      comboSeed: seed,
      message: outcome.message,
    );
  }

  // ---------------------------------------------------------------------------
  // Match detection
  // ---------------------------------------------------------------------------

  /// Finds every match currently on the board, merged into connected groups.
  List<MatchGroup> findMatches() {
    final List<_Run> runs = _findRuns();
    if (runs.isEmpty) return const <MatchGroup>[];

    // Union runs that share a cell into one group.
    final List<List<int>> parent =
        List<List<int>>.generate(runs.length, (int i) => <int>[i]);
    int find(int x) {
      while (parent[x][0] != x) {
        parent[x][0] = parent[parent[x][0]][0];
        x = parent[x][0];
      }
      return x;
    }

    void union(int a, int b) {
      final int ra = find(a);
      final int rb = find(b);
      if (ra != rb) parent[rb][0] = ra;
    }

    final Map<int, List<int>> cellToRun = <int, List<int>>{};
    for (int i = 0; i < runs.length; i++) {
      for (final int cell in runs[i].cells) {
        cellToRun.putIfAbsent(cell, () => <int>[]).add(i);
      }
    }
    for (final List<int> group in cellToRun.values) {
      for (int k = 1; k < group.length; k++) {
        union(group[0], group[k]);
      }
    }

    final Map<int, List<_Run>> merged = <int, List<_Run>>{};
    for (int i = 0; i < runs.length; i++) {
      merged.putIfAbsent(find(i), () => <_Run>[]).add(runs[i]);
    }

    final List<MatchGroup> out = <MatchGroup>[];
    for (final List<_Run> group in merged.values) {
      out.add(_groupFromRuns(group));
    }
    return out;
  }

  /// Scans rows and columns for runs of 3 or more same coloured candies.
  List<_Run> _findRuns() {
    final List<_Run> runs = <_Run>[];

    // Horizontal.
    for (int r = 0; r < rows; r++) {
      int c = 0;
      while (c < cols) {
        final CandyTile? t = tileAt(r, c);
        if (t == null || t.isColorless || t.isJelly) {
          c++;
          continue;
        }
        final CandyColorType color = t.color;
        final List<int> run = <int>[indexOf(r, c)];
        int k = c + 1;
        while (k < cols) {
          final CandyTile? n = tileAt(r, k);
          if (n == null || n.color != color || n.isJelly) break;
          run.add(indexOf(r, k));
          k++;
        }
        if (run.length >= 3) runs.add(_Run(run, true, color));
        c = k;
      }
    }

    // Vertical.
    for (int c = 0; c < cols; c++) {
      int r = 0;
      while (r < rows) {
        final CandyTile? t = tileAt(r, c);
        if (t == null || t.isColorless || t.isJelly) {
          r++;
          continue;
        }
        final CandyColorType color = t.color;
        final List<int> run = <int>[indexOf(r, c)];
        int k = r + 1;
        while (k < rows) {
          final CandyTile? n = tileAt(k, c);
          if (n == null || n.color != color || n.isJelly) break;
          run.add(indexOf(k, c));
          k++;
        }
        if (run.length >= 3) runs.add(_Run(run, false, color));
        r = k;
      }
    }

    return runs;
  }

  /// Works out the shape and the special a merged group of runs spawns.
  MatchGroup _groupFromRuns(List<_Run> runs) {
    final Set<int> cellsInGroup = <int>{};
    for (final _Run run in runs) {
      cellsInGroup.addAll(run.cells);
    }

    int maxH = 0;
    int maxV = 0;
    for (final _Run run in runs) {
      if (run.horizontal) {
        if (run.cells.length > maxH) maxH = run.cells.length;
      } else {
        if (run.cells.length > maxV) maxV = run.cells.length;
      }
    }
    final bool hasH = maxH >= 3;
    final bool hasV = maxV >= 3;
    final int longest = max(maxH, maxV);

    MatchShape shape;
    SpecialType spawn;

    if (longest >= 5) {
      shape = MatchShape.line5;
      spawn = SpecialType.rainbow;
    } else if (hasH && hasV) {
      shape = (maxH >= 4 || maxV >= 4) ? MatchShape.tShape : MatchShape.lShape;
      spawn = SpecialType.wrapped;
    } else if (longest == 4) {
      shape = MatchShape.line4;
      spawn = maxH == 4
          ? SpecialType.stripedHorizontal
          : SpecialType.stripedVertical;
    } else {
      shape = MatchShape.line3;
      spawn = SpecialType.none;
    }

    // Prefer the crossing cell for wrapped candies so the bomb sits in the
    // corner of the L, which is what players expect.
    int spawnIndex = cellsInGroup.first;
    if (shape == MatchShape.lShape || shape == MatchShape.tShape) {
      final Set<int> hCells = <int>{};
      final Set<int> vCells = <int>{};
      for (final _Run run in runs) {
        if (run.horizontal) {
          hCells.addAll(run.cells);
        } else {
          vCells.addAll(run.cells);
        }
      }
      final Set<int> cross = hCells.intersection(vCells);
      if (cross.isNotEmpty) spawnIndex = cross.first;
    } else {
      // Middle of the longest run reads best for stripes and rainbows.
      List<int> best = runs.first.cells;
      for (final _Run run in runs) {
        if (run.cells.length > best.length) best = run.cells;
      }
      spawnIndex = best[best.length ~/ 2];
    }

    return MatchGroup(
      cells: cellsInGroup,
      color: runs.first.color,
      shape: shape,
      spawnSpecial: spawn,
      spawnIndex: spawnIndex,
    );
  }

  /// Where the player should swap, for the idle hint animation. Returns null
  /// when the board has no move (the caller should then shuffle).
  List<int>? findHint() {
    for (final int i in playableIndices) {
      final CandyTile? t = cells[i];
      if (t == null) continue;
      if (t.isRainbow) {
        final int r = rowOf(i);
        final int c = colOf(i);
        if (isPlayable(r, c + 1)) return <int>[i, indexOf(r, c + 1)];
        if (isPlayable(r + 1, c)) return <int>[i, indexOf(r + 1, c)];
      }
      final int r = rowOf(i);
      final int c = colOf(i);
      // Swap right.
      if (isPlayable(r, c + 1)) {
        final int j = indexOf(r, c + 1);
        if (cells[j] != null && _swapMakesMatch(i, j)) return <int>[i, j];
      }
      // Swap down.
      if (isPlayable(r + 1, c)) {
        final int j = indexOf(r + 1, c);
        if (cells[j] != null && _swapMakesMatch(i, j)) return <int>[i, j];
      }
    }
    return null;
  }

  bool hasPossibleMove() => findHint() != null;

  /// Tests a hypothetical swap by swapping, checking only the two affected
  /// cells, then swapping back. Cheap enough to run over the whole board.
  bool _swapMakesMatch(int i, int j) {
    final CandyTile? a = cells[i];
    final CandyTile? b = cells[j];
    if (a == null || b == null) return false;
    if (a.isRainbow || b.isRainbow) return true;
    if (a.isJelly || b.isJelly) return false;

    cells[i] = b;
    cells[j] = a;
    final bool match =
        _partOfRun(rowOf(i), colOf(i)) || _partOfRun(rowOf(j), colOf(j));
    cells[i] = a;
    cells[j] = b;
    return match;
  }

  /// True when the candy at (r,c) belongs to a run of 3 or more.
  bool _partOfRun(int r, int c) {
    final CandyTile? t = tileAt(r, c);
    if (t == null || t.isColorless || t.isJelly) return false;
    final CandyColorType color = t.color;

    int h = 1;
    for (int i = c - 1; i >= 0; i--) {
      final CandyTile? n = tileAt(r, i);
      if (n == null || n.color != color || n.isJelly) break;
      h++;
    }
    for (int i = c + 1; i < cols; i++) {
      final CandyTile? n = tileAt(r, i);
      if (n == null || n.color != color || n.isJelly) break;
      h++;
    }
    if (h >= 3) return true;

    int v = 1;
    for (int i = r - 1; i >= 0; i--) {
      final CandyTile? n = tileAt(i, c);
      if (n == null || n.color != color || n.isJelly) break;
      v++;
    }
    for (int i = r + 1; i < rows; i++) {
      final CandyTile? n = tileAt(i, c);
      if (n == null || n.color != color || n.isJelly) break;
      v++;
    }
    return v >= 3;
  }

  // ---------------------------------------------------------------------------
  // Clear planning and detonation
  // ---------------------------------------------------------------------------

  /// Builds the full clear set for a set of matches, expanding every special
  /// candy that is caught in the blast, to a fixed point.
  ///
  /// [comboSeed] holds cells a special combo already decided to clear. Its
  /// specials detonate too.
  /// [comboSpawns] are the special candies written back at the end.
  ClearPlan buildPlan(
    List<MatchGroup> matches, {
    Set<int> comboSeed = const <int>{},
    List<SpecialSpawn> comboReplacements = const <SpecialSpawn>[],
    CandyColorType? rainbowTarget,
    int cascadeIndex = 0,
  }) {
    final Set<int> clear = <int>{};
    final Set<int> blasts = <int>{};
    final Map<int, SpecialSpawn> spawnMap = <int, SpecialSpawn>{};

    for (final MatchGroup g in matches) {
      clear.addAll(g.cells);
      if (g.spawnsSomething) {
        spawnMap[g.spawnIndex] = SpecialSpawn(
          index: g.spawnIndex,
          color: g.spawnSpecial == SpecialType.rainbow
              ? CandyColorType.none
              : g.color,
          special: g.spawnSpecial,
        );
      }
    }

    for (final SpecialSpawn s in comboReplacements) {
      spawnMap[s.index] = s;
    }

    clear.addAll(comboSeed);

    // Spawn cells are transformed, never removed.
    for (final int idx in spawnMap.keys) {
      clear.remove(idx);
    }

    // Fixed point expansion: detonating a special adds cells, which may add
    // more specials to detonate.
    final Set<int> detonated = <int>{};
    bool changed = true;
    int guard = 0;
    while (changed && guard++ < 64) {
      changed = false;
      final List<int> snapshot = clear.toList();
      for (final int idx in snapshot) {
        final CandyTile? t = cells[idx];
        if (t == null || t.isJelly) continue;
        if (!t.isSpecial) continue;
        if (detonated.contains(idx)) continue;
        detonated.add(idx);
        blasts.add(idx);
        changed = true;
        for (final int extra in _blastCells(idx, t, rainbowTarget)) {
          if (clear.add(extra)) changed = true;
        }
      }
    }

    for (final int idx in spawnMap.keys) {
      clear.remove(idx);
    }
    clear.removeWhere((int idx) => cells[idx] == null);

    final int score = ScoreRules.clearScore(clear.length, cascadeIndex) +
        blasts.length * ScoreRules.specialCandyBonus +
        spawnMap.length * ScoreRules.spawnBonus;

    return ClearPlan(
      cells: clear,
      spawns: spawnMap.values.toList(),
      blasts: blasts,
      score: score,
    );
  }

  /// The cells a single detonating special clears.
  Set<int> _blastCells(int idx, CandyTile t, CandyColorType? rainbowTarget) {
    final Set<int> out = <int>{};
    final int r = rowOf(idx);
    final int c = colOf(idx);

    switch (t.special) {
      case SpecialType.stripedHorizontal:
        for (int cc = 0; cc < cols; cc++) {
          if (!isHole(r, cc)) out.add(indexOf(r, cc));
        }
        break;
      case SpecialType.stripedVertical:
        for (int rr = 0; rr < rows; rr++) {
          if (!isHole(rr, c)) out.add(indexOf(rr, c));
        }
        break;
      case SpecialType.wrapped:
        for (int dr = -1; dr <= 1; dr++) {
          for (int dc = -1; dc <= 1; dc++) {
            if (isPlayable(r + dr, c + dc)) out.add(indexOf(r + dr, c + dc));
          }
        }
        break;
      case SpecialType.rainbow:
        final CandyColorType target =
            rainbowTarget ?? presentColors[rng.nextInt(presentColors.length)];
        for (int i = 0; i < cells.length; i++) {
          final CandyTile? n = cells[i];
          if (n == null || n.isJelly) continue;
          if (n.color == target) out.add(i);
        }
        break;
      case SpecialType.none:
      case SpecialType.jelly:
        break;
    }
    return out;
  }

  /// Removes every candy in [plan] and writes the spawned specials back.
  ///
  /// Returns the candies that vanished so the view can burst them.
  List<ClearedCandy> applyClear(ClearPlan plan) {
    final List<ClearedCandy> removed = <ClearedCandy>[];
    for (final int idx in plan.cells) {
      final CandyTile? t = cells[idx];
      if (t == null) continue;
      removed.add(ClearedCandy(
        row: t.row,
        col: t.col,
        color: t.color,
        special: t.special,
      ));
      cells[idx] = null;
    }

    for (final SpecialSpawn s in plan.spawns) {
      if (s.index < 0 || s.index >= cells.length) continue;
      final CandyTile? existing = cells[s.index];
      if (existing == null) continue;
      existing.special = s.special;
      existing.color =
          s.special == SpecialType.rainbow ? CandyColorType.none : s.color;
    }
    return removed;
  }

  /// Applies damage to frosting next to (or under) every cleared cell.
  ///
  /// Returns the number of blockers that broke this step.
  int crackBlockers(Iterable<int> clearedCells) {
    if (blockers.isEmpty) return 0;
    final Set<int> hit = <int>{};
    for (final int idx in clearedCells) {
      final int r = rowOf(idx);
      final int c = colOf(idx);
      final int self = indexOf(r, c);
      if (blockers.containsKey(self)) hit.add(self);
      for (final List<int> d in const <List<int>>[
        <int>[-1, 0],
        <int>[1, 0],
        <int>[0, -1],
        <int>[0, 1],
      ]) {
        final int nr = r + d[0];
        final int nc = c + d[1];
        if (!inBounds(nr, nc)) continue;
        final int ni = indexOf(nr, nc);
        if (blockers.containsKey(ni)) hit.add(ni);
      }
    }

    int broken = 0;
    for (final int idx in hit) {
      final BlockerCell? b = blockers[idx];
      if (b == null || b.isBroken) continue;
      b.hp--;
      if (b.isBroken) broken++;
    }
    return broken;
  }

  /// True when every frosting cell has been broken.
  bool get allBlockersCleared {
    for (final BlockerCell b in blockers.values) {
      if (!b.isBroken) return false;
    }
    return true;
  }

  // ---------------------------------------------------------------------------
  // Gravity and refill
  // ---------------------------------------------------------------------------

  /// Compacts every column downwards, honouring holes.
  ///
  /// Returns one [DropRecord] per candy that moved, with the tile's animY set so
  /// the view can tween it from where it was to where it now is.
  List<DropRecord> applyGravity() {
    final List<DropRecord> drops = <DropRecord>[];

    for (int c = 0; c < cols; c++) {
      // Walk the column bottom up inside each contiguous segment of playable
      // cells. A hole ends the segment.
      int segmentBottom = -1;
      int r = rows - 1;
      while (r >= 0) {
        if (isHole(r, c)) {
          segmentBottom = -1;
          r--;
          continue;
        }
        if (segmentBottom == -1) segmentBottom = r;

        // Find the next candy above within this segment.
        int writeRow = segmentBottom;
        for (int readRow = segmentBottom; readRow >= 0; readRow--) {
          if (isHole(readRow, c)) break;
          final CandyTile? t = tileAt(readRow, c);
          if (t == null) continue;
          if (readRow != writeRow) {
            final int fromIndex = indexOf(readRow, c);
            final int toIndex = indexOf(writeRow, c);
            cells[toIndex] = t;
            cells[fromIndex] = null;
            t.animY = (readRow - writeRow).toDouble();
            t.isFalling = true;
            drops.add(DropRecord(
              tileId: t.id,
              col: c,
              fromRow: readRow,
              toRow: writeRow,
            ));
            t.row = writeRow;
            t.col = c;
          }
          writeRow--;
          if (writeRow < 0) break;
        }

        // Everything above the last written row in this segment is empty; move
        // on to the segment above the hole.
        r = writeRow;
        if (r >= 0 && !isHole(r, c)) {
          // There are no more candies in this segment; skip to the hole.
          while (r >= 0 && !isHole(r, c)) {
            r--;
          }
        }
        segmentBottom = -1;
      }
    }
    return drops;
  }

  /// Fills every empty playable cell, spawning new candies above the board so
  /// they visibly fall in.
  ///
  /// Returns the newly created tiles.
  List<CandyTile> refill() {
    final List<CandyTile> created = <CandyTile>[];
    final List<CandyColorType> pal = palette;

    for (int c = 0; c < cols; c++) {
      // Count how many empty cells sit in each segment so the spawn offsets
      // stack correctly from the top.
      int spawnDepth = 0;
      for (int r = 0; r < rows; r++) {
        if (isHole(r, c)) {
          spawnDepth = 0;
          continue;
        }
        final int idx = indexOf(r, c);
        if (cells[idx] != null) {
          spawnDepth = 0;
          continue;
        }
        final CandyTile t = CandyTile(
          row: r,
          col: c,
          color: pal[rng.nextInt(pal.length)],
          id: newId(),
        );
        // The first empty cell from the top starts one row above the board and
        // each subsequent one stacks further up.
        spawnDepth++;
        t.animY = -(spawnDepth + 0.0);
        t.isFalling = true;
        cells[idx] = t;
        created.add(t);
      }
    }
    return created;
  }

  // ---------------------------------------------------------------------------
  // Shuffle
  // ---------------------------------------------------------------------------

  /// Rearranges the existing candies until a legal move exists and no match is
  /// already on the board. Falls back to a fresh board if it cannot.
  bool shuffle() {
    final List<int> positions = playableIndices;
    final List<CandyTile?> payloads =
        positions.map((int i) => cells[i]).toList(growable: true);

    for (int attempt = 0; attempt < 300; attempt++) {
      payloads.shuffle(rng);
      for (int k = 0; k < positions.length; k++) {
        final CandyTile? t = payloads[k];
        if (t != null) {
          t.row = rowOf(positions[k]);
          t.col = colOf(positions[k]);
          t.resetAnimation();
        }
        cells[positions[k]] = t;
      }
      if (findMatches().isEmpty && hasPossibleMove()) return true;
    }

    // Could not find an arrangement: rebuild the colours from scratch.
    for (final int i in positions) {
      final CandyTile? t = cells[i];
      if (t == null) continue;
      if (t.isJelly || t.isRainbow) continue;
      t.color = palette[rng.nextInt(palette.length)];
      t.resetAnimation();
    }
    _removeStartingMatches();
    return true;
  }

  /// Ensures the board is playable, shuffling when it is not.
  bool ensurePlayable() {
    if (hasPossibleMove()) return false;
    shuffle();
    return true;
  }

  /// Picks a random playable cell that currently holds a candy, for placing a
  /// starting colour bomb booster.
  int? randomCandyCell() {
    final List<int> options = <int>[];
    for (final int i in playableIndices) {
      final CandyTile? t = cells[i];
      if (t != null && !t.isJelly) options.add(i);
    }
    if (options.isEmpty) return null;
    return options[rng.nextInt(options.length)];
  }

  /// Clears one cell outright, used by the lollipop hammer booster.
  ClearedCandy? smash(int index) {
    if (index < 0 || index >= cells.length) return null;
    final CandyTile? t = cells[index];
    if (t == null || t.isJelly) return null;
    final ClearedCandy out = ClearedCandy(
      row: t.row,
      col: t.col,
      color: t.color,
      special: t.special,
    );
    cells[index] = null;
    return out;
  }

  /// Deep copy, used by tests and by the "undo last move" style previews.
  MatchEngine clone() {
    final MatchEngine e = MatchEngine(
      rows: rows,
      cols: cols,
      colorCount: colorCount,
      blockedCells: Set<int>.from(blockedCells),
      seed: 1,
    );
    e.bumpIdFloor(_nextId);
    e.blockers = blockers.map((int k, BlockerCell v) =>
        MapEntry<int, BlockerCell>(
            k, BlockerCell(row: v.row, col: v.col, hp: v.hp, maxHp: v.maxHp)));
    e.cells = cells.map((CandyTile? t) => t?.copyWith()).toList(growable: true);
    return e;
  }
}
