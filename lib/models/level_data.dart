import 'candy_tile.dart';

/// What the player has to do to beat the level.
enum ObjectiveType {
  /// Reach [LevelObjective.target] points before the moves run out.
  score,

  /// Walk [LevelObjective.target] jelly ingredients to the bottom row.
  ingredient,

  /// Break [LevelObjective.target] frosting cells.
  frosting,
}

/// One objective row shown in the level goal panel.
class LevelObjective {
  const LevelObjective({
    required this.type,
    required this.target,
    this.progress = 0,
    this.label = '',
  });

  final ObjectiveType type;
  final int target;

  /// How far the player has got. Replaced through [copyWith], never mutated in
  /// place, so the class can stay const constructible.
  final int progress;

  final String label;

  bool get isComplete => progress >= target;

  double get ratio => target <= 0 ? 1.0 : (progress / target).clamp(0.0, 1.0);

  LevelObjective copyWith({int? progress}) => LevelObjective(
      type: type,
      target: target,
      progress: progress ?? this.progress,
      label: label);

  Map<String, dynamic> toJson() => <String, dynamic>{
        't': type.index,
        'g': target,
        'p': progress,
        'l': label
      };

  static LevelObjective fromJson(Map<String, dynamic> j) => LevelObjective(
        type: ObjectiveType.values[j['t'] as int],
        target: j['g'] as int,
        progress: j['p'] as int,
        label: j['l'] as String? ?? '',
      );
}

/// The star thresholds for a level. Index 0 is one star, index 2 is three.
class StarThresholds {
  const StarThresholds(
      {required this.one, required this.two, required this.three});

  final int one;
  final int two;
  final int three;

  /// How many stars [score] earns, 0 to 3.
  int starsFor(int score) {
    if (score >= three) return 3;
    if (score >= two) return 2;
    if (score >= one) return 1;
    return 0;
  }

  Map<String, dynamic> toJson() =>
      <String, dynamic>{'1': one, '2': two, '3': three};

  static StarThresholds fromJson(Map<String, dynamic> j) => StarThresholds(
      one: j['1'] as int, two: j['2'] as int, three: j['3'] as int);
}

/// Everything needed to build and play one level.
///
/// Levels are plain data: the engine reads this and knows nothing about how a
/// particular level was authored. [LevelRepository] produces the shipped set and
/// a generator can produce endless ones on top of the same shape.
class LevelData {
  LevelData({
    required this.id,
    required this.name,
    required this.rows,
    required this.cols,
    required this.moves,
    required this.objectives,
    required this.stars,
    this.colorCount = 5,
    this.blockers = const <BlockerCell>[],
    this.blockedCells = const <int>{},
    this.ingredientDropColumn,
    this.jellyCount = 0,
    this.seed,
  });

  /// Level number, 1 based.
  final int id;
  final String name;

  /// Grid dimensions. Candy Cascade ships 9x9 but the engine is size agnostic.
  final int rows;
  final int cols;

  /// Moves allowed before the level is lost.
  final int moves;

  /// How many distinct candy colours the generator may place, 3 to 6.
  /// Lower is easier.
  final int colorCount;

  final List<LevelObjective> objectives;
  final StarThresholds stars;

  /// Starting frosting / ice cells.
  final List<BlockerCell> blockers;

  /// Flat set of `row * cols + col` indices that are holes in the board
  /// (a candy can never exist there and gravity skips them).
  final Set<int> blockedCells;

  /// For ingredient levels: the column the jelly token starts in.
  final int? ingredientDropColumn;

  /// How many jelly tokens this level spawns.
  final int jellyCount;

  /// Deterministic board seed, so a level always starts the same way.
  final int? seed;

  int get cellCount => rows * cols;

  bool isHole(int row, int col) => blockedCells.contains(row * cols + col);

  /// Score objective if this level has one.
  LevelObjective? get scoreObjective {
    for (final LevelObjective o in objectives) {
      if (o.type == ObjectiveType.score) return o;
    }
    return null;
  }

  LevelObjective? objectiveOf(ObjectiveType type) {
    for (final LevelObjective o in objectives) {
      if (o.type == type) return o;
    }
    return null;
  }

