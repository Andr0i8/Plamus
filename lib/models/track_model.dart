/// Domain model for a single audio [Track] row in SQLite.
///
/// Maps to the `tracks` table. [durationMs] is stored in milliseconds for
/// precision; [isLiked] mirrors the smart "Liked Songs" list.
class TrackModel {
  /// Creates a track with optional [id] (null before insert).
  const TrackModel({
    this.id,
    required this.title,
    required this.artist,
    required this.filePath,
    required this.durationMs,
    this.isLiked = false,
    required this.dateAdded,
  });

  /// SQLite primary key; null when not yet persisted.
  final int? id;

  /// Display title; user-editable and may differ from file name.
  final String title;

  /// Artist or "Unknown" when missing.
  final String artist;

  /// UI label for [artist]: empty or generic "Unknown" → "Various Artists".
  String get displayArtistLabel {
    final a = artist.trim();
    if (a.isEmpty || a.toLowerCase() == 'unknown') {
      return 'Various Artists';
    }
    return a;
  }

  /// Absolute path to the audio file on disk (library or user folder).
  final String filePath;

  /// Duration in milliseconds (0 if unknown).
  final int durationMs;

  /// When true, track appears in the Liked Songs smart list.
  final bool isLiked;

  /// When the track was added to the library (ISO-8601 string).
  final String dateAdded;

  /// Builds a [TrackModel] from a SQLite row map.
  factory TrackModel.fromMap(Map<String, Object?> map) {
    return TrackModel(
      id: map['id'] as int?,
      title: map['title'] as String? ?? 'Untitled',
      artist: map['artist'] as String? ?? 'Unknown',
      filePath: map['filePath'] as String? ?? '',
      durationMs: (map['durationMs'] as int?) ?? 0,
      isLiked: ((map['isLiked'] as int?) ?? 0) == 1,
      dateAdded: map['dateAdded'] as String? ?? '',
    );
  }

  /// Converts this model to a map for inserts/updates (excludes null [id] on insert).
  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      'title': title,
      'artist': artist,
      'filePath': filePath,
      'durationMs': durationMs,
      'isLiked': isLiked ? 1 : 0,
      'dateAdded': dateAdded,
    };
  }

  /// Returns a copy with selective overrides.
  TrackModel copyWith({
    int? id,
    String? title,
    String? artist,
    String? filePath,
    int? durationMs,
    bool? isLiked,
    String? dateAdded,
  }) {
    return TrackModel(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      filePath: filePath ?? this.filePath,
      durationMs: durationMs ?? this.durationMs,
      isLiked: isLiked ?? this.isLiked,
      dateAdded: dateAdded ?? this.dateAdded,
    );
  }
}
