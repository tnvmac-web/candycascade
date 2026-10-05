import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logic/game_controller.dart';
import '../logic/providers.dart';
import '../services/ad_service.dart';
import '../services/audio_service.dart';
import '../services/persistence_service.dart';
import 'game_board_screen.dart';
import 'ui_overlays.dart';

/// The home screen: wallet, level map, settings, shop.
class LevelMapScreen extends ConsumerStatefulWidget {
  const LevelMapScreen({super.key});

  @override
  ConsumerState<LevelMapScreen> createState() => _LevelMapScreenState();
}

class _LevelMapScreenState extends ConsumerState<LevelMapScreen> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // A one second tick keeps the life countdown and the "next life in" label
    // honest without any widget needing its own timer.
    _ticker = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      final GameController controller =
          ref.read(gameControllerProvider.notifier);
      controller.refreshLives();
      if (mounted) {
        ref.read(progressRevisionProvider.notifier).state++;
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final PlayerProgress progress = ref.watch(playerProgressProvider);
    final PersistenceService persistence = ref.watch(persistenceProvider);
    final int highest = progress.highestLevelUnlocked;
    // Show a few levels past the frontier so the map feels endless.
    final int visible = math.max(20, highest + 6);

    return Scaffold(
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
              _TopBar(progress: progress),
              const _TitleBanner(),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.82,
                  ),
                  itemCount: visible,
                  itemBuilder: (BuildContext context, int index) {
                    final int levelId = index + 1;
                    final bool unlocked = levelId <= highest;
                    final int stars = persistence.starsFor(levelId);
                    return _LevelNode(
                      levelId: levelId,
                      unlocked: unlocked,
                      stars: stars,
                      onTap: () => _openLevel(levelId, progress),
                    );
                  },
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: BannerAdSlot(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openLevel(int levelId, PlayerProgress progress) async {
    if (levelId > progress.highestLevelUnlocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Finish the earlier levels first!')),
      );
      return;
    }
    if (!progress.livesFull && progress.lives <= 0) {
      final bool refilled = await _promptNoLives();
      if (!refilled || !mounted) return;
    }
    AudioService.instance.hapticLight();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
          builder: (BuildContext context) => GameBoardScreen(levelId: levelId)),
    );
    if (mounted) {
      ref.read(progressRevisionProvider.notifier).state++;
    }
  }

  /// Offers the two legitimate ways to get a life back: wait, or watch an ad.
  Future<bool> _promptNoLives() async {
    final AdService ads = ref.read(adProvider);
    final GameController controller = ref.read(gameControllerProvider.notifier);
    final PlayerProgress progress = ref.read(persistenceProvider).progress;

    final String? choice = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: GameColors.panel,
        title: const Text('Out of lives',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        content: Text(
          'Next life in ${_formatMs(progress.msToNextLife())}.\nWatch a short ad for a free life now?',
          style: const TextStyle(color: Colors.white70, height: 1.5),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop('cancel'),
            child: const Text('Wait', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop('ad'),
            child: const Text('Watch ad',
                style: TextStyle(
                    color: GameColors.gold, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );

    if (choice != 'ad') return false;
    final RewardOutcome outcome = await ads.showRewarded();
    if (outcome == RewardOutcome.earned) {
      progress.addLife();
      await ref.read(persistenceProvider).save();
      if (mounted) ref.read(progressRevisionProvider.notifier).state++;
      controller.refreshLives();
      return true;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(outcome == RewardOutcome.notReady
              ? 'No ad ready yet, try again in a moment.'
              : 'No reward this time.'),
        ),
      );
    }
    return false;
  }

  static String _formatMs(int ms) {
    final int totalSeconds = (ms / 1000).ceil();
    final int m = totalSeconds ~/ 60;
    final int s = totalSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

class _TopBar extends ConsumerWidget {
  const _TopBar({required this.progress});

  final PlayerProgress progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Row(
        children: <Widget>[
          const Expanded(child: WalletStrip()),
          const SizedBox(width: 8),
          RoundIconButton(
            icon: Icons.storefront_rounded,
            badge: null,
            color: const Color(0xFF57C84D),
            onPressed: () => showShopSheet(context, ref),
          ),
          const SizedBox(width: 8),
          RoundIconButton(
            icon: Icons.settings_rounded,
            onPressed: () => showSettingsSheet(context, ref),
          ),
        ],
      ),
    );
  }
}

class _TitleBanner extends StatelessWidget {
  const _TitleBanner();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: <Color>[GameColors.accent, GameColors.accentDark]),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: Colors.white.withValues(alpha: 0.4), width: 2.5),
          boxShadow: const <BoxShadow>[
            BoxShadow(
                color: Color(0x55000000), blurRadius: 10, offset: Offset(0, 5)),
          ],
        ),
        child: const Text(
          'CANDY CASCADE',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w900,
            letterSpacing: 3,
            shadows: <Shadow>[
              Shadow(
                  color: Color(0x99000000), blurRadius: 5, offset: Offset(0, 2))
            ],
          ),
        ),
      ),
    );
  }
}