  LevelData copyWith({List<LevelObjective>? objectives}) => LevelData(
        id: id,
        name: name,
        rows: rows,
        cols: cols,
        moves: moves,
        objectives: objectives ?? this.objectives,
        stars: stars,
        colorCount: colorCount,
        blockers: blockers,
        blockedCells: blockedCells,
        ingredientDropColumn: ingredientDropColumn,
        jellyCount: jellyCount,
        seed: seed,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'rows': rows,
        'cols': cols,
        'moves': moves,
        'colorCount': colorCount,
        'objectives': objectives.map((LevelObjective o) => o.toJson()).toList(),
        'stars': stars.toJson(),
        'blockers': blockers.map((BlockerCell b) => b.toJson()).toList(),
        'blocked': blockedCells.toList(),
        'ingredientColumn': ingredientDropColumn,
        'jellyCount': jellyCount,
        'seed': seed,
      };

  static LevelData fromJson(Map<String, dynamic> j) => LevelData(
        id: j['id'] as int,
        name: j['name'] as String,
        rows: j['rows'] as int,
        cols: j['cols'] as int,
        moves: j['moves'] as int,
        colorCount: j['colorCount'] as int? ?? 5,
        objectives: (j['objectives'] as List<dynamic>)
            .map((dynamic e) =>
                LevelObjective.fromJson(e as Map<String, dynamic>))
            .toList(),
        stars: StarThresholds.fromJson(j['stars'] as Map<String, dynamic>),
        blockers: (j['blockers'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic e) => BlockerCell.fromJson(e as Map<String, dynamic>))
            .toList(),
        blockedCells: (j['blocked'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic e) => e as int)
            .toSet(),
        ingredientDropColumn: j['ingredientColumn'] as int?,
        jellyCount: j['jellyCount'] as int? ?? 0,
        seed: j['seed'] as int?,
      );
}

/// Builds the shipped level list.
///
/// The first ten levels are hand tuned to teach one mechanic at a time, then
/// the generator produces an endless ramp on top of that.
class LevelRepository {
  LevelRepository._();

  static const int handCraftedCount = 10;

  /// Returns level [id] (1 based). Ids past the hand crafted set are generated
  /// deterministically from the id, so the same number always gives the same
  /// board.
  static LevelData levelFor(int id) {
    final List<LevelData> crafted = _handCrafted();
    if (id <= crafted.length) return crafted[id - 1];
    return generate(id);
  }

