import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/library_service.dart';
import '../widgets/import_modal.dart';
import '../widgets/track_tile.dart';

/// Main library grid/list: all tracks with import entry point.
class HomeLibraryScreen extends StatelessWidget {
  /// Creates the home library screen.
  const HomeLibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryService>();
    final tracks = lib.tracks;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(32, 32, 32, 16),
              child: Row(
                children: [
                  Text(
                    'Your library',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: () => showPlamusImportDialog(context),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    ),
                    icon: const Icon(Icons.add),
                    label: const Text('Import'),
                  ),
                ],
              ),
            ),
          ),
          if (tracks.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(
                  'No tracks yet. Import files or paste a link.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final t = tracks[i];
                  return TrackTile(
                    track: t,
                    contextTracks: tracks,
                    onRenamed: () => lib.refreshTracks(),
                  );
                },
                childCount: tracks.length,
              ),
            ),
        ],
      ),
    );
  }
}
