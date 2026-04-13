import 'dart:ui';

import 'package:flutter/material.dart' hide RepeatMode;
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';

import '../../models/repeat_mode.dart';
import '../../services/audio_player_service.dart';
import 'bouncy_icon_button.dart';

/// Bottom glass-style transport bar with blur, progress, and volume.
class GlassPlayerBar extends StatelessWidget {
  /// Height reserved for the bar (excluding safe area).
  const GlassPlayerBar({super.key});

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

    return Padding(
      padding: const EdgeInsets.all(16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            decoration: BoxDecoration(
              color: theme.brightness == Brightness.dark
                  ? Colors.black.withValues(alpha: 0.45)
                  : Colors.white.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: theme.dividerColor.withValues(alpha: 0.25),
                width: 1,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      track?.title ?? 'Nothing playing',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
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
              Expanded(
                flex: 5,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        BouncyIconButton(
                          tooltip: 'Previous',
                          icon: FontAwesomeIcons.backwardStep,
                          onPressed: () => audio.skipPrevious(),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              shape: const CircleBorder(),
                              padding: const EdgeInsets.all(14),
                              minimumSize: const Size(52, 52),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              backgroundColor: primary,
                            ),
                            onPressed: () async {
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
                              size: 20,
                              color: theme.colorScheme.onPrimary,
                            ),
                          ),
                        ),
                        BouncyIconButton(
                          tooltip: 'Next',
                          icon: FontAwesomeIcons.forwardStep,
                          onPressed: () => audio.skipNext(),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                          tooltip: _repeatTooltip(audio.repeatMode),
                          onPressed: () {
                            final next = switch (audio.repeatMode) {
                              RepeatMode.off => RepeatMode.all,
                              RepeatMode.all => RepeatMode.one,
                              RepeatMode.one => RepeatMode.off,
                            };
                            audio.setRepeatMode(next);
                          },
                          icon: _repeatModeIcon(audio.repeatMode, primary, theme),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Text(
                          _fmt(audio.position),
                          style: theme.textTheme.labelSmall,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Slider(
                            value: audio.progressFraction.clamp(0.0, 1.0),
                            onChanged: (v) {
                              final ms =
                                  (audio.duration.inMilliseconds * v).round();
                              audio.seek(Duration(milliseconds: ms));
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _fmt(audio.duration),
                          style: theme.textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    const Icon(FontAwesomeIcons.volumeLow, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Slider(
                        value: audio.volume,
                        onChanged: (v) => audio.setVolumeLinear(v),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
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

  Widget _repeatModeIcon(RepeatMode m, Color primary, ThemeData theme) {
    final base = theme.iconTheme.color ?? Colors.white;
    return switch (m) {
      RepeatMode.off => Icon(Icons.close, size: 22, color: base.withValues(alpha: 0.5)),
      RepeatMode.all => FaIcon(FontAwesomeIcons.repeat, size: 20, color: primary),
      RepeatMode.one => Icon(Icons.repeat_one, size: 24, color: primary),
    };
  }
}