/// One level bubble on the map.
class _LevelNode extends StatelessWidget {
  const _LevelNode({
    required this.levelId,
    required this.unlocked,
    required this.stars,
    required this.onTap,
  });

  final int levelId;
  final bool unlocked;
  final int stars;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool isBoss = levelId % 10 == 0;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Column(
        children: <Widget>[
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: unlocked
                      ? (isBoss
                          ? <Color>[GameColors.gold, GameColors.goldDark]
                          : <Color>[GameColors.panel, GameColors.panelDark])
                      : <Color>[
                          const Color(0xFF2A1B45),
                          const Color(0xFF20142F)
                        ],
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: unlocked
                      ? Colors.white.withValues(alpha: 0.35)
                      : Colors.white.withValues(alpha: 0.1),
                  width: 2,
                ),
              ),
              child: Center(
                child: unlocked
                    ? Text(
                        '$levelId',
                        style: TextStyle(
                          color:
                              isBoss ? const Color(0xFF4A2A00) : Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      )
                    : const Icon(Icons.lock_rounded,
                        color: Colors.white38, size: 24),
              ),
            ),
          ),
          const SizedBox(height: 3),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List<Widget>.generate(3, (int i) {
              return Icon(
                i < stars ? Icons.star_rounded : Icons.star_border_rounded,
                size: 13,
                color: i < stars ? GameColors.gold : Colors.white24,
              );
            }),
          ),
        ],
      ),
    );
  }
}

/// Settings: sound, music, haptics, restore, reset.
Future<void> showSettingsSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (BuildContext context) {
      return Consumer(
        builder: (BuildContext context, WidgetRef ref, Widget? child) {
          final PersistenceService persistence = ref.watch(persistenceProvider);
          final PlayerProgress p = ref.watch(playerProgressProvider);
          final AudioService audio = AudioService.instance;

          Future<void> update(Future<void> Function() change) async {
            await change();
            await persistence.save();
            audio.configure(p);
            ref.read(progressRevisionProvider.notifier).state++;
          }

          return Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
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
                          borderRadius: BorderRadius.circular(3)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Settings',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    value: p.soundOn,
                    activeThumbColor: GameColors.mint,
                    title: const Text('Sound effects',
                        style: TextStyle(color: Colors.white)),
                    onChanged: (bool v) => update(() async => p.soundOn = v),
                  ),
                  SwitchListTile(
                    value: p.musicOn,
                    activeThumbColor: GameColors.mint,
                    title: const Text('Music',
                        style: TextStyle(color: Colors.white)),
                    onChanged: (bool v) => update(() async => p.musicOn = v),
                  ),
                  SwitchListTile(
                    value: p.hapticsOn,
                    activeThumbColor: GameColors.mint,
                    title: const Text('Vibration',
                        style: TextStyle(color: Colors.white)),
                    onChanged: (bool v) => update(() async => p.hapticsOn = v),
                  ),
                  const Divider(color: Colors.white24),
                  CandyButton(
                    label: 'Restore Purchases',
                    icon: Icons.restore_rounded,
                    expand: true,
                    color: GameColors.panel,
                    darkColor: GameColors.panelDark,
                    onPressed: () => ref.read(iapProvider).restore(),
                  ),
                  const SizedBox(height: 10),
                  CandyButton(
                    label: 'Reset Progress',
                    icon: Icons.delete_forever_rounded,
                    expand: true,
                    color: GameColors.accentDark,
                    darkColor: const Color(0xFF7A1236),
                    onPressed: () async {
                      final bool? ok = await showDialog<bool>(
                        context: context,
                        builder: (BuildContext context) => AlertDialog(
                          backgroundColor: GameColors.panel,
                          title: const Text('Reset everything?',
                              style: TextStyle(color: Colors.white)),
                          content: const Text(
                            'This clears stars, coins and boosters. Purchases are not affected.',
                            style: TextStyle(color: Colors.white70),
                          ),
                          actions: <Widget>[
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(false),
                              child: const Text('Cancel',
                                  style: TextStyle(color: Colors.white70)),
                            ),
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(true),
                              child: const Text('Reset',
                                  style: TextStyle(color: GameColors.accent)),
                            ),
                          ],
                        ),
                      );
                      if (ok != true) return;
                      await persistence.resetAll();
                      ref.read(progressRevisionProvider.notifier).state++;
                      if (context.mounted) Navigator.of(context).pop();
                    },
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Candy Cascade 1.0.0',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white38, fontSize: 11.5),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
