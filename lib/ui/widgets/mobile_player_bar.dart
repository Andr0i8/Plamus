import 'dart:ui';

import 'package:flutter/material.dart' hide RepeatMode;
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';

import '../../models/repeat_mode.dart';
import '../../services/audio_player_service.dart';
import '../screens/full_player_screen.dart';

/// Compact mini-player rendered above the [BottomNavigationBar] on mobile.
///
/// Mirrors the desktop [GlassPlayerBar] aesthetic (blur + glass tint) but is
/// touch-first: full width, large tap targets, and tapping anywhere on the
/// bar (other than the play button) opens the full-screen [FullPlayerScreen].
class MobilePlayerBar extends StatelessWidget {
  /// Creates the mini player.
  const MobilePlayerBar({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final audio = context.watch<AudioPlayerService>();
    final track = audio.currentTrack;
    final primary = theme.colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: track == null
                  ? null
                  : () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const FullPlayerScreen(),
                          fullscreenDialog: true,
                        ),
                      ),
              child: Container(
                decoration: BoxDecoration(
                  color: theme.brightness == Brightness.dark
                      ? Colors.black.withValues(alpha: 0.45)
                      : Colors.white.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: theme.dividerColor.withValues(alpha: 0.25),
                  ),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            FontAwesomeIcons.music,
                            color: primary,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                track?.title ?? 'Nothing playing',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                track == null ? '—' : track.displayArtistLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.textTheme.bodySmall?.color
                                      ?.withValues(alpha: 0.7),
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Previous',
                          iconSize: 26,
                          padding: const EdgeInsets.all(8),
                          constraints:
                              const BoxConstraints(minWidth: 48, minHeight: 48),
                          icon: const FaIcon(FontAwesomeIcons.backwardStep),
                          onPressed: track == null ? null : audio.skipPrevious,
                        ),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            shape: const CircleBorder(),
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(48, 48),
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
                            size: 16,
                            color: theme.colorScheme.onPrimary,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Next',
                          iconSize: 26,
                          padding: const EdgeInsets.all(8),
                          constraints:
                              const BoxConstraints(minWidth: 48, minHeight: 48),
                          icon: const FaIcon(FontAwesomeIcons.forwardStep),
                          onPressed: track == null ? null : audio.skipNext,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: audio.progressFraction.clamp(0.0, 1.0),
                      minHeight: 2,
                      backgroundColor: primary.withValues(alpha: 0.15),
                      valueColor: AlwaysStoppedAnimation<Color>(primary),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shared label/icon for the repeat-mode cycle button used by both desktop
/// and mobile player surfaces.
String repeatTooltipFor(RepeatMode m) {
  return switch (m) {
    RepeatMode.off => 'Repeat: off',
    RepeatMode.all => 'Repeat: all',
    RepeatMode.one => 'Repeat: one',
  };
}
