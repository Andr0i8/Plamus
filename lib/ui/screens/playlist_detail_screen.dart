import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../database/database_helper.dart';
import '../../models/playlist_model.dart';
import '../../models/track_model.dart';
import '../../services/audio_player_service.dart';
import '../../services/library_service.dart';
import '../widgets/track_tile.dart';

/// Single user playlist: lists ordered tracks and can play the whole queue.
class PlaylistDetailScreen extends StatefulWidget {
  /// Creates a playlist screen for the given [playlistId].
  const PlaylistDetailScreen({super.key, required this.playlistId});

  final int playlistId;

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  late Future<PlaylistModel?> _meta;
  late Future<List<TrackModel>> _tracks;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _meta = DatabaseHelper.instance.getPlaylistById(widget.playlistId);
    _tracks = DatabaseHelper.instance.getTracksForPlaylist(widget.playlistId);
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.read<LibraryService>();
    final audio = context.read<AudioPlayerService>();

    return FutureBuilder<PlaylistModel?>(
      future: _meta,
      builder: (context, metaSnap) {
        final name = metaSnap.data?.name ?? 'Playlist';
        return Scaffold(
          body: FutureBuilder<List<TrackModel>>(
            future: _tracks,
            builder: (context, trackSnap) {
              if (!trackSnap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final tracks = trackSnap.data!;

              return CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(32, 32, 32, 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          if (tracks.isNotEmpty)
                            FilledButton(
                              onPressed: () async {
                                await audio.setQueue(
                                  tracks,
                                  playImmediately: true,
                                );
                              },
                              style: FilledButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30),
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                              ),
                              child: const Text('Play all'),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (tracks.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Text('No tracks yet. Add some from the library menu.'),
                      ),
                    )
                  else
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => TrackTile(
                          track: tracks[i],
                          contextTracks: tracks,
                          onRenamed: () {
                            lib.refreshAll();
                            setState(_reload);
                          },
                        ),
                        childCount: tracks.length,
                      ),
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}
