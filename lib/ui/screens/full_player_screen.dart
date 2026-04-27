import 'package:flutter/material.dart' hide RepeatMode;
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';

import '../../models/repeat_mode.dart';
import '../../services/audio_player_service.dart';

/// Full-screen player surface used on Android (pushed from the mini-player).
///
/// Provides the same controls as the desktop glass player bar plus the
/// shuffle and repeat toggles on a generously sized layout that fits one
/// thumb. The hero artwork tile is a placeholder gradient — Plamus does not
/// currently extract embedded album art.
class FullPlayerScreen extends StatelessWidget {
  /// Creates the full-screen player.
  const FullPlayerScreen({super.key});

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(1, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      return '${d.inHours}:$m:$s';
    }
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final audio = context.watch<AudioPlayerService>();
    final track = audio.currentTrack;
    final primary = theme.colorScheme.primary;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down, size: 32),
          onPressed: () => Navigator.of(context).maybePop(),
          tooltip: 'Close player',
        ),
        title: const Text('Now playing'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            children: [
              const Spacer(),
              AspectRatio(
                aspectRatio: 1,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        primary.withValues(alpha: 0.7),
                        primary.withValues(alpha: 0.25),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Icon(
                    FontAwesomeIcons.music,
                    size: 96,
                    color: theme.colorScheme.onPrimary.withValues(alpha: 0.85),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                track?.title ?? 'Nothing playing',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(
                track?.displayArtistLabel ?? '—',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.textTheme.bodySmall?.color,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 20),
              Slider(
                value: audio.progressFraction.clamp(0.0, 1.0),
                onChanged: track == null
                    ? null
                    : (v) {
                        final ms = (audio.duration.inMilliseconds * v).round();
                        audio.seek(Duration(milliseconds: ms));
                      },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_fmt(audio.position), style: theme.textTheme.labelSmall),
                    Text(_fmt(audio.duration), style: theme.textTheme.labelSmall),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    iconSize: 28,
                    tooltip: audio.shuffleEnabled
                        ? 'Shuffle: on'
                        : 'Shuffle: off',
                    onPressed: track == null ? null : audio.toggleShuffle,
                    icon: FaIcon(
                      FontAwesomeIcons.shuffle,
                      color: audio.shuffleEnabled
                          ? primary
                          : theme.iconTheme.color,
                    ),
                  ),
                  IconButton(
                    iconSize: 36,
                    tooltip: 'Previous',
                    onPressed: track == null ? null : audio.skipPrevious,
                    icon: const FaIcon(FontAwesomeIcons.backwardStep),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      shape: const CircleBorder(),
                      padding: const EdgeInsets.all(20),
                      minimumSize: const Size(72, 72),
                      backgroundColor: primary,
                    ),
                    onPressed: track == null
                        ? null
                        : () async {
                            if (audio.playing) {
                              await audio.pause();
                            } else {
                              await audio.play();
                            }
                          },
                    child: Icon(
                      audio.playing
                          ? FontAwesomeIcons.pause
                          : FontAwesomeIcons.play,
                      size: 26,
                      color: theme.colorScheme.onPrimary,
                    ),
                  ),
                  IconButton(
                    iconSize: 36,
                    tooltip: 'Next',
                    onPressed: track == null ? null : audio.skipNext,
                    icon: const FaIcon(FontAwesomeIcons.forwardStep),
                  ),
                  IconButton(
                    iconSize: 28,
                    tooltip: _repeatTooltip(audio.repeatMode),
                    onPressed: track == null
                        ? null
                        : () {
                            final next = switch (audio.repeatMode) {
                              RepeatMode.off => RepeatMode.all,
                              RepeatMode.all => RepeatMode.one,
                              RepeatMode.one => RepeatMode.off,
                            };
                            audio.setRepeatMode(next);
                          },
                    icon: _repeatIcon(audio.repeatMode, primary, theme),
                  ),
                ],
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  String _repeatTooltip(RepeatMode m) {
    return switch (m) {
      RepeatMode.off => 'Repeat: off',
      RepeatMode.all => 'Repeat: all',
      RepeatMode.one => 'Repeat: one',
    };
  }

  Widget _repeatIcon(RepeatMode m, Color primary, ThemeData theme) {
    final base = theme.iconTheme.color ?? Colors.white;
    return switch (m) {
      RepeatMode.off => Icon(
          Icons.close,
          size: 26,
          color: base.withValues(alpha: 0.5),
        ),
      RepeatMode.all => FaIcon(
          FontAwesomeIcons.repeat,
          size: 22,
          color: primary,
        ),
      RepeatMode.one => Icon(Icons.repeat_one, size: 28, color: primary),
    };
  }
}
