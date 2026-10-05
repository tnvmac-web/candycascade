import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../logic/game_controller.dart';
import '../logic/providers.dart';
import '../models/level_data.dart';
import '../services/ad_service.dart';
import '../services/iap_service.dart';
import '../services/persistence_service.dart';
import 'game_board_screen.dart';

/// What the player chose in a pause menu.
enum PauseAction { resume, restart, quit }

/// What the player chose in a win or lose dialog.
enum ResultAction { next, replay, map }

/// A reusable chunky candy button.
class CandyButton extends StatelessWidget {
  const CandyButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color = GameColors.accent,
    this.darkColor = GameColors.accentDark,
    this.icon,
    this.expand = false,
    this.small = false,
    this.enabled = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final Color darkColor;
  final IconData? icon;
  final bool expand;
  final bool small;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final bool active = enabled && onPressed != null;
    final Widget child = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (icon != null) ...<Widget>[
          Icon(icon, color: Colors.white, size: small ? 16 : 20),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            label,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: small ? 12 : 15,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    );

    return Opacity(
      opacity: active ? 1.0 : 0.45,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[color, darkColor],
          ),
          borderRadius: BorderRadius.circular(small ? 12 : 18),
          border:
              Border.all(color: Colors.white.withValues(alpha: 0.35), width: 2),
          boxShadow: const <BoxShadow>[
            BoxShadow(
                color: Color(0x55000000), blurRadius: 6, offset: Offset(0, 3)),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(small ? 12 : 18),
            onTap: active ? onPressed : null,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: small ? 10 : 20,
                vertical: small ? 8 : 13,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// A round icon button used in the top bar.
class RoundIconButton extends StatelessWidget {
  const RoundIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.badge,
    this.color = GameColors.panel,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? badge;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Container(
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.3), width: 2),
          ),
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onPressed,
              child: Padding(
                padding: const EdgeInsets.all(9),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
            ),
          ),
        ),
        if (badge != null)
          Positioned(
            right: -6,
            top: -6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: <Color>[GameColors.gold, GameColors.goldDark]),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: Text(
                badge!,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF4A2A00)),
              ),
            ),
          ),
      ],
    );
  }
}

/// The coin / life / star wallet strip.
class WalletStrip extends ConsumerWidget {
  const WalletStrip({super.key, this.showLives = true, this.showStars = true});

  final bool showLives;
  final bool showStars;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PlayerProgress p = ref.watch(playerProgressProvider);
    // Rebuild every second so the life countdown ticks.
    ref.watch(progressRevisionProvider);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (showStars)
          _WalletChip(
            icon: Icons.star_rounded,
            label: '${p.totalStars}',
            color: GameColors.gold,
            dark: GameColors.goldDark,
          ),
        if (showLives) ...<Widget>[
          const SizedBox(width: 6),
          _WalletChip(
            icon: Icons.favorite_rounded,
            label: p.livesFull
                ? '${p.lives}/${PlayerProgress.maxLives}'
                : '${p.lives}/${PlayerProgress.maxLives} · ${_formatMs(p.msToNextLife())}',
            color: GameColors.accent,
            dark: GameColors.accentDark,
          ),
        ],
        const SizedBox(width: 6),
        _WalletChip(
          icon: Icons.monetization_on_rounded,
          label: '${p.coins}',
          color: const Color(0xFF57C84D),
          dark: const Color(0xFF2E7A27),
        ),
      ],
    );
  }

  static String _formatMs(int ms) {
    final int totalSeconds = (ms / 1000).ceil();
    final int m = totalSeconds ~/ 60;
    final int s = totalSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

class _WalletChip extends StatelessWidget {
  const _WalletChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.dark,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        gradient:
            LinearGradient(colors: <Color>[dark, dark.withValues(alpha: 0.7)]),
        borderRadius: BorderRadius.circular(20),
        border:
            Border.all(color: Colors.white.withValues(alpha: 0.25), width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, color: color, size: 17),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// In level HUD
// -----------------------------------------------------------------------------

/// Top bar of the board screen: objectives, moves, pause.
class LevelGoalBar extends ConsumerWidget {
  const LevelGoalBar({super.key, required this.game, required this.onPause});

  final GameState game;
  final VoidCallback onPause;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: GameColors.panelDark.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(18),
        border:
            Border.all(color: Colors.white.withValues(alpha: 0.15), width: 1.5),
      ),
      child: Row(
        children: <Widget>[
          RoundIconButton(icon: Icons.pause_rounded, onPressed: onPause),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'Level ${game.level.id} · ${game.level.name}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: game.objectives.map((LevelObjective o) {
                    return _ObjectiveChip(objective: o);
                  }).toList(),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _MovesBadge(moves: game.movesLeft, score: game.score),
        ],
      ),
    );
  }
}

