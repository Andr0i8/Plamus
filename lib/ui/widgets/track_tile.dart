import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';

import '../../models/track_model.dart';
import '../../services/audio_player_service.dart';
import '../../services/library_service.dart';

/// Library row with hover, context actions, and inline title editing.
class TrackTile extends StatefulWidget {
  /// Creates a track row.
  const TrackTile({
    super.key,
    required this.track,
    required this.onRenamed,
    this.contextTracks,
  });

  final TrackModel track;
  final VoidCallback onRenamed;
  /// Full list of tracks in the current view (for queue context).
  final List<TrackModel>? contextTracks;

  @override
  State<TrackTile> createState() => _TrackTileState();
}

class _TrackTileState extends State<TrackTile> {
  bool _hover = false;
  bool _editing = false;
  late final TextEditingController _titleCtrl =
      TextEditingController(text: widget.track.title);

  @override
  void didUpdateWidget(covariant TrackTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_editing && oldWidget.track.title != widget.track.title) {
      _titleCtrl.text = widget.track.title;
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  String _formatDuration(int ms) {
    if (ms <= 0) return '—';
    final d = Duration(milliseconds: ms);
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:$s';
    }
    return '$m:$s';
  }

  Future<void> _addToPlaylist() async {
    final lib = context.read<LibraryService>();
    await lib.refreshAll();
    final playlists = lib.playlists;
    if (!mounted) return;
    if (playlists.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Create a playlist first from the sidebar.'),
        ),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: playlists.map((p) {
              return ListTile(
                title: Text(p.name),
                onTap: () async {
                  if (p.id != null && widget.track.id != null) {
                    await lib.addTrackToPlaylist(p.id!, widget.track.id!);
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Added to playlist')),
                    );
                  }
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Future<void> _commitTitle() async {
    final lib = context.read<LibraryService>();
    try {
      await lib.renameTrackTitle(widget.track, _titleCtrl.text);
      if (!mounted) return;
      setState(() => _editing = false);
      widget.onRenamed();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not rename: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final audio = context.watch<AudioPlayerService>();
    final lib = context.read<LibraryService>();

    // Check if this track is currently playing
    final currentTrack = audio.currentTrack;
    final isPlaying = currentTrack?.id != null &&
                      currentTrack?.id == widget.track.id;
    final brandPurple = const Color(0xFF9C27B0);

    // Get context tracks for queue building
    final contextTracks = widget.contextTracks ?? [widget.track];

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedScale(
        scale: _hover ? 1.01 : 1.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
          decoration: BoxDecoration(
            color: isPlaying
                ? brandPurple.withValues(alpha: 0.12)
                : _hover
                    ? theme.colorScheme.primary.withValues(alpha: 0.06)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: IconButton(
            tooltip: widget.track.isLiked ? 'Unlike' : 'Like',
            icon: Icon(
              widget.track.isLiked ? Icons.favorite : Icons.favorite_border,
              color: widget.track.isLiked ? theme.colorScheme.primary : null,
              size: 22,
            ),
            onPressed: () async {
              await lib.toggleLike(widget.track);
              widget.onRenamed();
            },
          ),
          title: Row(
            children: [
              Expanded(
                child: _editing
                    ? TextField(
                        controller: _titleCtrl,
                        autofocus: true,
                        decoration: const InputDecoration(isDense: true),
                        onSubmitted: (_) => _commitTitle(),
                      )
                    : GestureDetector(
                        onTap: () => setState(() {
                          _editing = true;
                          _titleCtrl
                            ..text = widget.track.title
                            ..selection = TextSelection(
                              baseOffset: 0,
                              extentOffset: widget.track.title.length,
                            );
                        }),
                        child: Text(
                          widget.track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: isPlaying ? brandPurple : null,
                            fontWeight: isPlaying ? FontWeight.w600 : null,
                          ),
                        ),
                      ),
              ),
              if (isPlaying && audio.playing)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: _AnimatedMusicBars(color: brandPurple),
                ),
            ],
          ),
          subtitle: Text(
            '${widget.track.displayArtistLabel} · ${_formatDuration(widget.track.durationMs)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: isPlaying
                    ? (audio.playing ? 'Pause' : 'Resume')
                    : 'Play',
                icon: FaIcon(
                  isPlaying && audio.playing
                      ? FontAwesomeIcons.pause
                      : FontAwesomeIcons.play,
                  size: 18,
                ),
                onPressed: () async {
                  await audio.togglePlayTrack(widget.track, contextTracks);
                },
              ),
              PopupMenuButton<String>(
                onSelected: (value) async {
                  try {
                    if (value == 'playlist') {
                      await _addToPlaylist();
                    } else if (value == 'folder') {
                      await lib.revealTrackInExplorer(widget.track);
                    } else if (value == 'export') {
                      await lib.exportTrackTo(widget.track);
                    } else if (value == 'delete') {
                      await lib.deleteTrack(widget.track);
                      widget.onRenamed();
                    }
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('$e')),
                    );
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'playlist',
                    child: Text('Add to playlist…'),
                  ),
                  PopupMenuItem(value: 'folder', child: Text('Show in folder')),
                  PopupMenuItem(value: 'export', child: Text('Export to…')),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text('Remove from library'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }
}

/// Animated music visualizer bars for "now playing" indicator.
class _AnimatedMusicBars extends StatefulWidget {
  const _AnimatedMusicBars({required this.color});

  final Color color;

  @override
  State<_AnimatedMusicBars> createState() => _AnimatedMusicBarsState();
}

class _AnimatedMusicBarsState extends State<_AnimatedMusicBars>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 16,
      height: 16,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _Bar(
                height: 4 + (_controller.value * 8),
                color: widget.color,
              ),
              _Bar(
                height: 8 + ((1 - _controller.value) * 6),
                color: widget.color,
              ),
              _Bar(
                height: 6 + (_controller.value * 7),
                color: widget.color,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.height, required this.color});

  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 3,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}
