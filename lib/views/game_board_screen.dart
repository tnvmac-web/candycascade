import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logic/game_controller.dart';
import '../logic/match_engine.dart';
import '../logic/providers.dart';
import '../models/candy_tile.dart';
import '../services/ad_service.dart';
import '../services/audio_service.dart';
import 'ui_overlays.dart';

/// Colours used across the game chrome. One place so the whole app stays on
/// brand: candy pink shell, deep berry background, gold for rewards.
class GameColors {
  GameColors._();

  static const Color bgTop = Color(0xFF3A1E5C);
  static const Color bgBottom = Color(0xFF1B0B33);
  static const Color panel = Color(0xFF4A2A78);
  static const Color panelDark = Color(0xFF2E1A4D);
  static const Color accent = Color(0xFFFF4E8B);
  static const Color accentDark = Color(0xFFB02358);
  static const Color gold = Color(0xFFFFC53D);
  static const Color goldDark = Color(0xFFC98A0B);
  static const Color mint = Color(0xFF4CE0B3);
  static const Color boardFrame = Color(0xFF2A1746);
  static const Color cellA = Color(0xFF3B2260);
  static const Color cellB = Color(0xFF341E56);
  static const Color ice = Color(0xFF9FD8F5);
  static const Color iceCrack = Color(0xFF5FA8D3);
  static const Color textLight = Color(0xFFFFF6FB);
}

/// The full screen for playing a level: HUD, board, boosters, dialogs.
class GameBoardScreen extends ConsumerStatefulWidget {
  const GameBoardScreen({super.key, required this.levelId});

  final int levelId;

  @override
  ConsumerState<GameBoardScreen> createState() => _GameBoardScreenState();
}