class _ObjectiveChip extends StatelessWidget {
  const _ObjectiveChip({required this.objective});

  final LevelObjective objective;

  IconData get _icon {
    switch (objective.type) {
      case ObjectiveType.score:
        return Icons.emoji_events_rounded;
      case ObjectiveType.ingredient:
        return Icons.icecream_rounded;
      case ObjectiveType.frosting:
        return Icons.ac_unit_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool done = objective.isComplete;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: done
            ? GameColors.mint.withValues(alpha: 0.25)
            : Colors.white.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: done ? GameColors.mint : Colors.white.withValues(alpha: 0.2),
          width: 1.2,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(_icon,
              size: 13, color: done ? GameColors.mint : GameColors.gold),
          const SizedBox(width: 4),
          Text(
            '${objective.progress}/${objective.target}',
            style: TextStyle(
              color: done ? GameColors.mint : Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _MovesBadge extends StatelessWidget {
  const _MovesBadge({required this.moves, required this.score});

  final int moves;
  final int score;

  @override
  Widget build(BuildContext context) {
    final bool low = moves <= 3;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          '$score',
          style: const TextStyle(
              color: GameColors.gold,
              fontWeight: FontWeight.w900,
              fontSize: 17),
        ),
        Container(
          margin: const EdgeInsets.only(top: 3),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: low
                  ? <Color>[GameColors.accent, GameColors.accentDark]
                  : <Color>[GameColors.mint, const Color(0xFF2A9E7A)],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '$moves moves',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

/// The strip of booster buttons under the board.
class BoosterBar extends ConsumerWidget {
  const BoosterBar({super.key, required this.game});

  final GameState game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PlayerProgress p = ref.watch(playerProgressProvider);
    final GameController controller = ref.read(gameControllerProvider.notifier);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: GameColors.panelDark.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(18),
        border:
            Border.all(color: Colors.white.withValues(alpha: 0.12), width: 1.5),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: <Widget>[
          _BoosterTile(
            label: 'Hammer',
            icon: Icons.gavel_rounded,
            count: p.hammerCount,
            selected: game.booster == BoosterMode.hammer,
            onTap: () => controller.armBooster(BoosterMode.hammer),
            onBuy: () async {
              final bool ok =
                  await controller.buyBoosterWithCoins(BoosterMode.hammer, 120);
              if (!ok && context.mounted) {
                showShopSheet(context, ref,
                    reason: 'You need more coins for a Lollipop Hammer.');
              }
            },
          ),
          _BoosterTile(
            label: 'Switch',
            icon: Icons.swap_horiz_rounded,
            count: p.freeSwitchCount,
            selected: game.booster == BoosterMode.freeSwitch,
            onTap: () => controller.armBooster(BoosterMode.freeSwitch),
            onBuy: () async {
              final bool ok = await controller.buyBoosterWithCoins(
                  BoosterMode.freeSwitch, 90);
              if (!ok && context.mounted) {
                showShopSheet(context, ref,
                    reason: 'You need more coins for a Free Switch.');
              }
            },
          ),
          _BoosterTile(
            label: 'Moves',
            icon: Icons.add_circle_rounded,
            count: 0,
            selected: false,
            showCount: false,
            cost: 150,
            onTap: () async {
              final bool ok = await controller.buyExtraMovesWithCoins(150, 5);
              if (!ok && context.mounted) {
                showShopSheet(context, ref,
                    reason: 'You need more coins for +5 moves.');
              }
            },
          ),
          _BoosterTile(
            label: 'Free ad',
            icon: Icons.ondemand_video_rounded,
            count: 0,
            selected: false,
            showCount: false,
            onTap: () async {
              final AdService ads = ref.read(adProvider);
              final RewardOutcome outcome = await ads.showRewarded();
              if (!context.mounted) return;
              if (outcome == RewardOutcome.earned) {
                controller.grantRewardedMoves(3);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('+3 moves!')),
                );
              } else if (outcome == RewardOutcome.notReady) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('No ad ready yet, try again in a moment.')),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}

class _BoosterTile extends StatelessWidget {
  const _BoosterTile({
    required this.label,
    required this.icon,
    required this.count,
    required this.selected,
    required this.onTap,
    this.onBuy,
    this.cost,
    this.showCount = true,
  });

  final String label;
  final IconData icon;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onBuy;
  final int? cost;
  final bool showCount;

  @override
  Widget build(BuildContext context) {
    final bool empty = showCount && count <= 0;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: empty && onBuy != null ? onBuy : onTap,
      child: Container(
        width: 62,
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: selected
                ? <Color>[GameColors.gold, GameColors.goldDark]
                : <Color>[GameColors.panel, GameColors.panelDark],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color:
                selected ? Colors.white : Colors.white.withValues(alpha: 0.2),
            width: selected ? 2.2 : 1.4,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, color: Colors.white, size: 21),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700),
            ),
            if (showCount)
              Text(
                empty ? '+${cost ?? 0}' : 'x$count',
                style: TextStyle(
                  color: empty
                      ? GameColors.gold
                      : Colors.white.withValues(alpha: 0.85),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Dialogs
// -----------------------------------------------------------------------------

/// The pause menu.
Future<PauseAction?> showPauseMenu(BuildContext context, GameState game) {
  return showDialog<PauseAction>(
    context: context,
    barrierDismissible: true,
    builder: (BuildContext context) {
      return _CandyDialog(
        title: 'Paused',
        children: <Widget>[
          Text(
            'Level ${game.level.id} · ${game.level.name}\nScore ${game.score} · ${game.movesLeft} moves left',
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white70, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 18),
          CandyButton(
            label: 'Resume',
            icon: Icons.play_arrow_rounded,
            expand: true,
            onPressed: () => Navigator.of(context).pop(PauseAction.resume),
          ),
          const SizedBox(height: 10),
          CandyButton(
            label: 'Restart Level',
            icon: Icons.refresh_rounded,
            expand: true,
            color: GameColors.panel,
            darkColor: GameColors.panelDark,
            onPressed: () => Navigator.of(context).pop(PauseAction.restart),
          ),
          const SizedBox(height: 10),
          CandyButton(
            label: 'Quit to Map',
            icon: Icons.exit_to_app_rounded,
            expand: true,
            color: const Color(0xFF7A4A9E),
            darkColor: const Color(0xFF4A2A6E),
            onPressed: () => Navigator.of(context).pop(PauseAction.quit),
          ),
        ],
      );
    },
  );
}

/// Confirmation before leaving a level in progress.
Future<bool> showQuitDialog(BuildContext context) async {
  final bool? result = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => _CandyDialog(
      title: 'Leave level?',
      children: <Widget>[
        const Text(
          'Your progress in this level will be lost.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        const SizedBox(height: 18),
        CandyButton(
          label: 'Keep playing',
          expand: true,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        const SizedBox(height: 10),
        CandyButton(
          label: 'Leave',
          expand: true,
          color: GameColors.panel,
          darkColor: GameColors.panelDark,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// The win dialog with the star reveal.
Future<ResultAction?> showWinDialog(BuildContext context, GameState game) {
  return showDialog<ResultAction>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) {
      final int stars = game.stars;
      return _CandyDialog(
        title: stars == 3 ? 'Sugar Crush!' : 'Level Clear!',
        children: <Widget>[
          _StarRow(stars: stars),
          const SizedBox(height: 14),
          Text(
            'Score ${game.score}',
            style: const TextStyle(
              color: GameColors.gold,
              fontWeight: FontWeight.w900,
              fontSize: 22,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            game.objectives
                .map((LevelObjective o) =>
                    '${o.label} ${o.progress}/${o.target}')
                .join('   ·   '),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 20),
          CandyButton(
            label: 'Next Level',
            icon: Icons.arrow_forward_rounded,
            expand: true,
            color: const Color(0xFF57C84D),
            darkColor: const Color(0xFF2E7A27),
            onPressed: () => Navigator.of(context).pop(ResultAction.next),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: CandyButton(
                  label: 'Replay',
                  small: true,
                  color: GameColors.panel,
                  darkColor: GameColors.panelDark,
                  onPressed: () =>
                      Navigator.of(context).pop(ResultAction.replay),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: CandyButton(
                  label: 'Map',
                  small: true,
                  color: GameColors.panel,
                  darkColor: GameColors.panelDark,
                  onPressed: () => Navigator.of(context).pop(ResultAction.map),
                ),
              ),
            ],
          ),
        ],
      );
    },
  );
}

/// The lose dialog with the two ways out: ad or coins.
Future<ResultAction?> showLoseDialog(
  BuildContext context,
  GameState game, {
  required Future<bool> Function() onWatchAd,
  required Future<bool> Function() onBuyMoves,
}) {
  return showDialog<ResultAction>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) => _LoseDialog(
      game: game,
      onWatchAd: onWatchAd,
      onBuyMoves: onBuyMoves,
    ),
  );
}

/// The lose dialog body.
///
/// A real StatefulWidget rather than a StatefulBuilder, because the ad button's
/// label depends on the busy flag: with a builder the ternary is evaluated once,
/// before the closure ever runs, so the label would never change.
class _LoseDialog extends StatefulWidget {
  const _LoseDialog({
    required this.game,
    required this.onWatchAd,
    required this.onBuyMoves,
  });

  final GameState game;
  final Future<bool> Function() onWatchAd;
  final Future<bool> Function() onBuyMoves;

  @override
  State<_LoseDialog> createState() => _LoseDialogState();
}

class _LoseDialogState extends State<_LoseDialog> {
  bool _busy = false;

  Future<void> _runAd() async {
    if (_busy) return;
    setState(() => _busy = true);
    final bool ok = await widget.onWatchAd();
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(ResultAction.replay);
    } else {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No reward this time.')),
      );
    }
  }

  Future<void> _runBuy() async {
    if (_busy) return;
    setState(() => _busy = true);
    final bool ok = await widget.onBuyMoves();
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(ResultAction.replay);
    } else {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not enough coins.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final GameState game = widget.game;
    return _CandyDialog(
      title: 'Out of Moves',
      children: <Widget>[
        const Icon(Icons.sentiment_dissatisfied_rounded,
            color: GameColors.accent, size: 46),
        const SizedBox(height: 10),
        Text(
          'You scored ${game.score}.',
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        const SizedBox(height: 6),
        Text(
          game.objectives
              .where((LevelObjective o) => !o.isComplete)
              .map((LevelObjective o) => '${o.label} ${o.progress}/${o.target}')
              .join('   ·   '),
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: GameColors.gold,
              fontSize: 12.5,
              fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 18),
        CandyButton(
          label: _busy ? 'Please wait...' : 'Watch ad for +5 moves',
          icon: Icons.ondemand_video_rounded,
          expand: true,
          color: const Color(0xFF57C84D),
          darkColor: const Color(0xFF2E7A27),
          enabled: !_busy,
          onPressed: _runAd,
        ),
        const SizedBox(height: 10),
        CandyButton(
          label: 'Continue for 150 coins',
          icon: Icons.monetization_on_rounded,
          expand: true,
          color: GameColors.gold,
          darkColor: GameColors.goldDark,
          enabled: !_busy,
          onPressed: _runBuy,
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Expanded(
              child: CandyButton(
                label: 'Replay',
                small: true,
                color: GameColors.panel,
                darkColor: GameColors.panelDark,
                enabled: !_busy,
                onPressed: () => Navigator.of(context).pop(ResultAction.replay),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: CandyButton(
                label: 'Map',
                small: true,
                color: GameColors.panel,
                darkColor: GameColors.panelDark,
                enabled: !_busy,
                onPressed: () => Navigator.of(context).pop(ResultAction.map),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Animated three star reveal.
class _StarRow extends StatelessWidget {
  const _StarRow({required this.stars});

  final int stars;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List<Widget>.generate(3, (int i) {
        final bool earned = i < stars;
        return TweenAnimationBuilder<double>(
          key: ValueKey<String>('star_$i'),
          tween: Tween<double>(begin: 0, end: earned ? 1 : 0.72),
          duration: Duration(milliseconds: 320 + i * 180),
          curve: Curves.elasticOut,
          builder: (BuildContext context, double v, Widget? child) {
            return Transform.scale(scale: v, child: child);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Icon(
              earned ? Icons.star_rounded : Icons.star_border_rounded,
              size: 56,
              color: earned ? GameColors.gold : Colors.white24,
              shadows: earned
                  ? const <Shadow>[
                      Shadow(color: Color(0xAAFFC53D), blurRadius: 14)
                    ]
                  : null,
            ),
          ),
        );
      }),
    );
  }
}

/// The shared candy-styled dialog shell.
class _CandyDialog extends StatelessWidget {
  const _CandyDialog({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 30),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 380),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[GameColors.panel, GameColors.panelDark],
          ),
          borderRadius: BorderRadius.circular(26),
          border:
              Border.all(color: Colors.white.withValues(alpha: 0.35), width: 3),
          boxShadow: const <BoxShadow>[
            BoxShadow(
                color: Color(0x88000000),
                blurRadius: 22,
                offset: Offset(0, 10)),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                  shadows: <Shadow>[
                    Shadow(
                        color: Color(0x99000000),
                        blurRadius: 6,
                        offset: Offset(0, 2))
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Shop
// -----------------------------------------------------------------------------

/// Opens the coin shop as a bottom sheet.
Future<void> showShopSheet(BuildContext context, WidgetRef ref,
    {String? reason}) {
  final IapService iap = ref.read(iapProvider);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext context) {
      return _ShopSheet(iap: iap, reason: reason);
    },
  );
}

class _ShopSheet extends StatefulWidget {
  const _ShopSheet({required this.iap, this.reason});

  final IapService iap;
  final String? reason;

  @override
  State<_ShopSheet> createState() => _ShopSheetState();
}

class _ShopSheetState extends State<_ShopSheet> {
  late final StreamSubscription<PurchaseEvent> _sub;
  String? _busyProduct;
  String? _toast;

  @override
  void initState() {
    super.initState();
    _sub = widget.iap.events.listen((PurchaseEvent e) {
      if (!mounted) return;
      setState(() {
        _busyProduct = null;
        switch (e.kind) {
          case PurchaseEventKind.delivered:
            _toast =
                e.coins > 0 ? 'Added ${e.coins} coins!' : 'Purchase complete!';
            break;
          case PurchaseEventKind.restored:
            _toast = 'Purchases restored.';
            break;
          case PurchaseEventKind.cancelled:
            _toast = 'Purchase cancelled.';
            break;
          case PurchaseEventKind.failed:
            _toast = e.message ?? 'The purchase failed.';
            break;
          case PurchaseEventKind.pending:
            _toast = 'Waiting for the store...';
            break;
        }
      });
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<ShopProduct> products = widget.iap.catalogue;
    final PlayerProgress progress =
        ProviderScope.containerOf(context).read(persistenceProvider).progress;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[GameColors.panel, GameColors.bgBottom],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: Container(
                  width: 46,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Sweet Shop',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900),
              ),
              if (widget.reason != null) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  widget.reason!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: GameColors.gold,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700),
                ),
              ],
              const SizedBox(height: 12),
              if (_toast != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: GameColors.mint.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: GameColors.mint, width: 1.5),
                  ),
                  child: Text(
                    _toast!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 12.5),
                  ),
                ),
              if (!widget.iap.storeAvailable)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: GameColors.accent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: GameColors.accent, width: 1.5),
                  ),
                  child: const Text(
                    'The store is not reachable on this device. Prices shown are indicative.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ...products.map((ShopProduct p) => _ShopRow(
                    product: p,
                    busy: _busyProduct == p.id,
                    onBuy: () {
                      setState(() {
                        _busyProduct = p.id;
                        _toast = null;
                      });
                      widget.iap.buy(p.id);
                    },
                  )),
              const SizedBox(height: 10),
              CandyButton(
                label: 'Restore Purchases',
                icon: Icons.restore_rounded,
                expand: true,
                color: GameColors.panel,
                darkColor: GameColors.panelDark,
                onPressed: () {
                  setState(() => _toast = 'Restoring...');
                  widget.iap.restore();
                },
              ),
              const SizedBox(height: 8),
              Text(
                'Coins in your wallet: ${progress.coins}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 11.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShopRow extends StatelessWidget {
  const _ShopRow(
      {required this.product, required this.busy, required this.onBuy});

  final ShopProduct product;
  final bool busy;
  final VoidCallback onBuy;

  IconData get _icon {
    switch (product.id) {
      case StoreIds.coinsTier1:
        return Icons.savings_rounded;
      case StoreIds.coinsTier2:
        return Icons.account_balance_wallet_rounded;
      case StoreIds.coinsTier3:
        return Icons.diamond_rounded;
      case StoreIds.refillLives:
        return Icons.favorite_rounded;
      case StoreIds.removeAds:
        return Icons.block_rounded;
      default:
        return Icons.shopping_bag_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: Colors.white.withValues(alpha: 0.14), width: 1.4),
      ),
      child: Row(
        children: <Widget>[
          Icon(_icon, color: GameColors.gold, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  product.title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  product.description,
                  style: const TextStyle(color: Colors.white60, fontSize: 11.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 104,
            child: CandyButton(
              label: busy ? '...' : product.price,
              small: true,
              expand: true,
              enabled: !busy,
              color: product.available
                  ? const Color(0xFF57C84D)
                  : GameColors.panel,
              darkColor: product.available
                  ? const Color(0xFF2E7A27)
                  : GameColors.panelDark,
              onPressed: onBuy,
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Shared helper widgets
// -----------------------------------------------------------------------------

/// A small banner ad slot that disposes its ad with the widget.
class BannerAdSlot extends ConsumerStatefulWidget {
  const BannerAdSlot({super.key, this.size = AdSize.banner});

  final AdSize size;

  @override
  ConsumerState<BannerAdSlot> createState() => _BannerAdSlotState();
}

class _BannerAdSlotState extends ConsumerState<BannerAdSlot> {
  BannerAd? _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _load() {
    final AdService ads = ref.read(adProvider);
    final BannerAd? ad = ads.createBanner(size: widget.size);
    if (ad == null) return;
    ad.load().then((_) {}).catchError((Object _) {});
    setState(() => _ad = ad);
    // The listener inside createBanner reports success; poll once for sizing.
    Future<void>.delayed(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _loaded = true);
    });
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final BannerAd? ad = _ad;
    if (ad == null) return const SizedBox.shrink();
    return SizedBox(
      width: ad.size.width.toDouble(),
      height: ad.size.height.toDouble(),
      child: _loaded ? AdWidget(ad: ad) : const SizedBox.shrink(),
    );
  }
}