  static List<LevelData> _handCrafted() {
    return <LevelData>[
      // 1: teach swapping, pure score.
      LevelData(
        id: 1,
        name: 'Sugar Rush',
        rows: 9,
        cols: 9,
        moves: 25,
        colorCount: 4,
        seed: 1001,
        objectives: const <LevelObjective>[
          LevelObjective(
              type: ObjectiveType.score, target: 3000, label: 'Score'),
        ],
        stars: const StarThresholds(one: 3000, two: 6000, three: 9000),
      ),
      // 2: a second score step, five colours.
      LevelData(
        id: 2,
        name: 'Gummy Gate',
        rows: 9,
        cols: 9,
        moves: 25,
        colorCount: 5,
        seed: 1002,
        objectives: const <LevelObjective>[
          LevelObjective(
              type: ObjectiveType.score, target: 6000, label: 'Score'),
        ],
        stars: const StarThresholds(one: 6000, two: 10000, three: 15000),
      ),
      // 3: first frosting, a small patch in the middle.
      LevelData(
        id: 3,
        name: 'First Frost',
        rows: 9,
        cols: 9,
        moves: 22,
        colorCount: 5,
        seed: 1003,
        blockers: _frostingPatch(3, 3, 3, 3),
        objectives: const <LevelObjective>[
          LevelObjective(
              type: ObjectiveType.frosting, target: 9, label: 'Frosting'),
        ],
        stars: const StarThresholds(one: 5000, two: 9000, three: 14000),
      ),
      // 4: bigger frosting block.
      LevelData(
        id: 4,
        name: 'Ice House',
        rows: 9,
        cols: 9,
        moves: 24,
        colorCount: 5,
        seed: 1004,
        blockers: _frostingPatch(2, 2, 5, 5),
        objectives: const <LevelObjective>[
          LevelObjective(
              type: ObjectiveType.frosting, target: 25, label: 'Frosting'),
        ],
        stars: const StarThresholds(one: 6000, two: 11000, three: 16000),
      ),
      // 5: first ingredient drop.
      LevelData(
        id: 5,
        name: 'Jelly Run',
        rows: 9,
        cols: 9,
        moves: 24,
        colorCount: 5,
        seed: 1005,
        ingredientDropColumn: 4,
        jellyCount: 2,
        objectives: const <LevelObjective>[
          LevelObjective(
              type: ObjectiveType.ingredient, target: 2, label: 'Jelly'),
        ],
        stars: const StarThresholds(one: 5000, two: 9000, three: 13000),
      ),
      // 6: three jelly plus a small score ask.
      LevelData(
        id: 6,
        name: 'Drop Zone',
        rows: 9,
        cols: 9,
        moves: 26,
        colorCount: 5,
        seed: 1006,
        ingredientDropColumn: 2,
        jellyCount: 3,
        objectives: const <LevelObjective>[
          LevelObjective(
              type: ObjectiveType.ingredient, target: 3, label: 'Jelly'),
          LevelObjective(
              type: ObjectiveType.score, target: 8000, label: 'Score'),
        ],
        stars: const StarThresholds(one: 8000, two: 14000, three: 20000),
      ),
      // 7: frosting with holes, the board shape matters.
      LevelData(
        id: 7,
        name: 'Hollow Hearts',
        rows: 9,
        cols: 9,
        moves: 25,
        colorCount: 5,
        seed: 1007,
        blockedCells: _diamondHoles(9, 9),
        blockers: _frostingPatch(3, 3, 3, 3),
        objectives: const <LevelObjective>[
          LevelObjective(
              type: ObjectiveType.frosting, target: 9, label: 'Frosting'),
          LevelObjective(
              type: ObjectiveType.score, target: 9000, label: 'Score'),
        ],
        stars: const StarThresholds(one: 9000, two: 15000, three: 22000),
      ),
      // 8: two jellies in different columns plus score.
      LevelData(
        id: 8,
        name: 'Double Drop',
        rows: 9,
        cols: 9,
        moves: 27,
        colorCount: 5,
        seed: 1008,
        ingredientDropColumn: 1,
        jellyCount: 4,
        objectives: const <LevelObjective>[
          LevelObjective(
              type: ObjectiveType.ingredient, target: 4, label: 'Jelly'),
        ],
        stars: const StarThresholds(one: 7000, two: 13000, three: 19000),
      ),
      // 9: frosting ring around a hole.
      LevelData(
        id: 9,
        name: 'Frozen Crown',
        rows: 9,
        cols: 9,
        moves: 26,
        colorCount: 6,
        seed: 1009,
        blockedCells: _crossHoles(9, 9),
        blockers: _frostingPatch(3, 3, 3, 3),
        objectives: const <LevelObjective>[
          LevelObjective(
              type: ObjectiveType.frosting, target: 9, label: 'Frosting'),
        ],
        stars: const StarThresholds(one: 8000, two: 14000, three: 20000),
      ),
      // 10: the graduation level, three objectives at once.
      LevelData(
        id: 10,
        name: 'Candy Cascade',
        rows: 9,
        cols: 9,
        moves: 30,
        colorCount: 6,
        seed: 1010,
        ingredientDropColumn: 4,
        jellyCount: 2,
        blockers: _frostingPatch(2, 2, 5, 5),
        objectives: const <LevelObjective>[
          LevelObjective(
              type: ObjectiveType.frosting, target: 25, label: 'Frosting'),
          LevelObjective(
              type: ObjectiveType.ingredient, target: 2, label: 'Jelly'),
          LevelObjective(
              type: ObjectiveType.score, target: 15000, label: 'Score'),
        ],
        stars: const StarThresholds(one: 15000, two: 24000, three: 34000),
      ),
    ];
  }

  /// Frosting rectangle covering [height] rows from [topRow], [width] columns
  /// from [leftCol].
  static List<BlockerCell> _frostingPatch(
      int topRow, int leftCol, int height, int width,
      {int hp = 1}) {
    final List<BlockerCell> out = <BlockerCell>[];
    for (int r = topRow; r < topRow + height; r++) {
      for (int c = leftCol; c < leftCol + width; c++) {
        out.add(BlockerCell(row: r, col: c, hp: hp, maxHp: hp));
      }
    }
    return out;
  }

