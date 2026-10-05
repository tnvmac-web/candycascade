import 'package:candy_cascade/logic/game_controller.dart';
import 'package:candy_cascade/logic/providers.dart';
import 'package:candy_cascade/services/iap_service.dart';
import 'package:candy_cascade/services/persistence_service.dart';
import 'package:candy_cascade/views/game_board_screen.dart';
import 'package:candy_cascade/views/level_map_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Renders the real level map and asserts what the player can see.
///
/// This is the check that a saved result actually shows up as gold stars under
/// the level node, which is the whole point of recording it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  /// Builds the app shell around the real map screen with a real persistence
  /// service, exactly as main.dart wires it.
  Future<Widget> harness(PersistenceService persistence) async {
    final IapService iap = IapService(persistence);
    return ProviderScope(
      overrides: <Override>[
        persistenceProvider.overrideWithValue(persistence),
        iapProvider.overrideWithValue(iap),
        gameControllerProvider.overrideWith(
          (Ref ref) => GameController(persistence: persistence, iap: iap),
        ),
      ],
      child: const MaterialApp(home: LevelMapScreen()),
    );
  }

  /// Counts star icons drawn inside the level grid only.
  ///
  /// The wallet strip at the top also draws a gold star, so counting globally
  /// would be off by one; scoping to the GridView keeps the assertion about the
  /// level nodes themselves.
  int countGridStars(WidgetTester tester, IconData icon, Color color) {
    int n = 0;
    for (final Element e in find
        .descendant(of: find.byType(GridView), matching: find.byType(Icon))
        .evaluate()) {
      final Icon w = e.widget as Icon;
      if (w.icon == icon && w.color == color) n++;
    }
    return n;
  }

  /// Counts lock icons drawn inside the level grid only.
  int countGridLocks(WidgetTester tester) {
    int n = 0;
    for (final Element e in find
        .descendant(of: find.byType(GridView), matching: find.byType(Icon))
        .evaluate()) {
      final Icon w = e.widget as Icon;
      if (w.icon == Icons.lock_rounded) n++;
    }
    return n;
  }

  /// Counts star icons in the same level node as [label], which is the node
  /// whose number or lock glyph is that text.
  int starsInNode(
      WidgetTester tester, String label, IconData icon, Color color) {
    final Finder node = find.ancestor(
      of: find.text(label),
      matching: find.byType(Column),
    );
    int n = 0;
    for (final Element e in find
        .descendant(of: node.first, matching: find.byType(Icon))
        .evaluate()) {
      final Icon w = e.widget as Icon;
      if (w.icon == icon && w.color == color) n++;
    }
    return n;
  }

  testWidgets('a fresh map shows no earned stars and only level 1 unlocked',
      (WidgetTester tester) async {
    final PersistenceService persistence = await PersistenceService.open();
    await tester.pumpWidget(await harness(persistence));
    await tester.pumpAndSettle();

    expect(countGridStars(tester, Icons.star_rounded, GameColors.gold), 0,
        reason: 'nothing is earned yet');
    expect(find.text('1'), findsOneWidget);
    expect(countGridLocks(tester), greaterThan(0),
        reason: 'every level past the first is locked');
    // Level 1 shows three empty slots.
    expect(
        starsInNode(tester, '1', Icons.star_border_rounded, Colors.white24), 3);
  });

  testWidgets(
      'a recorded win shows gold stars under the level and unlocks the next',
      (WidgetTester tester) async {
    final PersistenceService persistence = await PersistenceService.open();
    await persistence.recordLevelResult(levelId: 1, stars: 2, coinsEarned: 77);

    await tester.pumpWidget(await harness(persistence));
    await tester.pumpAndSettle();

    expect(countGridStars(tester, Icons.star_rounded, GameColors.gold), 2,
        reason: 'the two earned stars must be drawn in gold');

    // Level 2 must now be a number, not a padlock.
    expect(find.text('2'), findsWidgets, reason: 'level 2 should be unlocked');
    expect(find.text('1'), findsOneWidget);

    // In level 1's own node: two gold, one outline.
    expect(starsInNode(tester, '1', Icons.star_rounded, GameColors.gold), 2);
    expect(
        starsInNode(tester, '1', Icons.star_border_rounded, Colors.white24), 1,
        reason: 'the third slot stays an empty outline');
  });

  testWidgets('the wallet strip shows the star total, lives and coins',
      (WidgetTester tester) async {
    final PersistenceService persistence = await PersistenceService.open();
    await persistence.recordLevelResult(levelId: 1, stars: 3, coinsEarned: 123);

    await tester.pumpWidget(await harness(persistence));
    await tester.pumpAndSettle();

    expect(find.text('623'), findsOneWidget, reason: '500 + 123 coins');
    expect(find.textContaining('5/5'), findsOneWidget,
        reason: 'lives are full');
    // The wallet star chip shows the running total.
    expect(find.text('3'), findsWidgets);
    expect(countGridStars(tester, Icons.star_rounded, GameColors.gold), 3);
  });

  testWidgets('the map reflects a result that arrives after it is on screen',
      (WidgetTester tester) async {
    final PersistenceService persistence = await PersistenceService.open();
    await tester.pumpWidget(await harness(persistence));
    await tester.pumpAndSettle();
    expect(countGridStars(tester, Icons.star_rounded, GameColors.gold), 0);

    // Simulate returning from a level: record the result, then bump the
    // revision exactly as GameBoardScreen does.
    await persistence.recordLevelResult(levelId: 1, stars: 3, coinsEarned: 0);
    final ProviderContainer container =
        ProviderScope.containerOf(tester.element(find.byType(LevelMapScreen)));
    container.read(progressRevisionProvider.notifier).state++;
    await tester.pumpAndSettle();

    expect(countGridStars(tester, Icons.star_rounded, GameColors.gold), 3,
        reason: 'the map must repaint with the new stars');
    expect(find.text('2'), findsWidgets, reason: 'level 2 unlocks');
  });
}
