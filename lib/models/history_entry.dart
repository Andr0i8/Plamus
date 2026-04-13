import 'track_model.dart';

/// Single play event for "Recently played" (backed by `history` + `tracks`).
class HistoryEntry {
  const HistoryEntry({
    required this.track,
    required this.playedAt,
  });

  final TrackModel track;

  /// ISO-8601 when the user played this track.
  final String playedAt;
}
