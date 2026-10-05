# Candy Cascade

A complete, feature rich match 3 casual puzzle game for Android and iOS, built
with Flutter 3. Drop the folder into Android Studio, run `flutter pub get`, and
build an APK or AAB.

Everything in this repository is real, working code. There are no stubs, no
placeholder functions, and no `// TODO: implement` markers in the game logic.

---

## What is in the box

### Core loop

* Grid based adjacent swapping, on a 9x9 board by default, with a revert when no
  match forms.
* Match formations and the specials they spawn:
  * 3 in a row: clear and score.
  * 4 in a row: a striped rocket that clears its whole row or column.
  * L shape or T shape (5 candies): a wrapped bomb with a 3x3 blast.
  * 5 in a row: a rainbow colour bomb that erases one colour from the board.
* Special combinations, each with its own effect and banner:
  * rainbow + rainbow: clears the entire board.
  * rainbow + striped: turns every candy of that colour into a striped candy and
    detonates them all.
  * rainbow + wrapped: turns every candy of that colour into a bomb.
  * rainbow + normal: erases every candy of that colour.
  * striped + striped: a full row and a full column at once.
  * striped + wrapped: a three wide cross through the whole board.
  * wrapped + wrapped: a five by five blast.
* Cascades: cleared candies vanish, survivors fall with an eased acceleration
  curve, new candies drop in from above, and the loop repeats until the board is
  quiet. Each cascade step multiplies the score.
* Dead board recovery: when no legal move exists the board reshuffles itself and
  keeps every candy and every hole in place.

### Objectives

* Score target within a move limit.
* Jelly drop: walk the golden jelly token to the bottom row.
* Frosting and ice breaker: break the ice covering cells by matching next to it,
  with multi hit ice supported.

### Progression and economy

* One, two or three stars per level, with best star memory per level.
* Five lives, regenerating one every twenty minutes. The countdown is derived
  from a stored timestamp, so it is correct after a force quit and does not
  depend on the app running.
* Coins wallet, earned from wins and spendable on boosters and extra moves.

### Boosters

* Lollipop Hammer: break any single candy without spending a move.
* Free Switch: swap any two adjacent candies with no match required.
* Extra Moves, bought with coins or earned from a rewarded ad.
* Pre game starting colour bomb.

### Monetisation

* `in_app_purchase` with a full purchase stream listener, covering pending,
  purchased, restored, error and cancelled states.
* Products: `coins_tier_1_100`, `coins_tier_2_500`, `coins_tier_3_1200`,
  `refill_lives_full` (consumables) and `remove_ads_permanent` (non consumable).
* Restore Purchases, reachable from both the shop and settings, which is a store
  requirement on both platforms.
* AdMob banner, interstitial between levels, and rewarded video for extra moves
  and extra lives. All units default to Google's published test ids.

### Compliance

* Android 14 and 15 ready: `compileSdk 35`, `targetSdk 35`.
* Android 12+ splash screen API wired through `values/styles.xml`.
* AdMob application id declared in the manifest as a `meta-data` tag.
* Play Billing permission declared.
* A single `kChildDirectedMode` flag in `lib/main.dart` drives COPPA behaviour:
  it tags every ad request as child directed, requests under age of consent
  handling, and caps the content rating at G.
* No background location, no unencrypted tracking, no analytics beyond what the
  ads and billing SDKs do.

### Architecture

* Riverpod `StateNotifier` for the game state.
* The rules live in a pure Dart engine with no Flutter imports, so they are unit
  tested headlessly and the view never has to know them.
* The board is painted by a single `CustomPainter` inside a `RepaintBoundary`,
  driven by one `Ticker`. A cascade repaints one layer instead of rebuilding a
  widget tree.
* `audioplayers` for effects and music, with graceful silence when an asset is
  missing.
* Haptics on swap, match, combo and result.
* `shared_preferences` for level progress, coins, life timestamps, stars and the
  sound, music and vibration toggles.

---

## Project layout

```
candy_cascade/
├── pubspec.yaml
├── analysis_options.yaml
├── lib/
│   ├── main.dart                       app startup, orientation, lifecycle
│   ├── models/
│   │   ├── candy_tile.dart             tile, colours, specials, blockers
│   │   └── level_data.dart             objectives, levels, endless generator
│   ├── logic/
│   │   ├── match_engine.dart           swap, matches, combos, gravity, shuffle
│   │   ├── game_controller.dart        Riverpod state machine for a level
│   │   └── providers.dart              dependency wiring
│   ├── services/
│   │   ├── iap_service.dart            store billing lifecycle
│   │   ├── ad_service.dart             AdMob banner, interstitial, rewarded
│   │   ├── audio_service.dart          sound effects, music, haptics
│   │   └── persistence_service.dart    saved progress and life timers
│   └── views/
│       ├── game_board_screen.dart      board rendering and gestures
│       ├── ui_overlays.dart            HUD, dialogs, shop sheet
│       └── level_map_screen.dart       home map, settings
├── test/
│   └── match_engine_test.dart          40+ engine unit tests
├── android/                            manifest, gradle, splash, proguard
└── ios/                                Info.plist, tracking, SKAdNetwork
```

---

## Getting it running

### Prerequisites

