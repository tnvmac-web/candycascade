import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Google's published test IDs. These are safe to ship and always serve a test
/// creative, so an app can be built and reviewed before real ads are wired up.
/// Replace both with your own IDs before you publish.
class AdIds {
  AdIds._();

  static const String testAndroidAppId =
      'ca-app-pub-3940256099942544~3347511713';
  static const String testIosAppId = 'ca-app-pub-3940256099942544~1458002511';

  static const String testBannerAndroid =
      'ca-app-pub-3940256099942544/6300978111';
  static const String testBannerIos = 'ca-app-pub-3940256099942544/2934735716';

  static const String testInterstitialAndroid =
      'ca-app-pub-3940256099942544/1033173712';
  static const String testInterstitialIos =
      'ca-app-pub-3940256099942544/4411468910';

  static const String testRewardedAndroid =
      'ca-app-pub-3940256099942544/5224354917';
  static const String testRewardedIos =
      'ca-app-pub-3940256099942544/1712485313';
}

/// Reasons a rewarded ad can end, so the caller only grants the reward on
/// [RewardOutcome.earned].
enum RewardOutcome { earned, dismissed, failed, notReady }

/// AdMob wrapper.
///
/// Covers the three formats the game needs: a banner on the map and shop, an
/// interstitial between levels, and rewarded video for extra moves and lives.
/// Everything degrades to a no-op when ads are removed, unavailable, or running
/// on a platform without a configured ad unit.
class AdService {
  AdService._();

  static final AdService instance = AdService._();

  bool _sdkReady = false;
  bool _adsRemoved = false;

  /// Whether this build is aimed at children. Kept so a later ad request can
  /// re-read it, and so the value is visible in a debugger.
  bool _childDirected = false;

  InterstitialAd? _interstitial;
  RewardedAd? _rewarded;
  BannerAd? _banner;

  bool _loadingInterstitial = false;
  bool _loadingRewarded = false;

  /// Counts levels finished since the last interstitial, so ads land every
  /// second or third level rather than every level.
  int _levelsSinceAd = 0;
  static const int _levelsPerAd = 2;

  final StreamController<String> _log = StreamController<String>.broadcast();

  Stream<String> get log => _log.stream;

  bool get sdkReady => _sdkReady;
  bool get adsRemoved => _adsRemoved;
  bool get childDirected => _childDirected;

  /// True when a rewarded ad is loaded and can be shown immediately.
  bool get rewardedReady => _rewarded != null;

  /// Initialises the Mobile Ads SDK and requests consent.
  ///
  /// [childDirected] turns on COPPA handling: the SDK is told the app is aimed
  /// at children and only non personalised ads are requested.
  Future<void> initialise({
    required bool adsRemoved,
    required bool childDirected,
  }) async {
    _adsRemoved = adsRemoved;
    _childDirected = childDirected;

    if (_adsRemoved) {
      _log.add('Ads are removed for this player, skipping SDK init.');
      return;
    }

    try {
      final RequestConfiguration requestConfiguration = RequestConfiguration(
        tagForChildDirectedTreatment: childDirected
            ? TagForChildDirectedTreatment.yes
            : TagForChildDirectedTreatment.unspecified,
        tagForUnderAgeOfConsent: childDirected
            ? TagForUnderAgeOfConsent.yes
            : TagForUnderAgeOfConsent.unspecified,
        maxAdContentRating:
            childDirected ? MaxAdContentRating.g : MaxAdContentRating.t,
        testDeviceIds: kDebugMode ? const <String>[] : const <String>[],
      );
      await MobileAds.instance.updateRequestConfiguration(requestConfiguration);
      await MobileAds.instance.initialize();
      _sdkReady = true;
      _log.add('Mobile Ads SDK initialised.');
      unawaited(preloadInterstitial());
      unawaited(preloadRewarded());
    } catch (e) {
      _sdkReady = false;
      _log.add('Ads SDK failed to initialise: $e');
    }
  }

  /// Called when the player buys Remove Ads, so live units stop serving.
  Future<void> setAdsRemoved(bool removed) async {
    _adsRemoved = removed;
    if (removed) {
      _interstitial?.dispose();
      _rewarded?.dispose();
      _banner?.dispose();
      _interstitial = null;
      _rewarded = null;
      _banner = null;
      await _log.close();
    }
  }

  String get _bannerUnit => defaultTargetPlatform == TargetPlatform.iOS
      ? AdIds.testBannerIos
      : AdIds.testBannerAndroid;

  String get _interstitialUnit => defaultTargetPlatform == TargetPlatform.iOS
      ? AdIds.testInterstitialIos
      : AdIds.testInterstitialAndroid;

  String get _rewardedUnit => defaultTargetPlatform == TargetPlatform.iOS
      ? AdIds.testRewardedIos
      : AdIds.testRewardedAndroid;

  // ---------------------------------------------------------------------------
  // Banner
  // ---------------------------------------------------------------------------

