import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart' as ja;

import '../database/database_helper.dart';
import '../models/repeat_mode.dart';
import '../models/track_model.dart';

/// Wraps [ja.AudioPlayer] with queue, shuffle, repeat, volume, and history hooks.
///
/// Notifies listeners on position/duration/index/shuffle changes.
///
/// Cross-platform notes:
///   * **Windows/Linux** — backed by media_kit via `just_audio_media_kit`. Plays
///     while the window is minimized (desktop OS audio mix). System media keys
///     are not wired (no MPRIS / SMTC integration).
///   * **Android** — backed by the native just_audio plugin. When
///     `just_audio_background` is initialized in `main`, every track surfaces in
///     the lock-screen / notification media session via the [MediaItem] tag
///     attached to its [ja.AudioSource]. Audio focus (calls, other media apps)
///     is delegated to the configured [AudioSession].
///
/// `just_audio` is imported as `ja` so Plamus's `RepeatMode` model stays
/// unambiguous (vs. just_audio / Flutter types of the same name).
class AudioPlayerService extends ChangeNotifier {
  /// Creates the service; call [init] once before use.
  AudioPlayerService() : _player = ja.AudioPlayer();

  final ja.AudioPlayer _player;
  final DatabaseHelper _db = DatabaseHelper.instance;

  /// Ordered list currently driving playback (insertion order).
  ///
  /// Shuffle does not reorder this list — instead just_audio applies a
  /// shuffled index permutation, which preserves a natural back-stack for
  /// "previous" navigation through already-played tracks.
  List<TrackModel> _queue = [];

  /// Index in [_queue] for the active track (always reflects insertion order,
  /// not shuffle position).
  int _index = 0;

  /// Repeat behavior for boundaries and single-track loop.
  RepeatMode repeatMode = RepeatMode.off;

  /// Whether the engine is currently traversing the queue in shuffled order.
  bool _shuffleEnabled = false;

  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration?>? _durSub;
  StreamSubscription<ja.PlayerState>? _stateSub;
  StreamSubscription<int?>? _indexSub;

  /// Latest known position for UI.
  Duration position = Duration.zero;

  /// Latest known total duration (may be zero while loading).
  Duration duration = Duration.zero;

  /// Whether the engine is actively playing audio.
  bool playing = false;

  /// Volume in the range 0.0–1.0 (maps to UI 0–100%).
  double volume = 1;

  /// The active queue (unmodifiable view, insertion order).
  List<TrackModel> get queue => List.unmodifiable(_queue);

  /// Current track or null if the queue is empty.
  TrackModel? get currentTrack =>
      _queue.isEmpty ? null : _queue[_index.clamp(0, _queue.length - 1)];

  /// Whether shuffle mode is on.
  bool get shuffleEnabled => _shuffleEnabled;

  /// 0.0–1.0 progress for sliders; 0 when duration unknown.
  double get progressFraction {
    if (duration.inMilliseconds <= 0) return 0;
    return (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
  }

  /// Configures the [AudioSession] and wires player streams.
  ///
  /// On Android, [AudioSessionConfiguration.music] negotiates focus correctly
  /// with phone calls and other media apps (auto-pause on call, resume after).
  Future<void> init() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    await _player.setVolume(volume);
    // Ensure loop mode starts as off (not stuck in repeat-one)
    await _player.setLoopMode(ja.LoopMode.off);
    await _player.setShuffleModeEnabled(false);
    await _attachStreams();
  }

  Future<void> _attachStreams() async {
    await _posSub?.cancel();
    await _durSub?.cancel();
    await _stateSub?.cancel();
    await _indexSub?.cancel();

    _posSub = _player.positionStream.listen((d) {
      position = d;
      notifyListeners();
    });
    _durSub = _player.durationStream.listen((d) {
      duration = d ?? Duration.zero;
      notifyListeners();
    });
    _stateSub = _player.playerStateStream.listen((s) {
      playing = s.playing;
      notifyListeners();
    });
    _indexSub = _player.currentIndexStream.listen((idx) {
      if (idx != null && idx < _queue.length) {
        if (idx != _index) {
          _index = idx;
          _recordPlayForCurrentTrack();
        }
        notifyListeners();
      }
    });
  }

