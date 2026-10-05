import 'dart:async';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

import '../services/persistence_service.dart';

/// The sounds the game can play.
enum Sfx {
  swap,
  invalidSwap,
  match,
  special,
  rocket,
  bomb,
  rainbow,
  cascade,
  star,
  win,
  lose,
  click,
}

/// Names of the combo voiceovers, so a caller can pick one by combo size.
class ComboVoice {
  ComboVoice._();

  static const List<String> lines = <String>[
    'Sweet!',
    'Tasty!',
    'Delicious!',
    'Divine!',
    'Sugar Crush!'
  ];

  static String forCascade(int index) =>
      lines[index.clamp(0, lines.length - 1)];
}

/// Central audio + haptics hub.
///
/// Every asset is optional: if a file is missing the call is a silent no-op, so
/// the game is fully playable with an empty `assets/audio` directory. Drop real
/// files in with the names below to bring it to life.
class AudioService {
  AudioService._();

  static final AudioService instance = AudioService._();

  final AudioPlayer _sfxPlayer = AudioPlayer(playerId: 'cc_sfx_a');
  final AudioPlayer _sfxPlayerB = AudioPlayer(playerId: 'cc_sfx_b');
  final AudioPlayer _musicPlayer = AudioPlayer(playerId: 'cc_music');
  final Random _rng = Random();

  bool _soundOn = true;
  bool _musicOn = true;
  bool _hapticsOn = true;
  bool _musicPlaying = false;
  bool _sfxUseB = false;
  int _lastSfxMs = 0;

  /// Asset paths. Replace with your own files, or delete the entry to disable.
  static const Map<Sfx, String> _sfxAssets = <Sfx, String>{
    Sfx.swap: 'audio/swap.mp3',
    Sfx.invalidSwap: 'audio/invalid.mp3',
    Sfx.match: 'audio/match.mp3',
    Sfx.special: 'audio/special.mp3',
    Sfx.rocket: 'audio/rocket.mp3',
    Sfx.bomb: 'audio/bomb.mp3',
    Sfx.rainbow: 'audio/rainbow.mp3',
    Sfx.cascade: 'audio/cascade.mp3',
    Sfx.star: 'audio/star.mp3',
    Sfx.win: 'audio/win.mp3',
    Sfx.lose: 'audio/lose.mp3',
    Sfx.click: 'audio/click.mp3',
  };

  static const String _musicAsset = 'audio/music.mp3';

  /// Applies the player's saved toggles.
  void configure(PlayerProgress progress) {
    _soundOn = progress.soundOn;
    _musicOn = progress.musicOn;
    _hapticsOn = progress.hapticsOn;
    if (_musicOn) {
      unawaited(playMusic());
    } else {
      unawaited(stopMusic());
    }
  }

  set soundOn(bool value) {
    _soundOn = value;
  }

  set musicOn(bool value) {
    _musicOn = value;
    if (value) {
      unawaited(playMusic());
    } else {
      unawaited(stopMusic());
    }
  }

  set hapticsOn(bool value) => _hapticsOn = value;

  /// Plays a one shot effect. Uses two alternating players so a rapid cascade
  /// does not cut itself off.
  Future<void> play(Sfx sfx,
      {double volume = 1.0, bool throttle = true}) async {
    if (!_soundOn) return;
    final int nowMs = DateTime.now().millisecondsSinceEpoch;
    // Cascade sounds can fire dozens of times per second; keep them musical.
    if (throttle && nowMs - _lastSfxMs < 45) return;
    _lastSfxMs = nowMs;

    final String? asset = _sfxAssets[sfx];
    if (asset == null) return;
    final AudioPlayer player = _sfxUseB ? _sfxPlayerB : _sfxPlayer;
    _sfxUseB = !_sfxUseB;
    try {
      await player.stop();
      await player.setVolume(volume);
      await player.play(AssetSource(asset));
    } catch (_) {
      // Missing asset or platform hiccup: the game keeps running silently.
    }
  }

  Future<void> playMusic() async {
    if (!_musicOn || _musicPlaying) return;
    try {
      await _musicPlayer.setReleaseMode(ReleaseMode.loop);
      await _musicPlayer.setVolume(0.35);
      await _musicPlayer.play(AssetSource(_musicAsset));
      _musicPlaying = true;
    } catch (_) {
      // No music asset shipped: ignore.
    }
  }

  Future<void> stopMusic() async {
    _musicPlaying = false;
    try {
      await _musicPlayer.stop();
    } catch (_) {}
  }

  Future<void> pauseMusic() async {
    try {
      await _musicPlayer.pause();
    } catch (_) {}
  }

  Future<void> resumeMusic() async {
    if (!_musicOn) return;
    try {
      await _musicPlayer.resume();
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Haptics
  // ---------------------------------------------------------------------------

  Future<void> hapticLight() async {
    if (!_hapticsOn) return;
    await HapticFeedback.lightImpact();
  }

  Future<void> hapticMedium() async {
    if (!_hapticsOn) return;
    await HapticFeedback.mediumImpact();
  }

  Future<void> hapticHeavy() async {
    if (!_hapticsOn) return;
    await HapticFeedback.heavyImpact();
  }

  Future<void> hapticSelection() async {
    if (!_hapticsOn) return;
    await HapticFeedback.selectionClick();
  }

  /// A short buzz pattern used on a big combo.
  Future<void> hapticCombo(int strength) async {
    if (!_hapticsOn) return;
    if (strength <= 0) {
      await HapticFeedback.selectionClick();
    } else if (strength == 1) {
      await HapticFeedback.lightImpact();
    } else if (strength == 2) {
      await HapticFeedback.mediumImpact();
    } else {
      await HapticFeedback.heavyImpact();
    }
  }

  /// Random short "yum" for a cascade, so repeats do not sound mechanical.
  String randomComboVoice() =>
      ComboVoice.lines[_rng.nextInt(ComboVoice.lines.length)];

  void dispose() {
    _sfxPlayer.dispose();
    _sfxPlayerB.dispose();
    _musicPlayer.dispose();
  }
}