  /// Builds a banner widget for the given size, or null when ads are off.
  ///
  /// The returned ad is owned by the caller widget and must be disposed with it.
  BannerAd? createBanner({AdSize size = AdSize.banner}) {
    if (_adsRemoved || !_sdkReady) return null;
    final BannerAd banner = BannerAd(
      adUnitId: _bannerUnit,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (Ad ad) => _log.add('Banner loaded.'),
        onAdFailedToLoad: (Ad ad, LoadAdError error) {
          _log.add('Banner failed: ${error.message}');
          ad.dispose();
        },
      ),
    );
    banner.load();
    return banner;
  }

  // ---------------------------------------------------------------------------
  // Interstitial
  // ---------------------------------------------------------------------------

  Future<void> preloadInterstitial() async {
    if (_adsRemoved ||
        !_sdkReady ||
        _loadingInterstitial ||
        _interstitial != null) {
      return;
    }
    _loadingInterstitial = true;
    await InterstitialAd.load(
      adUnitId: _interstitialUnit,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (InterstitialAd ad) {
          _loadingInterstitial = false;
          _interstitial = ad;
          _log.add('Interstitial ready.');
        },
        onAdFailedToLoad: (LoadAdError error) {
          _loadingInterstitial = false;
          _interstitial = null;
          _log.add('Interstitial failed: ${error.message}');
        },
      ),
    );
  }

  /// Shows an interstitial if the level cadence allows it. Returns true when an
  /// ad was actually presented.
  Future<bool> maybeShowInterstitial({bool force = false}) async {
    if (_adsRemoved || !_sdkReady) return false;
    _levelsSinceAd++;
    if (!force && _levelsSinceAd < _levelsPerAd) return false;
    if (_interstitial == null) {
      unawaited(preloadInterstitial());
      return false;
    }

    _levelsSinceAd = 0;
    final InterstitialAd ad = _interstitial!;
    _interstitial = null;
    final Completer<bool> done = Completer<bool>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (InterstitialAd a) {
        a.dispose();
        if (!done.isCompleted) done.complete(true);
        unawaited(preloadInterstitial());
      },
      onAdFailedToShowFullScreenContent: (InterstitialAd a, AdError error) {
        _log.add('Interstitial show failed: ${error.message}');
        a.dispose();
        if (!done.isCompleted) done.complete(false);
        unawaited(preloadInterstitial());
      },
    );
    await ad.show();
    // Guard against a callback that never arrives.
    return done.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () => false,
    );
  }

  // ---------------------------------------------------------------------------
  // Rewarded
  // ---------------------------------------------------------------------------

  Future<void> preloadRewarded() async {
    if (_adsRemoved || !_sdkReady || _loadingRewarded || _rewarded != null) {
      return;
    }
    _loadingRewarded = true;
    await RewardedAd.load(
      adUnitId: _rewardedUnit,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (RewardedAd ad) {
          _loadingRewarded = false;
          _rewarded = ad;
          _log.add('Rewarded ready.');
        },
        onAdFailedToLoad: (LoadAdError error) {
          _loadingRewarded = false;
          _rewarded = null;
          _log.add('Rewarded failed: ${error.message}');
        },
      ),
    );
  }

  /// Shows a rewarded video. Resolves with whether the reward was earned.
  ///
  /// The reward is only granted on [RewardOutcome.earned]; a dismissal or a
  /// failure gives nothing, which is what AdMob policy requires.
  Future<RewardOutcome> showRewarded() async {
    if (_adsRemoved) return RewardOutcome.failed;
    if (!_sdkReady) return RewardOutcome.failed;
    if (_rewarded == null) {
      unawaited(preloadRewarded());
      return RewardOutcome.notReady;
    }

    final RewardedAd ad = _rewarded!;
    _rewarded = null;
    final Completer<RewardOutcome> done = Completer<RewardOutcome>();
    bool earned = false;

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (RewardedAd a) {
        a.dispose();
        if (!done.isCompleted) {
          done.complete(
              earned ? RewardOutcome.earned : RewardOutcome.dismissed);
        }
        unawaited(preloadRewarded());
      },
      onAdFailedToShowFullScreenContent: (RewardedAd a, AdError error) {
        _log.add('Rewarded show failed: ${error.message}');
        a.dispose();
        if (!done.isCompleted) done.complete(RewardOutcome.failed);
        unawaited(preloadRewarded());
      },
    );

    await ad.show(
      onUserEarnedReward: (AdWithoutView _, RewardItem reward) {
        earned = true;
        _log.add('Reward earned: ${reward.amount} ${reward.type}');
      },
    );

    return done.future.timeout(
      const Duration(seconds: 60),
      onTimeout: () => earned ? RewardOutcome.earned : RewardOutcome.failed,
    );
  }

  void dispose() {
    _interstitial?.dispose();
    _rewarded?.dispose();
    _banner?.dispose();
    _interstitial = null;
    _rewarded = null;
    _banner = null;
  }
}
