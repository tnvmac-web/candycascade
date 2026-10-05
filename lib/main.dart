import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'logic/game_controller.dart';
import 'logic/providers.dart';
import 'services/ad_service.dart';
import 'services/audio_service.dart';
import 'services/iap_service.dart';
import 'services/persistence_service.dart';
import 'views/game_board_screen.dart';
import 'views/level_map_screen.dart';

/// Flip to true to build the child directed variant of the app.
///
/// This is the single switch that drives COPPA behaviour: it tags every ad
/// request as child directed, asks the SDK for under age of consent handling,
/// and caps the content rating at G. A children's build should also be
/// published under the Families policy in Play Console and declare the
/// "Designed for Families" flag, which is a store listing setting rather than
/// something the binary can do.
const bool kChildDirectedMode = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Landscape is a poor fit for a 9x9 board on a phone, so lock to portrait.
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Edge to edge, with the system bars drawn as translucent overlays so the
  // gradient reaches the screen edges on Android 15.
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.edgeToEdge,
    overlays: SystemUiOverlay.values,
  );
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: GameColors.bgBottom,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // Persistence first: everything else reads the player's saved state.
  final PersistenceService persistence = await PersistenceService.open();

  // Audio, configured from the saved toggles.
  AudioService.instance.configure(persistence.progress);

  // Billing.
  final IapService iap = IapService(persistence);

  runApp(
    ProviderScope(
      overrides: <Override>[
        persistenceProvider.overrideWithValue(persistence),
        iapProvider.overrideWithValue(iap),
        gameControllerProvider.overrideWith(
          (Ref ref) => GameController(persistence: persistence, iap: iap),
        ),
      ],
      child: const CandyCascadeApp(),
    ),
  );

  // AdMob must be initialised after the first frame on Android, so the consent
  // form and the app id meta data are already in place.
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await AdService.instance.initialise(
      adsRemoved: persistence.progress.adsRemoved,
      childDirected: kChildDirectedMode,
    );
    // Billing is initialised after ads so a slow store never blocks the first
    // playable frame.
    await iap.initialise();
  });
}

/// Root widget. Owns the lifecycle hooks that keep music and lives correct.
class CandyCascadeApp extends ConsumerStatefulWidget {
  const CandyCascadeApp({super.key});

  @override
  ConsumerState<CandyCascadeApp> createState() => _CandyCascadeAppState();
}

class _CandyCascadeAppState extends ConsumerState<CandyCascadeApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Keeps offline life regeneration moving while the map is open.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(gameControllerProvider.notifier).startLifeTimer(() {
        if (mounted) ref.read(progressRevisionProvider.notifier).state++;
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final GameController controller = ref.read(gameControllerProvider.notifier);
    switch (state) {
      case AppLifecycleState.resumed:
        controller.onResume();
        AudioService.instance.resumeMusic();
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        AudioService.instance.pauseMusic();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Candy Cascade',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      home: const LevelMapScreen(),
      builder: (BuildContext context, Widget? child) {
        // Clamp text scaling so a huge accessibility setting cannot break the
        // board layout, while still honouring the player's preference.
        final MediaQueryData data = MediaQuery.of(context);
        return MediaQuery(
          data: data.copyWith(
            textScaler: data.textScaler
                .clamp(minScaleFactor: 0.85, maxScaleFactor: 1.25),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }

  ThemeData _buildTheme() {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: GameColors.accent,
      brightness: Brightness.dark,
      primary: GameColors.accent,
      secondary: GameColors.gold,
      surface: GameColors.panel,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: GameColors.bgBottom,
      splashFactory: InkSparkle.splashFactory,
      fontFamily: defaultTargetPlatform == TargetPlatform.iOS ? null : null,
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: GameColors.panel,
        contentTextStyle: TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