  /// Builds an audio source for [track] with a [MediaItem] tag so that
  /// `just_audio_background` can surface metadata in the Android system
  /// media session. The tag is harmless on platforms without a background
  /// service (Windows): just_audio simply ignores the unused tag.
  ja.AudioSource _sourceForTrack(TrackModel track) {
    final mediaItem = MediaItem(
      id: track.id?.toString() ?? track.filePath,
      title: track.title,
      artist: track.displayArtistLabel,
      duration: track.durationMs > 0
          ? Duration(milliseconds: track.durationMs)
          : null,
    );
    return ja.AudioSource.file(track.filePath, tag: mediaItem);
  }

  /// Replaces the queue and optionally starts at [startIndex].
  /// This is the GOLDEN MASTER queue builder - it sets up the entire
  /// ConcatenatingAudioSource so just_audio knows the full sequence.
  Future<void> setQueue(
    List<TrackModel> tracks, {
    int startIndex = 0,
    bool playImmediately = true,
  }) async {
    if (tracks.isEmpty) {
      await stop();
      return;
    }

    _queue = List<TrackModel>.from(tracks);
    _index = startIndex.clamp(0, _queue.length - 1);

    // Build ConcatenatingAudioSource for the entire queue
    final playlist = ja.ConcatenatingAudioSource(
      children: _queue.map(_sourceForTrack).toList(),
    );

    try {
      await _player.setAudioSource(playlist, initialIndex: _index);
      // Reapply shuffle: just_audio resets shuffle order whenever the audio
      // source changes, so we re-enable + reshuffle to keep behavior consistent
      // with the toggle state the user expects.
      if (_shuffleEnabled) {
        await _player.shuffle();
        await _player.setShuffleModeEnabled(true);
      }
      _recordPlayForCurrentTrack();
      if (playImmediately) {
        await _player.play();
      }
    } catch (e) {
      debugPrint('AudioPlayerService: failed to load queue: $e');
      rethrow;
    }
    notifyListeners();
  }

  /// Plays a single track from a list context. Builds the full queue
  /// with the clicked track as the starting point.
  Future<void> playTrackInContext(
    TrackModel clickedTrack,
    List<TrackModel> contextTracks,
  ) async {
    final clickedIndex = contextTracks.indexWhere(
      (t) => t.id == clickedTrack.id,
    );
    if (clickedIndex == -1) {
      // Fallback: play just this track
      await setQueue([clickedTrack], playImmediately: true);
      return;
    }
    await setQueue(contextTracks, startIndex: clickedIndex, playImmediately: true);
  }

  /// Toggles play/pause for a specific track. If it's already the current
  /// track, toggle playback. If it's a different track, start playing it.
  Future<void> togglePlayTrack(
    TrackModel clickedTrack,
    List<TrackModel> contextTracks,
  ) async {
    final current = currentTrack;

    // Same track: toggle play/pause
    if (current?.id != null && current?.id == clickedTrack.id) {
      if (playing) {
        await pause();
      } else {
        await play();
      }
      return;
    }

    // Different track: play it in context
    await playTrackInContext(clickedTrack, contextTracks);
  }

  /// Appends tracks without changing the current item.
  void appendToQueue(List<TrackModel> tracks) {
    _queue.addAll(tracks);
    notifyListeners();
  }

  /// Clears playback state.
  Future<void> stop() async {
    await _player.stop();
    _queue = [];
    _index = 0;
    notifyListeners();
  }

  /// Updates repeat mode and maps to just_audio LoopMode.
  Future<void> setRepeatMode(RepeatMode mode) async {
    repeatMode = mode;
    final loopMode = switch (mode) {
      RepeatMode.off => ja.LoopMode.off,
      RepeatMode.all => ja.LoopMode.all,
      RepeatMode.one => ja.LoopMode.one,
    };
    await _player.setLoopMode(loopMode);
    notifyListeners();
  }

