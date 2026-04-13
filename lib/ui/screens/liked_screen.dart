import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../database/database_helper.dart';
import '../../models/track_model.dart';
import '../../services/audio_player_service.dart';
import '../../services/library_service.dart';
import '../widgets/track_tile.dart';

/// Smart list of liked tracks (`tracks.isLiked = 1`).
class LikedScreen extends StatefulWidget {
  /// Creates the liked songs screen.
  const LikedScreen({super.key});

  @override
  State<LikedScreen> createState() => _LikedScreenState();
}

class _LikedScreenState extends State<LikedScreen> {
  late Future<List<TrackModel>> _future;

  @override
  void initState() {
    super.initState();
    _future = DatabaseHelper.instance.getLikedTracks();
  }

  void _reload() {
    setState(() {
      _future = DatabaseHelper.instance.getLikedTracks();
    });
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.read<LibraryService>();
    final audio = context.read<AudioPlayerService>();

    return Scaffold(
      body: FutureBuilder<List<TrackModel>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final tracks = snap.data ?? [];
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(32, 32, 32, 16),
                  child: Row(
                    children: [
                      Text(
                        'Liked songs',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const Spacer(),
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
                  child: Center(child: Text('Like tracks from your library.')),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => TrackTile(
                      track: tracks[i],
                      contextTracks: tracks,
                      onRenamed: () {
                        lib.refreshTracks();
                        _reload();
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
  }
}
