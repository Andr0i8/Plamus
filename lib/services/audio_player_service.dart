import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart' as ja;

import '../database/database_helper.dart';
import '../models/repeat_mode.dart';
import '../models/track_model.dart';

/// Wraps [ja.AudioPlayer] with queue, repeat, volume, and history hooks.
///
/// Notifies listeners on position/duration/index changes. Continues playback
/// when the Flutter window is minimized (desktop OS audio mix).
///
/// `just_audio` is imported as `ja` so Plamus's `RepeatMode` model stays unambiguous
/// (vs. `just_audio` / Flutter types of the same name).
class AudioPlayerService extends ChangeNotifier {
  /// Creates the service; call [init] once before use.
  AudioPlayerService() : _player = ja.AudioPlayer();

  final ja.AudioPlayer _player;
  final DatabaseHelper _db = DatabaseHelper.instance;

  /// Ordered list currently driving playback.
  List<TrackModel> _queue = [];

  /// Index in [_queue] for the active track.
  int _index = 0;

  /// Repeat behavior for boundaries and single-track loop.
  RepeatMode repeatMode = RepeatMode.off;

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

  /// The active queue (unmodifiable view).
  List<TrackModel> get queue => List.unmodifiable(_queue);

  /// Current track or null if the queue is empty.
  TrackModel? get currentTrack =>
      _queue.isEmpty ? null : _queue[_index.clamp(0, _queue.length - 1)];

  /// 0.0–1.0 progress for sliders; 0 when duration unknown.
  double get progressFraction {
    if (duration.inMilliseconds <= 0) return 0;
    return (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
  }

  /// Configures session category and wires player streams.
  Future<void> init() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    await _player.setVolume(volume);
    // Ensure loop mode starts as off (not stuck in repeat-one)
    await _player.setLoopMode(ja.LoopMode.off);
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
      children: _queue.map((t) => ja.AudioSource.file(t.filePath)).toList(),
    );

    try {
      await _player.setAudioSource(playlist, initialIndex: _index);
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
  Future<void> setVolumeLinear(double v) async {
    volume = v.clamp(0.0, 1.0);
    await _player.setVolume(volume);
    notifyListeners();
  }

  /// Moves to the next track using just_audio's built-in navigation.
  /// GOLDEN MASTER: Properly handles queue boundaries and repeat modes.
  Future<void> skipNext() async {
    if (_queue.isEmpty) return;

    final currentIdx = _player.currentIndex ?? _index;
    final isLastTrack = currentIdx >= _queue.length - 1;

    if (!isLastTrack) {
      // Normal case: advance to next track
      await _player.seekToNext();
    } else {
      // At end of queue
      if (repeatMode == RepeatMode.all) {
        // Loop back to start
        await _player.seek(Duration.zero, index: 0);
        await _player.play();
      } else {
        // Stop at end
        await _player.pause();
        await _player.seek(Duration.zero);
      }
    }
  }

  /// Moves to the previous track using just_audio's built-in navigation.
  /// GOLDEN MASTER: Properly handles queue boundaries and restart logic.
  Future<void> skipPrevious() async {
    if (_queue.isEmpty) return;

    // Restart current track if more than 2.5s in
    if (position.inMilliseconds > 2500) {
      await _player.seek(Duration.zero);
      return;
    }

    final currentIdx = _player.currentIndex ?? _index;
    final isFirstTrack = currentIdx <= 0;

    if (!isFirstTrack) {
      // Normal case: go to previous track
      await _player.seekToPrevious();
    } else {
      // At start of queue
      if (repeatMode == RepeatMode.all) {
        // Loop to end
        await _player.seek(Duration.zero, index: _queue.length - 1);
        await _player.play();
      } else {
        // Just restart current track
        await _player.seek(Duration.zero);
      }
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