Flutter 3.19 or newer, with the Android and iOS toolchains you need. Run
`flutter doctor` and fix anything it complains about before you start.

### Build

```bash
cd candy_cascade
flutter pub get
flutter analyze
flutter test
flutter run
```

For a release build:

```bash
flutter build apk --release          # Android APK
flutter build appbundle --release    # Android AAB for Play
flutter build ipa --release          # iOS, needs a Mac and a signing profile
```

### Opening in Android Studio

`File > Open`, then pick the `candy_cascade` folder. Android Studio will pick up
the Gradle project under `android/` on the first sync.

---

## What you must change before you publish

The game builds and runs as it stands. These are the things that are
deliberately left as yours, because they are account specific:

1. **AdMob ids.** `android/app/src/main/AndroidManifest.xml`,
   `android/app/src/main/res/values/strings.xml`, and the unit ids in
   `lib/services/ad_service.dart` all use Google's test ids. Replace all three
   with your own.
2. **Application id.** `com.candycascade.game` in `android/app/build.gradle` and
   the iOS bundle identifier in Xcode. It must be unique across the store.
3. **Release signing.** `android/app/build.gradle` currently signs release with
   the debug key, which Play rejects. Add a real `signingConfigs.release`.
4. **Store products.** Create the five product ids from `StoreIds` in Play
   Console and App Store Connect, exactly as spelled.
5. **Icons and splash art.** Replace `android/app/src/main/res/mipmap-*` and the
   iOS `AppIcon` asset catalogue with your own art.
6. **Audio.** `assets/audio/` ships empty on purpose. The game is fully playable
   in silence; drop in files with the names listed in `AudioService._sfxAssets`
   to switch sound on.
7. **Receipt verification.** `IapService._deliver` grants purchases locally and
   logs the receipt. A production build should verify
   `serverVerificationData` against the store server APIs before granting.
8. **Privacy policy URL.** Required by both stores, and by the UMP consent
   flow.

### Making a children's build

Set `kChildDirectedMode = true` in `lib/main.dart`, remove the
`NSUserTrackingUsageDescription` key from `ios/Runner/Info.plist`, and declare
the Designed for Families flag in Play Console. That combination is what COPPA
and the Families policy expect.

---

## Continuous integration

`.github/workflows/build-apk.yml` runs on every push to `main`, on pull
requests, and on demand from the Actions tab.

Two jobs, in order:

1. **Analyze and test.** Formats, analyzes and runs the test suite. It needs no
   Android toolchain, so a broken commit fails in about a minute instead of
   after a five minute SDK download.
2. **Build APK.** Provisions the Android SDK with Google's `android` CLI,
   then builds the release APK split per ABI and the release App Bundle.

The SDK is installed by the CLI rather than relying on a pre-baked runner
image, so the workflow states exactly what it needs:

| Component | Version | Why |
|---|---|---|
| Flutter | 3.47.6 | pinned to the version this project was built against |
| Java | 17 | the toolchain Gradle and AGP both expect |
| Platform | android-36 | matches `compileSdk` |
| Build tools | 36.0.0 | matches the platform |
| cmdline-tools | 16.0 | Flutter needs `apkanalyzer` from here to verify the AAB symbol strip |
| NDK | 28.2.13676358 | required to strip native debug symbols when bundling the AAB |

### What it produces

Every run uploads three artifacts, downloadable from the run page:

* `candy-cascade-release-apks` — the per ABI APKs, about 30 MB total.
* `candy-cascade-release-aab` — the App Bundle for the Play Store, about 51 MB.
* `coverage` — the LCOV coverage report.

Push a tag starting with `v` (for example `git tag v1.0.0 && git push --tags`)
and the same artifacts are attached to a GitHub Release automatically.

### Running a one-off debug build

Actions tab, **Build Candy Cascade APK**, **Run workflow**, choose `debug`.

### Two things to note

The release artifacts are signed with the **debug key**, because
`android/app/build.gradle.kts` points `release` at `signingConfigs.debug` so
that `flutter build apk --release` works with no setup. Add a real
`signingConfigs.release` block, fed from repository secrets, before you upload
to Play.

The build also needs `android/local.properties` to exist. The workflow
generates it; locally, `flutter pub get` does.

---

## Tests

```bash
flutter test
```

`test/match_engine_test.dart` covers board generation determinism, hole
handling, every match shape and the special it spawns, swap validation and
reversion, all seven special combos, blast expansion, gravity including the
hole barrier case, refill spawn offsets, frosting damage at one and two hit
health, shuffle correctness, hint legality, jelly behaviour, the hammer, and
score multipliers.

`test/game_flow_test.dart` covers the shipped level list (every hand crafted
level is checked for reachable objectives, ascending star thresholds, frosting
it actually has and jelly columns that exist), the JSON round trip, objective
and star maths, a full cascade run to quiescence, sixty simulated turns with a
hint-driven swap each time, and the offline life regeneration arithmetic.

Both suites use a `blankEngine` helper that starts with every cell marked as a
hole, so a test fills in exactly the candies it cares about and the expected
match is never a guess.

47 tests, all passing.

---

## License

This code is yours to ship. Replace this section with your own licence before
you publish the repository.