  /// Toggles shuffle on/off, preserving the current track.
  ///
  /// just_audio implements shuffle as a permutation over the existing
  /// [ja.ConcatenatingAudioSource] indices — the queue model isn't reordered.
  /// Calling [ja.AudioPlayer.shuffle] regenerates the permutation; the
  /// permutation is fixed for the rest of the session, so "previous" walks
  /// back through already-played shuffled tracks (the required back-stack).
  Future<void> setShuffleEnabled(bool enabled) async {
    _shuffleEnabled = enabled;
    if (enabled) {
      // Generate a new shuffle order anchored at the current item, then enable.
      await _player.shuffle();
    }
    await _player.setShuffleModeEnabled(enabled);
    notifyListeners();
  }

  /// Convenience flip used by player-bar buttons.
  Future<void> toggleShuffle() => setShuffleEnabled(!_shuffleEnabled);

  /// Starts or resumes the current source.
  Future<void> play() async {
    if (currentTrack == null) return;
    await _player.play();
  }

  /// Pauses playback.
  Future<void> pause() async {
    await _player.pause();
  }

  /// Seeks within the current track.
  Future<void> seek(Duration target) async {
    await _player.seek(target);
  }

  /// Sets output volume (0.0–1.0).
  ///
  /// On Android, system volume buttons typically control the active stream
  /// directly; this slider is most useful as a finer per-track gain on desktop.
  Future<void> setVolumeLinear(double v) async {
    volume = v.clamp(0.0, 1.0);
    await _player.setVolume(volume);
    notifyListeners();
  }

  /// Moves to the next track using just_audio's built-in navigation.
  /// GOLDEN MASTER: Properly handles queue boundaries and repeat modes.
  /// Honors the current shuffle order automatically (just_audio handles it).
  Future<void> skipNext() async {
    if (_queue.isEmpty) return;

    if (_player.hasNext) {
      await _player.seekToNext();
      return;
    }

    // At the last item in playback order.
    if (repeatMode == RepeatMode.all) {
      await _player.seek(Duration.zero, index: 0);
      await _player.play();
    } else {
      await _player.pause();
      await _player.seek(Duration.zero);
    }
  }

  /// Moves to the previous track using just_audio's built-in navigation.
  /// GOLDEN MASTER: Properly handles queue boundaries and restart logic.
  /// Honors the shuffle back-stack automatically.
  Future<void> skipPrevious() async {
    if (_queue.isEmpty) return;

    // Restart current track if more than 2.5s in
    if (position.inMilliseconds > 2500) {
      await _player.seek(Duration.zero);
      return;
    }

    if (_player.hasPrevious) {
      await _player.seekToPrevious();
      return;
    }

    // At first item in playback order.
    if (repeatMode == RepeatMode.all) {
      await _player.seek(Duration.zero, index: _queue.length - 1);
      await _player.play();
    } else {
      // Just restart current track
      await _player.seek(Duration.zero);
    }
  }

  /// Records play history for the current track and updates duration if needed.
  Future<void> _recordPlayForCurrentTrack() async {
    final t = currentTrack;
    if (t == null || t.id == null) return;

    try {
      await _db.recordPlay(t.id!);

      // Update duration in DB if unknown
      final d = _player.duration;
      if (d != null && d > Duration.zero && t.durationMs == 0) {
        await _db.updateTrack(
          t.copyWith(durationMs: d.inMilliseconds),
        );
      }
    } catch (e) {
      debugPrint('AudioPlayerService: failed to record play: $e');
    }
  }

  @override
  void dispose() {
    unawaited(_posSub?.cancel());
    unawaited(_durSub?.cancel());
    unawaited(_stateSub?.cancel());
    unawaited(_indexSub?.cancel());
    unawaited(_player.dispose());
    super.dispose();
  }
}

/// Reserved for future Android-only audio focus reactions (e.g. ducking on
/// transient interruptions). Currently a no-op placeholder so callers can
/// reference the symbol without conditional imports.
@visibleForTesting
bool isAudioPlatformAndroid() => Platform.isAndroid;