  /// A ring of holes shaped like a diamond, used to break up flat boards.
  static Set<int> _diamondHoles(int rows, int cols) {
    final Set<int> holes = <int>{};
    final int cr = rows ~/ 2;
    final int cc = cols ~/ 2;
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final int d = (r - cr).abs() + (c - cc).abs();
        if (d == 1) holes.add(r * cols + c);
      }
    }
    return holes;
  }

  /// A plus sign of holes, one row and one column through the centre.
  static Set<int> _crossHoles(int rows, int cols) {
    final Set<int> holes = <int>{};
    final int cr = rows ~/ 2;
    final int cc = cols ~/ 2;
    for (int c = 1; c < cols - 1; c++) {
      holes.add(cr * cols + c);
    }
    for (int r = 1; r < rows - 1; r++) {
      holes.add(r * cols + cc);
    }
    return holes;
  }

  /// Endless generator for levels past the hand crafted set.
  ///
  /// Difficulty ramps every level and resets to an easier band every ten, so
  /// the curve is a sawtooth rather than a wall.
  static LevelData generate(int id) {
    final int band = (id - handCraftedCount - 1) % 10; // 0..9 inside the band
    final int tier = (id - handCraftedCount - 1) ~/ 10; // how many bands deep
    final int ramp = band + tier * 2;

    final int colorCount = ramp < 3 ? 5 : 6;
    final int moves = 30 - (ramp ~/ 2).clamp(0, 8);
    final int scoreTarget = 8000 + ramp * 1500 + tier * 2000;

    final List<LevelObjective> objectives = <LevelObjective>[
      LevelObjective(
          type: ObjectiveType.score, target: scoreTarget, label: 'Score'),
    ];

    List<BlockerCell> blockers = const <BlockerCell>[];
    Set<int> holes = const <int>{};
    int? ingredientCol;
    int jelly = 0;

    switch (band % 4) {
      case 0:
        // Score only, occasionally with holes.
        if (ramp.isOdd) holes = _diamondHoles(9, 9);
        break;
      case 1:
        final int side = 3 + (ramp % 3);
        blockers = _frostingPatch(4 - side ~/ 2, 4 - side ~/ 2, side, side,
            hp: ramp > 6 ? 2 : 1);
        objectives.add(LevelObjective(
          type: ObjectiveType.frosting,
          target: blockers.length,
          label: 'Frosting',
        ));
        break;
      case 2:
        jelly = 2 + (ramp % 3);
        ingredientCol = id % 9;
        objectives.add(LevelObjective(
          type: ObjectiveType.ingredient,
          target: jelly,
          label: 'Jelly',
        ));
        break;
      case 3:
        const int side = 4;
        blockers = _frostingPatch(3, 3, side, side, hp: ramp > 5 ? 2 : 1);
        jelly = 2;
        ingredientCol = (id * 3) % 9;
        holes = _crossHoles(9, 9);
        objectives.add(LevelObjective(
          type: ObjectiveType.frosting,
          target: blockers.length,
          label: 'Frosting',
        ));
        objectives.add(LevelObjective(
          type: ObjectiveType.ingredient,
          target: jelly,
          label: 'Jelly',
        ));
        break;
    }

    return LevelData(
      id: id,
      name: _nameFor(id),
      rows: 9,
      cols: 9,
      moves: moves,
      colorCount: colorCount,
      seed: 7000 + id,
      blockers: blockers,
      blockedCells: holes,
      ingredientDropColumn: ingredientCol,
      jellyCount: jelly,
      objectives: objectives,
      stars: StarThresholds(
        one: scoreTarget,
        two: (scoreTarget * 1.6).round(),
        three: (scoreTarget * 2.4).round(),
      ),
    );
  }

  static const List<String> _prefix = <String>[
    'Sugar',
    'Gummy',
    'Fizzy',
    'Jelly',
    'Toffee',
    'Sherbet',
    'Bonbon',
    'Marshmallow',
    'Lollipop',
    'Caramel',
    'Nougat',
    'Truffle',
    'Waffle',
  ];
  static const List<String> _suffix = <String>[
    'Cascade',
    'Rush',
    'Falls',
    'Blast',
    'Crunch',
    'Storm',
    'Drop',
    'Swirl',
    'Pop',
    'Frenzy',
    'Bounce',
    'Melt',
    'Twist',
  ];

  static String _nameFor(int id) {
    final String a = _prefix[(id * 7) % _prefix.length];
    final String b = _suffix[(id * 5) % _suffix.length];
    return '$a $b';
  }
}
