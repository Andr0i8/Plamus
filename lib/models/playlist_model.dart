/// User-defined playlist metadata (not smart lists like Liked / History).
class PlaylistModel {
  /// Creates a playlist; [id] is null before insert.
  const PlaylistModel({
    this.id,
    required this.name,
    required this.dateCreated,
  });

  final int? id;
  final String name;

  /// ISO-8601 timestamp when the playlist was created.
  final String dateCreated;

  factory PlaylistModel.fromMap(Map<String, Object?> map) {
    return PlaylistModel(
      id: map['id'] as int?,
      name: map['name'] as String? ?? 'Playlist',
      dateCreated: map['dateCreated'] as String? ?? '',
    );
  }

  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'dateCreated': dateCreated,
    };
  }

  PlaylistModel copyWith({int? id, String? name, String? dateCreated}) {
    return PlaylistModel(
      id: id ?? this.id,
      name: name ?? this.name,
      dateCreated: dateCreated ?? this.dateCreated,
    );
  }
}
