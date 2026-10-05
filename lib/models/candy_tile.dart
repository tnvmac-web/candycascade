import 'dart:ui';

/// The six playable candy colours. [CandyColorType.none] is used for cells that
/// hold no candy at all (a hole in the board, or a blocker cell).
enum CandyColorType { red, orange, yellow, green, blue, purple, none }

/// Every special candy the engine can spawn.
///
/// * [stripedHorizontal] / [stripedVertical] come from a straight match of 4.
/// * [wrapped] comes from an L or T shaped match of 5.
/// * [rainbow] comes from a straight match of 5.
/// * [jelly] is not a candy you can match: it is the objective token that must
///   be walked to the bottom row (ingredient drop levels).
enum SpecialType {
  none,
  stripedHorizontal,
  stripedVertical,
  wrapped,
  rainbow,
  jelly
}

/// Static colour / sprite metadata for a candy colour.
class CandyPalette {
  CandyPalette._();

  static const Map<CandyColorType, Color> colors = <CandyColorType, Color>{
    CandyColorType.red: Color(0xFFE8443A),
    CandyColorType.orange: Color(0xFFF58A28),
    CandyColorType.yellow: Color(0xFFF7D23E),
    CandyColorType.green: Color(0xFF4CBF4C),
    CandyColorType.blue: Color(0xFF3D8BEF),
    CandyColorType.purple: Color(0xFF9B51E0),
    CandyColorType.none: Color(0x00000000),
  };

  static const Map<CandyColorType, Color> dark = <CandyColorType, Color>{
    CandyColorType.red: Color(0xFF9E241C),
    CandyColorType.orange: Color(0xFFA6520E),
    CandyColorType.yellow: Color(0xFFB08A0C),
    CandyColorType.green: Color(0xFF257A25),
    CandyColorType.blue: Color(0xFF1B4E96),
    CandyColorType.purple: Color(0xFF5B2A8C),
    CandyColorType.none: Color(0x00000000),
  };

  static const Map<CandyColorType, Color> light = <CandyColorType, Color>{
    CandyColorType.red: Color(0xFFFF9C93),
    CandyColorType.orange: Color(0xFFFFC38A),
    CandyColorType.yellow: Color(0xFFFFF0A6),
    CandyColorType.green: Color(0xFFA6E8A6),
    CandyColorType.blue: Color(0xFFA9CCFF),
    CandyColorType.purple: Color(0xFFD7B4F5),
    CandyColorType.none: Color(0x00000000),
  };

  /// The colours the level generator may pick from.
  static const List<CandyColorType> playable = <CandyColorType>[
    CandyColorType.red,
    CandyColorType.orange,
    CandyColorType.yellow,
    CandyColorType.green,
    CandyColorType.blue,
    CandyColorType.purple,
  ];

  static Color color(CandyColorType t) => colors[t] ?? const Color(0x00000000);
  static Color darkOf(CandyColorType t) => dark[t] ?? const Color(0x00000000);
  static Color lightOf(CandyColorType t) => light[t] ?? const Color(0x00000000);
}

/// A single square on the board.
///
/// [row]/[col] are grid coordinates, never pixels. Pixel placement is computed
/// by the board view from the current cell size so the model stays free of any
/// layout concerns.
class CandyTile {
  CandyTile({
    required this.row,
    required this.col,
    required this.color,
    this.special = SpecialType.none,
    this.id = -1,
    this.animX = 0,
    this.animY = 0,
    this.scale = 1.0,
    this.opacity = 1.0,
    this.isFalling = false,
  });

  /// Grid row, 0 is the top row.
  int row;

  /// Grid column, 0 is the left column.
  int col;

  /// Matchable colour. [CandyColorType.none] means "no candy here".
  CandyColorType color;

  /// Special behaviour attached to this candy.
  SpecialType special;

  /// Stable identity, used by the view to diff tiles between frames so the
  /// animation layer can follow the same candy as it falls.
  int id;

  /// Animation offset in cell units, applied on top of [row]/[col].
  /// Negative Y is up, positive Y is down.
  double animX;
  double animY;

  /// Visual scale, 1.0 is natural size. Used for the pop/burst animation.
  double scale;

  /// Visual opacity, 1.0 is fully visible. Fades out on clear.
  double opacity;

  /// True while this tile is travelling between two rows.
  bool isFalling;

  bool get isEmpty => color == CandyColorType.none;

  bool get isSpecial => special != SpecialType.none;

  bool get isJelly => special == SpecialType.jelly;

  bool get isRainbow => special == SpecialType.rainbow;

  bool get isWrapped => special == SpecialType.wrapped;

  bool get isStriped =>
      special == SpecialType.stripedHorizontal ||
      special == SpecialType.stripedVertical;

  /// A rainbow bomb is the only special that has no colour of its own.
  bool get isColorless => color == CandyColorType.none;

  CandyTile copyWith({
    int? row,
    int? col,
    CandyColorType? color,
    SpecialType? special,
    int? id,
    double? animX,
    double? animY,
    double? scale,
    double? opacity,
    bool? isFalling,
  }) {
    return CandyTile(
      row: row ?? this.row,
      col: col ?? this.col,
      color: color ?? this.color,
      special: special ?? this.special,
      id: id ?? this.id,
      animX: animX ?? this.animX,
      animY: animY ?? this.animY,
      scale: scale ?? this.scale,
      opacity: opacity ?? this.opacity,
      isFalling: isFalling ?? this.isFalling,
    );
  }

  /// Resets every transient animation value. Called at the start of a frame.
  void resetAnimation() {
    animX = 0;
    animY = 0;
    scale = 1.0;
    opacity = 1.0;
    isFalling = false;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'r': row,
        'c': col,
        'col': color.index,
        'sp': special.index,
        'id': id,
      };

  static CandyTile fromJson(Map<String, dynamic> j) => CandyTile(
        row: j['r'] as int,
        col: j['c'] as int,
        color: CandyColorType.values[j['col'] as int],
        special: SpecialType.values[j['sp'] as int],
        id: j['id'] as int? ?? -1,
      );

  @override
  String toString() => 'CandyTile($row,$col ${color.name}/${special.name})';
}

/// A cell that is blocked until enough adjacent matches happen next to it.
/// Frosting and ice breaker levels use this.
class BlockerCell {
  BlockerCell(
      {required this.row, required this.col, this.hp = 1, this.maxHp = 1});

  final int row;
  final int col;

  /// Remaining hits before the blocker breaks.
  int hp;

  /// Hits the blocker started with, used to draw cracks.
  final int maxHp;

  bool get isBroken => hp <= 0;

  /// How cracked the ice looks, 0.0 is pristine, 1.0 is about to break.
  double get damageRatio => maxHp <= 0 ? 1.0 : 1.0 - (hp / maxHp);

  Map<String, dynamic> toJson() =>
      <String, dynamic>{'r': row, 'c': col, 'hp': hp, 'm': maxHp};

  static BlockerCell fromJson(Map<String, dynamic> j) => BlockerCell(
      row: j['r'] as int,
      col: j['c'] as int,
      hp: j['hp'] as int,
      maxHp: j['m'] as int);
}
