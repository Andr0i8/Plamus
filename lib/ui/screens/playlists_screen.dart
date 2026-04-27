import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';

import '../../models/playlist_model.dart';
import '../../services/library_service.dart';
import 'playlist_detail_screen.dart';

/// Index page for user playlists on mobile.
///
/// On desktop, playlists live inside the sidebar; on mobile we surface them as
/// a dedicated tab with a list of cards. Tapping a card pushes the existing
/// [PlaylistDetailScreen] within the current navigator (so the bottom nav
/// stays visible while inside a playlist).
class PlaylistsScreen extends StatelessWidget {
  /// Creates the playlists list screen.
  const PlaylistsScreen({super.key});

  Future<void> _createPlaylist(BuildContext context) async {
    final ctrl = TextEditingController(text: 'New playlist');
    String? name;
    try {
      name = await showDialog<String>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: const Text('Create playlist'),
            content: TextField(
              controller: ctrl,
              decoration: const InputDecoration(labelText: 'Name'),
              autofocus: true,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                child: const Text('Create'),
              ),
            ],
          );
        },
      );
    } finally {
      ctrl.dispose();
    }
    if (!context.mounted || name == null || name.isEmpty) return;
    try {
      await context.read<LibraryService>().createPlaylist(name);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create playlist: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lib = context.watch<LibraryService>();
    final playlists = lib.playlists;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Row(
                children: [
                  Text(
                    'Playlists',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  FilledButton.tonalIcon(
                    onPressed: () => _createPlaylist(context),
                    icon: const FaIcon(FontAwesomeIcons.plus, size: 14),
                    label: const Text('New'),
                  ),
                ],
              ),
            ),
          ),
          if (playlists.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    'No playlists yet — tap "New" to create one.',
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => _PlaylistCard(playlist: playlists[i]),
                childCount: playlists.length,
              ),
            ),
        ],
      ),
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  const _PlaylistCard({required this.playlist});

  final PlaylistModel playlist;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final id = playlist.id;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Material(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: id == null
              ? null
              : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => Scaffold(
                        appBar: AppBar(title: Text(playlist.name)),
                        body: PlaylistDetailScreen(playlistId: id),
                      ),
                    ),
                  ),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                FontAwesomeIcons.recordVinyl,
                color: theme.colorScheme.primary,
              ),
            ),
            title: Text(
              playlist.name,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            trailing: const Icon(Icons.chevron_right),
          ),
        ),
      ),
    );
  }
}
