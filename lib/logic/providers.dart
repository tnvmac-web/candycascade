import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/ad_service.dart';
import '../services/audio_service.dart';
import '../services/iap_service.dart';
import '../services/persistence_service.dart';
import 'game_controller.dart';

/// The persistence service, overridden in `main.dart` once the preferences
/// have finished loading.
final Provider<PersistenceService> persistenceProvider =
    Provider<PersistenceService>(
  (Ref ref) =>
      throw StateError('persistenceProvider must be overridden in main()'),
);

/// In app purchase service, created after persistence is ready.
final Provider<IapService> iapProvider = Provider<IapService>(
  (Ref ref) => throw StateError('iapProvider must be overridden in main()'),
);

/// The current level attempt. Null when the player is not in a level.
final StateNotifierProvider<GameController, GameState?> gameControllerProvider =
    StateNotifierProvider<GameController, GameState?>(
  (Ref ref) =>
      throw StateError('gameControllerProvider must be overridden in main()'),
);

/// Bumped whenever the persisted progress changes, so widgets that read
/// coins, lives, or stars rebuild.
final StateProvider<int> progressRevisionProvider =
    StateProvider<int>((Ref ref) => 0);

/// Convenience read of the player's persisted progress.
final Provider<PlayerProgress> playerProgressProvider =
    Provider<PlayerProgress>(
  (Ref ref) {
    ref.watch(progressRevisionProvider);
    return ref.watch(persistenceProvider).progress;
  },
);

/// The audio hub.
final Provider<AudioService> audioProvider = Provider<AudioService>(
  (Ref ref) => AudioService.instance,
);

/// The ad hub.
final Provider<AdService> adProvider = Provider<AdService>(
  (Ref ref) => AdService.instance,
);

/// Pushes a change of the persisted progress to every listener.
void bumpProgress(WidgetRef ref) {
  ref.read(progressRevisionProvider.notifier).state++;
}