class _GameBoardScreenState extends ConsumerState<GameBoardScreen>
    with WidgetsBindingObserver {
  bool _started = false;
  bool _resultShown = false;
  bool _rewardedBusy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (_started) return;
    _started = true;
    final GameController controller = ref.read(gameControllerProvider.notifier);
    final bool ok = await controller.startLevel(widget.levelId);
    if (!ok && mounted) {
      // Out of lives: bounce back with a clear message.
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Out of lives. Wait for one to refill, or watch an ad.')),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final GameController controller = ref.read(gameControllerProvider.notifier);
    if (state == AppLifecycleState.resumed) {
      controller.onResume();
      AudioService.instance.resumeMusic();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      AudioService.instance.pauseMusic();
    }
  }

  @override
  Widget build(BuildContext context) {
    final GameState? game = ref.watch(gameControllerProvider);

    if (game == null) {
      return const Scaffold(
        backgroundColor: GameColors.bgBottom,
        body:
            Center(child: CircularProgressIndicator(color: GameColors.accent)),
      );
    }

    // Show the result dialog exactly once per attempt.
    if (!_resultShown &&
        (game.phase == GamePhase.won || game.phase == GamePhase.lost)) {
      _resultShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _showResult(game));
    }
    if (game.phase == GamePhase.playing) {
      _resultShown = false;
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return;
        final bool leave = await showQuitDialog(context);
        if (leave && mounted) {
          ref.read(gameControllerProvider.notifier).quitLevel();
          if (mounted) Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: GameColors.bgBottom,
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[GameColors.bgTop, GameColors.bgBottom],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: <Widget>[
                LevelGoalBar(game: game, onPause: () => _onPause(game)),
                Expanded(child: Center(child: GameBoardView(game: game))),
                BoosterBar(game: game),
                const SizedBox(height: 6),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _onPause(GameState game) async {
    final GameController controller = ref.read(gameControllerProvider.notifier);
    final PauseAction? action = await showPauseMenu(context, game);
    if (!mounted || action == null) return;
    switch (action) {
      case PauseAction.resume:
        break;
      case PauseAction.restart:
        controller.restartLevel();
        break;
      case PauseAction.quit:
        controller.quitLevel();
        Navigator.of(context).pop();
        break;
    }
  }

  Future<void> _showResult(GameState game) async {
    if (!mounted) return;
    final GameController controller = ref.read(gameControllerProvider.notifier);
    final AdServiceLike ads = AdServiceLike(ref);

    if (game.phase == GamePhase.won) {
      final ResultAction? action = await showWinDialog(context, game);
      if (!mounted || action == null) return;
      // Interstitial every second or third level, and never right after a
      // purchase of remove ads.
      await ads.maybeShowInterstitial();
      if (!mounted) return;
      switch (action) {
        case ResultAction.next:
          await controller.nextLevel();
          break;
        case ResultAction.replay:
          await controller.restartLevel();
          break;
        case ResultAction.map:
          controller.quitLevel();
          Navigator.of(context).pop();
          break;
      }
    } else {
      final ResultAction? action = await showLoseDialog(
        context,
        game,
        onWatchAd: () async {
          if (_rewardedBusy) return false;
          _rewardedBusy = true;
          final RewardOutcomeLike outcome = await ads.showRewarded();
          _rewardedBusy = false;
          if (outcome == RewardOutcomeLike.earned) {
            controller.grantRewardedMoves(5);
            return true;
          }
          return false;
        },
        onBuyMoves: () => controller.continueWithCoins(150, 5),
      );
      if (!mounted || action == null) return;
      switch (action) {
        case ResultAction.replay:
          await controller.restartLevel();
          break;
        case ResultAction.next:
        case ResultAction.map:
          controller.quitLevel();
          Navigator.of(context).pop();
          break;
      }
    }
  }
}

/// Small adapter so the screen does not need to know the ad service shape.
class AdServiceLike {
  AdServiceLike(this.ref);

  final WidgetRef ref;

  Future<void> maybeShowInterstitial() async {
    await ref.read(adProvider).maybeShowInterstitial();
  }

  Future<RewardOutcomeLike> showRewarded() async {
    final RewardOutcome outcome = await ref.read(adProvider).showRewarded();
    switch (outcome) {
      case RewardOutcome.earned:
        return RewardOutcomeLike.earned;
      case RewardOutcome.notReady:
        return RewardOutcomeLike.notReady;
      case RewardOutcome.dismissed:
        return RewardOutcomeLike.dismissed;
      case RewardOutcome.failed:
        return RewardOutcomeLike.failed;
    }
  }
}

enum RewardOutcomeLike { earned, dismissed, failed, notReady }

// -----------------------------------------------------------------------------
// Board view
// -----------------------------------------------------------------------------

/// Renders the grid and handles drag to swap, tap for boosters.
///
/// The board is painted by a single [CustomPainter] inside a [RepaintBoundary],
/// so a cascade repaints one layer instead of rebuilding a widget tree. That is
/// what keeps budget devices at frame rate.
class GameBoardView extends ConsumerStatefulWidget {
  const GameBoardView({super.key, required this.game});

  final GameState game;

  @override
  ConsumerState<GameBoardView> createState() => _GameBoardViewState();
}

class _GameBoardViewState extends ConsumerState<GameBoardView>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;

  /// Per tile id, the offset (in cells) it started this fall from.
  final Map<int, double> _fallFrom = <int, double>{};
  final Map<int, double> _fallProgress = <int, double>{};

  /// Per tile id, 0 to 1 spawn scale in.
  final Map<int, double> _spawnProgress = <int, double>{};

  /// Per tile id, 0 to 1 clear shrink out.
  final Map<int, double> _clearProgress = <int, double>{};

  final List<_Particle> _particles = <_Particle>[];
  final List<_FloatingText> _popups = <_FloatingText>[];

  int? _selectedIndex;
  Offset? _dragStart;
  int? _dragStartIndex;

  final math.Random _rng = math.Random();

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final double dt = _lastTick == Duration.zero
        ? 1 / 60
        : ((elapsed - _lastTick).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _lastTick = elapsed;

    bool needsRepaint = false;

    // Fall animation: 4 cells per second squared style ease, capped.
    for (final int id in _fallProgress.keys.toList()) {
      final double speed = 3.4 + _fallFrom[id]!.abs() * 0.9;
      _fallProgress[id] = (_fallProgress[id]! + dt * speed).clamp(0.0, 1.0);
      needsRepaint = true;
      if (_fallProgress[id]! >= 1.0) {
        _fallProgress.remove(id);
        _fallFrom.remove(id);
      }
    }

    for (final int id in _spawnProgress.keys.toList()) {
      _spawnProgress[id] = (_spawnProgress[id]! + dt * 5.0).clamp(0.0, 1.0);
      needsRepaint = true;
      if (_spawnProgress[id]! >= 1.0) _spawnProgress.remove(id);
    }

    for (final int id in _clearProgress.keys.toList()) {
      _clearProgress[id] = (_clearProgress[id]! + dt * 6.0).clamp(0.0, 1.0);
      needsRepaint = true;
      if (_clearProgress[id]! >= 1.0) _clearProgress.remove(id);
    }

    if (_particles.isNotEmpty) {
      needsRepaint = true;
      for (final _Particle p in _particles) {
        p.x += p.vx * dt;
        p.y += p.vy * dt;
        p.vy += 900 * dt;
        p.vx *= 0.985;
        p.life -= dt;
      }
      _particles.removeWhere((_Particle p) => p.life <= 0);
    }

    if (_popups.isNotEmpty) {
      needsRepaint = true;
      for (final _FloatingText t in _popups) {
        t.row -= 46 * dt;
        t.life -= dt;
      }
      _popups.removeWhere((_FloatingText t) => t.life <= 0);
    }

    if (needsRepaint && mounted) setState(() {});
  }

  /// Reacts to a new game state: registers fall, spawn and clear animations and
  /// spawns particles for whatever was cleared.
  @override
  void didUpdateWidget(covariant GameBoardView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _consumeEffects(widget.game);
  }

  void _consumeEffects(GameState game) {
    // Falls.
    for (final DropRecord d in game.lastDrops) {
      if (!_fallFrom.containsKey(d.tileId)) {
        _fallFrom[d.tileId] = (d.fromRow - d.toRow).toDouble();
        _fallProgress[d.tileId] = 0.0;
      }
    }

    // Spawns: any tile that is falling in from above the board.
    for (final CandyTile? t in game.board) {
      if (t == null) continue;
      if (t.animY < 0 &&
          !_spawnProgress.containsKey(t.id) &&
          !_fallProgress.containsKey(t.id)) {
        _spawnProgress[t.id] = 0.0;
      }
    }

    // Clears.
    final EffectRequest? fx = game.effects;
    if (fx != null && fx.cleared.isNotEmpty) {
      for (final ClearedCandy c in fx.cleared) {
        _spawnParticles(c);
      }
      if (fx.score > 0) {
        final double avgRow = fx.cleared
                .map((ClearedCandy c) => c.row)
                .reduce((int a, int b) => a + b) /
            fx.cleared.length;
        final double avgCol = fx.cleared
                .map((ClearedCandy c) => c.col)
                .reduce((int a, int b) => a + b) /
            fx.cleared.length;
        _popups.add(_FloatingText(
          row: avgRow,
          col: avgCol,
          text: fx.cascadeIndex > 0
              ? '+${fx.score} x${fx.cascadeIndex + 1}'
              : '+${fx.score}',
          color: fx.cascadeIndex > 0 ? GameColors.gold : GameColors.textLight,
        ));
      }
      if (fx.blasts.isNotEmpty) {
        for (final int idx in fx.blasts) {
          _popups.add(_FloatingText(
            row: (idx ~/ game.cols).toDouble(),
            col: (idx % game.cols).toDouble(),
            text: 'BOOM!',
            color: GameColors.accent,
            life: 0.7,
          ));
        }
      }
    }
  }

  void _spawnParticles(ClearedCandy c) {
    final int count = c.special == SpecialType.none ? 5 : 10;
    for (int i = 0; i < count; i++) {
      final double angle = _rng.nextDouble() * math.pi * 2;
      final double speed = 90 + _rng.nextDouble() * 240;
      _particles.add(_Particle(
        x: c.col + 0.5,
        y: c.row + 0.5,
        vx: math.cos(angle) * speed,
        vy: math.sin(angle) * speed - 80,
        life: 0.45 + _rng.nextDouble() * 0.35,
        maxLife: 0.8,
        color: CandyPalette.color(
            c.color == CandyColorType.none ? CandyColorType.yellow : c.color),
        size: 0.10 + _rng.nextDouble() * 0.10,
      ));
    }
  }

  // ---------------------------------------------------------------------------
  // Gestures
  // ---------------------------------------------------------------------------

  int? _cellAt(Offset local, double cell, int rows, int cols) {
    final int c = (local.dx / cell).floor();
    final int r = (local.dy / cell).floor();
    if (r < 0 || r >= rows || c < 0 || c >= cols) return null;
    return r * cols + c;
  }

  void _onPanStart(DragStartDetails d, double cell, int rows, int cols) {
    if (widget.game.busy) return;
    _dragStart = d.localPosition;
    _dragStartIndex = _cellAt(d.localPosition, cell, rows, cols);
    setState(() => _selectedIndex = _dragStartIndex);
  }

  void _onPanUpdate(DragUpdateDetails d, double cell, int rows, int cols) {
    final Offset? start = _dragStart;
    final int? startIdx = _dragStartIndex;
    if (start == null || startIdx == null) return;
    if (widget.game.busy) return;

    final Offset delta = d.localPosition - start;
    // Require a decisive drag so a sloppy tap does not swap.
    if (delta.distance < cell * 0.45) return;

    int dr = 0;
    int dc = 0;
    if (delta.dx.abs() > delta.dy.abs()) {
      dc = delta.dx > 0 ? 1 : -1;
    } else {
      dr = delta.dy > 0 ? 1 : -1;
    }

    final int r = startIdx ~/ cols;
    final int c = startIdx % cols;
    final int tr = r + dr;
    final int tc = c + dc;
    _dragStart = null;
    _dragStartIndex = null;
    setState(() => _selectedIndex = null);
    if (tr < 0 || tr >= rows || tc < 0 || tc >= cols) return;
    ref.read(gameControllerProvider.notifier).onSwap(r, c, tr, tc);
  }

  void _onPanEnd(DragEndDetails d) {
    _dragStart = null;
    _dragStartIndex = null;
    if (mounted) setState(() => _selectedIndex = null);
  }

  void _onTapUp(TapUpDetails d, double cell, int rows, int cols) {
    if (widget.game.busy) return;
    final int? idx = _cellAt(d.localPosition, cell, rows, cols);
    if (idx == null) return;
    final GameState game = widget.game;
    final GameController controller = ref.read(gameControllerProvider.notifier);

    if (game.booster != BoosterMode.none) {
      controller.onCellTap(idx ~/ cols, idx % cols);
      return;
    }

    // Tap to select, tap an adjacent cell to swap.
    if (_selectedIndex == null) {
      setState(() => _selectedIndex = idx);
      AudioService.instance.hapticSelection();
      return;
    }
    if (_selectedIndex == idx) {
      setState(() => _selectedIndex = null);
      return;
    }
    final int r1 = _selectedIndex! ~/ cols;
    final int c1 = _selectedIndex! % cols;
    final int r2 = idx ~/ cols;
    final int c2 = idx % cols;
    setState(() => _selectedIndex = null);
    if ((r1 - r2).abs() + (c1 - c2).abs() == 1) {
      controller.onSwap(r1, c1, r2, c2);
    } else {
      controller.cancelBooster();
    }
  }

  @override
  Widget build(BuildContext context) {
    final GameState game = widget.game;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double boardWidth =
            math.min(constraints.maxWidth, constraints.maxHeight);
        final double cell = boardWidth / game.cols;
        final double boardHeight = cell * game.rows;

        return SizedBox(
          width: boardWidth,
          height: boardHeight,
          child: RepaintBoundary(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (DragStartDetails d) =>
                  _onPanStart(d, cell, game.rows, game.cols),
              onPanUpdate: (DragUpdateDetails d) =>
                  _onPanUpdate(d, cell, game.rows, game.cols),
              onPanEnd: _onPanEnd,
              onTapUp: (TapUpDetails d) =>
                  _onTapUp(d, cell, game.rows, game.cols),
              child: Stack(
                children: <Widget>[
                  CustomPaint(
                    size: Size(boardWidth, boardHeight),
                    painter: _BoardPainter(
                      game: game,
                      cell: cell,
                      selected: _selectedIndex,
                      fallFrom: Map<int, double>.from(_fallFrom),
                      fallProgress: Map<int, double>.from(_fallProgress),
                      spawnProgress: Map<int, double>.from(_spawnProgress),
                      clearProgress: Map<int, double>.from(_clearProgress),
                      particles: List<_Particle>.from(_particles),
                      popups: List<_FloatingText>.from(_popups),
                      rng: _rng,
                    ),
                  ),
                  if (game.comboMessage != null &&
                      game.comboMessage!.isNotEmpty)
                    Positioned(
                      top: boardHeight * 0.36,
                      left: 0,
                      right: 0,
                      child: IgnorePointer(
                        child: _ComboBanner(text: game.comboMessage!),
                      ),
                    ),
                  if (game.busy)
                    const Positioned(
                      right: 8,
                      top: 8,
                      child: IgnorePointer(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: GameColors.mint,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// Particles and popups
// -----------------------------------------------------------------------------

class _Particle {
  _Particle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.life,
    required this.maxLife,
    required this.color,
    required this.size,
  });

  /// Position in cell units.
  double x;
  double y;

  /// Velocity in cell units per second.
  double vx;
  double vy;

  double life;
  double maxLife;
  Color color;

  /// Radius in cell units.
  double size;
}

class _FloatingText {
  _FloatingText({
    required this.row,
    required this.col,
    required this.text,
    required this.color,
    this.life = 0.9,
  });

  /// Position in cell units. [row] is animated upward as the text ages.
  double row;
  double col;
  String text;
  Color color;
  double life;
}

// -----------------------------------------------------------------------------
// Painter
// -----------------------------------------------------------------------------

/// Paints the whole board in one pass.
class _BoardPainter extends CustomPainter {
  _BoardPainter({
    required this.game,
    required this.cell,
    required this.selected,
    required this.fallFrom,
    required this.fallProgress,
    required this.spawnProgress,
    required this.clearProgress,
    required this.particles,
    required this.popups,
    required this.rng,
  });

  final GameState game;
  final double cell;
  final int? selected;
  final Map<int, double> fallFrom;
  final Map<int, double> fallProgress;
  final Map<int, double> spawnProgress;
  final Map<int, double> clearProgress;
  final List<_Particle> particles;
  final List<_FloatingText> popups;
  final math.Random rng;

  @override
  void paint(Canvas canvas, Size size) {
    _paintBackground(canvas, size);
    _paintCells(canvas);
    _paintBlockers(canvas);
    _paintSelection(canvas);
    _paintCandies(canvas);
    _paintParticles(canvas);
    _paintPopups(canvas);
  }

  void _paintBackground(Canvas canvas, Size size) {
    final Rect board = Rect.fromLTWH(0, 0, size.width, size.height);
    final RRect frame =
        RRect.fromRectAndRadius(board, const Radius.circular(18));
    canvas.drawRRect(frame, Paint()..color = GameColors.boardFrame);
    canvas.save();
    canvas.clipRRect(frame);
    canvas.drawRRect(
      frame.deflate(3),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[GameColors.panelDark, Color(0xFF231340)],
        ).createShader(board),
    );
    canvas.restore();
  }

  void _paintCells(Canvas canvas) {
    for (int r = 0; r < game.rows; r++) {
      for (int c = 0; c < game.cols; c++) {
        if (game.level.isHole(r, c)) continue;
        final Rect rect = _cellRect(r, c).deflate(cell * 0.045);
        final RRect rr =
            RRect.fromRectAndRadius(rect, Radius.circular(cell * 0.22));
        final bool checker = (r + c) % 2 == 0;
        canvas.drawRRect(
          rr,
          Paint()..color = checker ? GameColors.cellA : GameColors.cellB,
        );
      }
    }
  }

  void _paintBlockers(Canvas canvas) {
    for (final BlockerCell b in game.level.blockers) {
      if (b.isBroken) continue;
      final Rect rect = _cellRect(b.row, b.col).deflate(cell * 0.03);
      final RRect rr =
          RRect.fromRectAndRadius(rect, Radius.circular(cell * 0.2));
      final double damage = b.damageRatio;
      canvas.drawRRect(
        rr,
        Paint()..color = GameColors.ice.withValues(alpha: 0.42 + damage * 0.1),
      );
      canvas.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = cell * 0.055
          ..color = GameColors.iceCrack.withValues(alpha: 0.9),
      );
      // Cracks grow as the ice takes damage.
      if (damage > 0.01) {
        final Paint crack = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = cell * 0.035
          ..strokeCap = StrokeCap.round
          ..color = GameColors.iceCrack.withValues(alpha: 0.85);
        final Path p = Path();
        final Offset o = rect.topLeft;
        p.moveTo(o.dx + rect.width * 0.22, o.dy + rect.height * 0.14);
        p.lineTo(o.dx + rect.width * (0.44 + damage * 0.1),
            o.dy + rect.height * 0.5);
        p.lineTo(o.dx + rect.width * 0.24, o.dy + rect.height * 0.86);
        if (damage > 0.5) {
          p.moveTo(o.dx + rect.width * 0.5, o.dy + rect.height * 0.5);
          p.lineTo(o.dx + rect.width * 0.86, o.dy + rect.height * 0.34);
        }
        canvas.drawPath(p, crack);
      }
    }
  }

  void _paintSelection(Canvas canvas) {
    final int? idx = selected;
    if (idx == null) return;
    final int r = idx ~/ game.cols;
    final int c = idx % game.cols;
    final Rect rect = _cellRect(r, c).deflate(cell * 0.02);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(cell * 0.24)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = cell * 0.08
        ..color = GameColors.gold,
    );
    // Booster targeting ring.
    if (game.booster != BoosterMode.none) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            rect.inflate(cell * 0.06), Radius.circular(cell * 0.28)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = cell * 0.03
          ..color = GameColors.accent,
      );
    }
  }

  void _paintCandies(Canvas canvas) {
    // The hint pulse uses a shared clock so both cells breathe together.
    final double hintPulse =
        0.5 + 0.5 * math.sin(DateTime.now().millisecondsSinceEpoch / 260.0);

    for (int r = 0; r < game.rows; r++) {
      for (int c = 0; c < game.cols; c++) {
        final CandyTile? t = game.at(r, c);
        if (t == null) continue;
        if (t.color == CandyColorType.none && !t.isRainbow && !t.isJelly) {
          continue;
        }

        double y = r.toDouble();
        final double x = c.toDouble();
        double scale = 1.0;

        // Falling: interpolate from where it started to where it is now.
        final double? from = fallFrom[t.id];
        final double? prog = fallProgress[t.id];
        if (from != null && prog != null) {
          final double eased = _easeOutCubic(prog);
          y = r - from * (1 - eased);
        } else if (t.animY < 0) {
          // Refilled candy entering from above.
          final double p = spawnProgress[t.id] ?? 1.0;
          y = r + t.animY * (1 - _easeOutCubic(p));
        }

        final double? spawn = spawnProgress[t.id];
        if (spawn != null && from == null) {
          scale = 0.55 + 0.45 * _easeOutBack(spawn);
        }

        final double? clear = clearProgress[t.id];
        if (clear != null) {
          scale = 1.0 + clear * 0.35;
        }

        final Rect rect =
            Rect.fromLTWH(x * cell, y * cell, cell, cell).deflate(cell * 0.075);
        final bool highlighted = game.hint != null &&
            (game.hint![0] == r * game.cols + c ||
                game.hint![1] == r * game.cols + c);
        if (highlighted) {
          final Rect ring = _cellRect(r, c).deflate(cell * 0.03);
          canvas.drawRRect(
            RRect.fromRectAndRadius(ring, Radius.circular(cell * 0.24)),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = cell * 0.06
              ..color =
                  GameColors.mint.withValues(alpha: 0.35 + hintPulse * 0.5),
          );
        }

        _drawCandy(canvas, rect, t, scale);
      }
    }
  }

  void _drawCandy(Canvas canvas, Rect rect, CandyTile t, double scale) {
    final Offset center = rect.center;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(scale);
    canvas.translate(-center.dx, -center.dy);

    if (t.isJelly) {
      _drawJelly(canvas, rect);
    } else if (t.isRainbow) {
      _drawRainbow(canvas, rect);
    } else {
      _drawBaseCandy(canvas, rect, t.color);
      if (t.special == SpecialType.stripedHorizontal) {
        _drawStripes(canvas, rect, horizontal: true);
      } else if (t.special == SpecialType.stripedVertical) {
        _drawStripes(canvas, rect, horizontal: false);
      } else if (t.special == SpecialType.wrapped) {
        _drawWrapper(canvas, rect, t.color);
      }
    }

    canvas.restore();
  }

  void _drawBaseCandy(Canvas canvas, Rect rect, CandyColorType color) {
    final RRect rr =
        RRect.fromRectAndRadius(rect, Radius.circular(rect.width * 0.3));
    // Drop shadow.
    canvas.drawRRect(
      rr.shift(Offset(0, rect.height * 0.06)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    // Body.
    canvas.drawRRect(
      rr,
      Paint()
        ..shader = ui.Gradient.linear(
          rect.topLeft,
          rect.bottomRight,
          <Color>[
            CandyPalette.lightOf(color),
            CandyPalette.color(color),
            CandyPalette.darkOf(color),
          ],
          <double>[0.0, 0.55, 1.0],
        ),
    );
    // Gloss.
    final Rect gloss = Rect.fromLTWH(
      rect.left + rect.width * 0.16,
      rect.top + rect.height * 0.12,
      rect.width * 0.38,
      rect.height * 0.26,
    );
    canvas.drawOval(
      gloss,
      Paint()..color = Colors.white.withValues(alpha: 0.55),
    );
    // Rim light.
    canvas.drawRRect(
      rr.deflate(rect.width * 0.045),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = rect.width * 0.05
        ..color = Colors.white.withValues(alpha: 0.16),
    );
  }

  void _drawStripes(Canvas canvas, Rect rect, {required bool horizontal}) {
    final RRect rr =
        RRect.fromRectAndRadius(rect, Radius.circular(rect.width * 0.3));
    canvas.save();
    canvas.clipRRect(rr);
    final Paint p = Paint()
      ..color = Colors.white.withValues(alpha: 0.92)
      ..strokeWidth = rect.width * 0.1
      ..strokeCap = StrokeCap.round;
    if (horizontal) {
      for (int i = 0; i < 3; i++) {
        final double y = rect.top + rect.height * (0.28 + i * 0.22);
        canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), p);
      }
    } else {
      for (int i = 0; i < 3; i++) {
        final double x = rect.left + rect.width * (0.28 + i * 0.22);
        canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), p);
      }
    }
    canvas.restore();
  }

  void _drawWrapper(Canvas canvas, Rect rect, CandyColorType color) {
    final RRect rr =
        RRect.fromRectAndRadius(rect, Radius.circular(rect.width * 0.3));
    // A wrapped candy is the base candy with a bright ribbon cross on it.
    canvas.save();
    canvas.clipRRect(rr);
    final Paint band = Paint()..color = Colors.white.withValues(alpha: 0.85);
    canvas.drawRect(
      Rect.fromLTWH(rect.left, rect.center.dy - rect.height * 0.075, rect.width,
          rect.height * 0.15),
      band,
    );
    canvas.drawRect(
      Rect.fromLTWH(rect.center.dx - rect.width * 0.075, rect.top,
          rect.width * 0.15, rect.height),
      band,
    );
    canvas.restore();
    // Knot at the centre.
    canvas.drawCircle(
      rect.center,
      rect.width * 0.14,
      Paint()..color = CandyPalette.darkOf(color),
    );
    canvas.drawCircle(
      rect.center,
      rect.width * 0.08,
      Paint()..color = Colors.white.withValues(alpha: 0.9),
    );
  }

  void _drawRainbow(Canvas canvas, Rect rect) {
    final Offset center = rect.center;
    final double radius = rect.width * 0.5;
    canvas.drawCircle(
      center.translate(0, rect.height * 0.06),
      radius,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    final List<Color> wheel =
        CandyPalette.playable.map(CandyPalette.color).toList();
    final Rect oval = Rect.fromCircle(center: center, radius: radius);
    final SweepGradient sweep =
        SweepGradient(colors: <Color>[...wheel, wheel.first]);
    canvas.drawCircle(
        center, radius, Paint()..shader = sweep.createShader(oval));
    // Sparkle ring.
    canvas.drawCircle(
      center,
      radius * 0.62,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = rect.width * 0.06
        ..color = Colors.white.withValues(alpha: 0.75),
    );
    canvas.drawCircle(
      center.translate(-radius * 0.22, -radius * 0.22),
      radius * 0.2,
      Paint()..color = Colors.white.withValues(alpha: 0.9),
    );
  }

  void _drawJelly(Canvas canvas, Rect rect) {
    // The ingredient token: a shiny golden blob with a face, so it reads as
    // "this is not a candy, get it to the bottom".
    final RRect rr = RRect.fromRectAndRadius(
      rect.deflate(rect.width * 0.04),
      Radius.circular(rect.width * 0.36),
    );
    canvas.drawRRect(
      rr.shift(Offset(0, rect.height * 0.06)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawRRect(
      rr,
      Paint()
        ..shader = ui.Gradient.linear(
          rect.topLeft,
          rect.bottomRight,
          <Color>[
            const Color(0xFFFFE9A8),
            GameColors.gold,
            GameColors.goldDark
          ],
        ),
    );
    // Blush.
    canvas.drawCircle(
      Offset(rect.left + rect.width * 0.3, rect.top + rect.height * 0.6),
      rect.width * 0.07,
      Paint()..color = GameColors.accent.withValues(alpha: 0.45),
    );
    canvas.drawCircle(
      Offset(rect.left + rect.width * 0.7, rect.top + rect.height * 0.6),
      rect.width * 0.07,
      Paint()..color = GameColors.accent.withValues(alpha: 0.45),
    );
    // Eyes.
    final Paint eye = Paint()..color = const Color(0xFF5A3200);
    canvas.drawCircle(
        Offset(rect.left + rect.width * 0.34, rect.top + rect.height * 0.42),
        rect.width * 0.055,
        eye);
    canvas.drawCircle(
        Offset(rect.left + rect.width * 0.66, rect.top + rect.height * 0.42),
        rect.width * 0.055,
        eye);
    // Smile.
    final Path smile = Path()
      ..moveTo(rect.left + rect.width * 0.36, rect.top + rect.height * 0.68)
      ..quadraticBezierTo(
        rect.center.dx,
        rect.top + rect.height * 0.86,
        rect.left + rect.width * 0.64,
        rect.top + rect.height * 0.68,
      );
    canvas.drawPath(
      smile,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = rect.width * 0.05
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF5A3200),
    );
  }

  void _paintParticles(Canvas canvas) {
    for (final _Particle p in particles) {
      final double a = (p.life / p.maxLife).clamp(0.0, 1.0);
      canvas.drawCircle(
        Offset(p.x * cell, p.y * cell),
        p.size * cell * (0.5 + a * 0.7),
        Paint()..color = p.color.withValues(alpha: a),
      );
    }
  }

  void _paintPopups(Canvas canvas) {
    for (final _FloatingText t in popups) {
      final double a = (t.life / 0.9).clamp(0.0, 1.0);
      final TextPainter tp = TextPainter(
        text: TextSpan(
          text: t.text,
          style: TextStyle(
            fontSize: cell * 0.42,
            fontWeight: FontWeight.w900,
            color: t.color.withValues(alpha: a),
            shadows: const <Shadow>[
              Shadow(
                  color: Color(0xCC000000),
                  blurRadius: 4,
                  offset: Offset(0, 2)),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(t.col * cell + cell * 0.5 - tp.width / 2,
            t.row * cell + cell * 0.2),
      );
    }
  }

  Rect _cellRect(int row, int col) =>
      Rect.fromLTWH(col * cell, row * cell, cell, cell);

  static double _easeOutCubic(double t) {
    final double u = 1 - t;
    return 1 - u * u * u;
  }

  static double _easeOutBack(double t) {
    const double c1 = 1.70158;
    const double c3 = c1 + 1;
    final double u = t - 1;
    return 1 + c3 * u * u * u + c1 * u * u;
  }

  @override
  bool shouldRepaint(covariant _BoardPainter old) => true;
}

/// The banner that flashes "Sweet!", "Tasty!" and combo names.
class _ComboBanner extends StatefulWidget {
  const _ComboBanner({required this.text});

  final String text;

  @override
  State<_ComboBanner> createState() => _ComboBannerState();
}

class _ComboBannerState extends State<_ComboBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..forward();
  }

  @override
  void didUpdateWidget(covariant _ComboBanner old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (BuildContext context, Widget? child) {
        final double t = Curves.easeOutBack.transform(_c.value.clamp(0.0, 1.0));
        final double fade =
            _c.value < 0.75 ? 1.0 : (1 - (_c.value - 0.75) / 0.25);
        return Opacity(
          opacity: fade.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: 0.6 + t * 0.5,
            child: child,
          ),
        );
      },
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: <Color>[GameColors.accent, GameColors.accentDark]),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.7), width: 2.5),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 12,
                  offset: Offset(0, 4)),
            ],
          ),
          child: Text(
            widget.text,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 1.2,
              shadows: <Shadow>[
                Shadow(
                    color: Color(0x99000000),
                    blurRadius: 4,
                    offset: Offset(0, 2))
              ],
            ),
          ),
        ),
      ),
    );
  }
}
