import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';

import '../../models/playlist_model.dart';
import '../../services/library_service.dart';
import '../../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../screens/history_screen.dart';
import '../screens/home_library_screen.dart';
import '../screens/import_screen.dart';
import '../screens/liked_screen.dart';
import '../screens/playlist_detail_screen.dart';
import '../widgets/glass_player_bar.dart';

/// Sidebar destinations and smooth content transitions.
enum PlamusSection {
  library,
  importPage,
  liked,
  history,
  playlist,
}

/// Root shell: left rail + animated body + glass bottom player.
class PlamusShell extends StatefulWidget {
  /// Creates the main application shell.
  const PlamusShell({super.key});

  @override
  State<PlamusShell> createState() => _PlamusShellState();
}

class _PlamusShellState extends State<PlamusShell> {
  PlamusSection _section = PlamusSection.library;
  int? _playlistId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<LibraryService>().refreshAll();
    });
  }

  void _openPlaylist(PlaylistModel p) {
    if (p.id == null) return;
    setState(() {
      _section = PlamusSection.playlist;
      _playlistId = p.id;
    });
  }

  Future<void> _createPlaylist() async {
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
    if (!mounted) return;
    if (name == null || name.isEmpty) return;
    try {
      final id = await context.read<LibraryService>().createPlaylist(name);
      if (!mounted) return;
      setState(() {
        _section = PlamusSection.playlist;
        _playlistId = id;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create playlist: $e')),
      );
    }
  }

  Widget _buildBody(ThemeData theme) {
    final playlistId = _playlistId;
    switch (_section) {
      case PlamusSection.library:
        return const HomeLibraryScreen();
      case PlamusSection.importPage:
        return const ImportScreen();
      case PlamusSection.liked:
        return const LikedScreen();
      case PlamusSection.history:
        return const HistoryScreen();
      case PlamusSection.playlist:
        if (playlistId == null) {
          return const HomeLibraryScreen();
        }
        return PlaylistDetailScreen(playlistId: playlistId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final sidebarColor = brightness == Brightness.dark
        ? PlamusColors.darkSidebar
        : PlamusColors.lightSidebar;

    final lib = context.watch<LibraryService>();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Row(
        children: [
          Container(
            width: 240,
            margin: const EdgeInsets.all(16),
            child: Material(
              color: sidebarColor,
              borderRadius: BorderRadius.circular(30),
              elevation: 0,
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 8, bottom: 8),
                    child: Text(
                      'Plamus',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  _NavButton(
                    label: 'Home',
                    icon: FontAwesomeIcons.house,
                    selected: _section == PlamusSection.library,
                    onTap: () => setState(() => _section = PlamusSection.library),
                  ),
                  _NavButton(
                    label: 'Search / import',
                    icon: FontAwesomeIcons.magnifyingGlass,
                    selected: _section == PlamusSection.importPage,
                    onTap: () => setState(() => _section = PlamusSection.importPage),
                  ),
                  _NavButton(
                    label: 'Liked songs',
                    icon: FontAwesomeIcons.heart,
                    selected: _section == PlamusSection.liked,
                    onTap: () => setState(() => _section = PlamusSection.liked),
                  ),
                  _NavButton(
                    label: 'History',
                    icon: FontAwesomeIcons.clock,
                    selected: _section == PlamusSection.history,
                    onTap: () => setState(() => _section = PlamusSection.history),
                  ),
                  const Divider(height: 40),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: FilledButton.tonalIcon(
                      onPressed: _createPlaylist,
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(25),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      ),
                      icon: const FaIcon(FontAwesomeIcons.plus, size: 16),
                      label: const Text('Create playlist'),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.only(left: 8, top: 8, bottom: 12),
                    child: Text(
                      'Playlists',
                      style: theme.textTheme.labelLarge,
                    ),
                  ),
                  ...lib.playlists.map(
                    (p) => _PlaylistSidebarTile(
                      playlist: p,
                      selected: _section == PlamusSection.playlist &&
                          _playlistId == p.id,
                      onOpen: () => _openPlaylist(p),
                      onChanged: () =>
                          context.read<LibraryService>().refreshAll(),
                      onDeleted: (id) {
                        if (_playlistId == id) {
                          setState(() {
                            _section = PlamusSection.library;
                            _playlistId = null;
                          });
                        }
                      },
                    ),
                  ),
                  const Divider(height: 24),
                  Consumer<ThemeController>(
                    builder: (context, tc, _) {
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          tc.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                        ),
                        title: Text(tc.isDark ? 'Light theme' : 'Dark theme'),
                        onTap: tc.toggle,
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    child: KeyedSubtree(
                      key: ValueKey<String>(
                        '${_section.name}-${_playlistId ?? 0}',
                      ),
                      child: _buildBody(theme),
                    ),
                  ),
                ),
                const GlassPlayerBar(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavButton extends StatefulWidget {
  const _NavButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_NavButton> createState() => _NavButtonState();
}

class _PlaylistSidebarTile extends StatelessWidget {
  const _PlaylistSidebarTile({
    required this.playlist,
    required this.selected,
    required this.onOpen,
    required this.onChanged,
    required this.onDeleted,
  });

  final PlaylistModel playlist;
  final bool selected;
  final VoidCallback onOpen;
  final VoidCallback onChanged;
  final void Function(int id) onDeleted;

  Future<void> _rename(BuildContext context) async {
    if (playlist.id == null) return;
    final ctrl = TextEditingController(text: playlist.name);
    String? name;
    try {
      name = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Rename playlist'),
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
              child: const Text('Save'),
            ),
          ],
        ),
      );
    } finally {
      ctrl.dispose();
    }
    if (!context.mounted) return;
    if (name == null || name.isEmpty) return;
    try {
      await context.read<LibraryService>().renamePlaylist(playlist.id!, name);
      if (!context.mounted) return;
      onChanged();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Rename failed: $e')),
        );
      }
    }
  }

  Future<void> _delete(BuildContext context) async {
    if (playlist.id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete playlist?'),
        content: const Text('Tracks stay in your library; only the playlist is removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!context.mounted) return;
    try {
      final id = playlist.id!;
      await context.read<LibraryService>().deletePlaylist(id);
      if (!context.mounted) return;
      onDeleted(id);
      onChanged();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected ? theme.colorScheme.primary : theme.colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected
            ? theme.colorScheme.primary.withValues(alpha: 0.18)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(25),
        child: ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          leading: FaIcon(FontAwesomeIcons.listUl, size: 18, color: color),
          title: Text(
            playlist.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: color,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
          onTap: onOpen,
          trailing: PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'rename') {
                _rename(context);
              } else if (v == 'delete') {
                _delete(context);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'rename', child: Text('Rename')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavButtonState extends State<_NavButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.textTheme.bodyLarge?.color ?? Colors.white;
    final color = widget.selected ? theme.colorScheme.primary : base;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: AnimatedScale(
          scale: _hover ? 1.02 : 1.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: widget.selected
                  ? theme.colorScheme.primary.withValues(alpha: 0.18)
                  : _hover
                      ? theme.colorScheme.primary.withValues(alpha: 0.08)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(25),
            ),
            child: ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              leading: FaIcon(widget.icon, size: 18, color: color),
              title: Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: color,
                  fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
              onTap: widget.onTap,
            ),
          ),
        ),
      ),
    );
  }
}
