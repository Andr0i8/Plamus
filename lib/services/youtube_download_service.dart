import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'download_service.dart';

/// Pure-Dart YouTube audio downloader for Android (and any platform without
/// `yt-dlp`).
///
/// Resolves a video URL/ID to its highest-bitrate audio-only stream via
/// `youtube_explode_dart`, then streams the bytes to disk while reporting
/// progress in the same shape as [DownloadProgress] so [import_panel.dart]
/// can stay agnostic of the platform.
///
/// We keep the original audio container (`.m4a` or `.webm`) — `just_audio`
/// plays both natively on Android, so transcoding to MP3 would only add CPU
/// cost and battery drain without quality benefit. If the user wants MP3
/// specifically, a future ffmpeg pass can be added.
class YoutubeDownloadService {
  YoutubeDownloadService._();

  /// Hard cap so a stalled stream cannot leave the UI on "Starting…" forever.
  static const Duration timeout = Duration(minutes: 30);

  /// Downloads the audio track of [url] into [outputDirectory] and returns the
  /// path of the saved file.
  ///
  /// Throws [ArgumentError] if [url] cannot be parsed as a YouTube id/url,
  /// [TimeoutException] on stalled streams, or [StateError] if the manifest
  /// has no audio-only track (very rare).
  static Future<String> downloadAudio({
    required String url,
    required String outputDirectory,
    void Function(DownloadProgress p)? onProgress,
  }) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(url, 'url', 'URL must not be empty');
    }

    final outDir = Directory(outputDirectory);
    if (!await outDir.exists()) {
      await outDir.create(recursive: true);
    }

    final yt = YoutubeExplode();
    File? sink;
    try {
      onProgress?.call(
        const DownloadProgress(fraction: 0.02, message: 'Resolving video…'),
      );

      final video = await yt.videos.get(trimmed).timeout(timeout);
      final manifest = await yt.videos.streamsClient
          .getManifest(video.id)
          .timeout(timeout);
      final audio = manifest.audioOnly.withHighestBitrate();

      final ext = audio.container.name.toLowerCase();
      final safeTitle = _sanitizeFileName(video.title);
      final outPath = await _uniquePath(
        p.join(outputDirectory, '$safeTitle.$ext'),
      );

      onProgress?.call(
        DownloadProgress(
          fraction: 0.05,
          message: 'Downloading "${video.title}"…',
        ),
      );

      sink = File(outPath);
      final ioSink = sink.openWrite();
      final total = audio.size.totalBytes;
      var received = 0;

      try {
        final stream = yt.videos.streamsClient.get(audio);
        final completer = Completer<void>();
        StreamSubscription<List<int>>? sub;
        sub = stream.listen(
          (chunk) {
            received += chunk.length;
            ioSink.add(chunk);
            if (total > 0 && onProgress != null) {
              final frac = (received / total).clamp(0.0, 1.0);
              onProgress(
                DownloadProgress(
                  fraction: frac,
                  message: '${(frac * 100).toStringAsFixed(1)}%',
                ),
              );
            }
          },
          onError: (Object e, StackTrace st) {
            if (!completer.isCompleted) completer.completeError(e, st);
          },
          onDone: () {
            if (!completer.isCompleted) completer.complete();
          },
          cancelOnError: true,
        );

        try {
          await completer.future.timeout(timeout);
        } finally {
          await sub.cancel();
        }
      } finally {
        await ioSink.flush();
        await ioSink.close();
      }

      onProgress?.call(
        const DownloadProgress(fraction: 1.0, message: 'Download complete.'),
      );
      return outPath;
    } catch (e) {
      // Best-effort cleanup of a partial file so the library never indexes a
      // truncated download.
      if (sink != null && await sink.exists()) {
        try {
          await sink.delete();
        } catch (_) {}
      }
      rethrow;
    } finally {
      yt.close();
    }
  }

  static String _sanitizeFileName(String raw) {
    const bad = r'<>:"/\|?*';
    var s = raw;
    for (final c in bad.split('')) {
      s = s.replaceAll(c, '_');
    }
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (s.length > 120) s = s.substring(0, 120);
    return s.isEmpty ? 'track' : s;
  }

  static Future<String> _uniquePath(String path) async {
    if (!await File(path).exists()) return path;
    final dir = p.dirname(path);
    final base = p.basenameWithoutExtension(path);
    final ext = p.extension(path);
    for (var i = 1; i < 10000; i++) {
      final candidate = p.join(dir, '${base}_$i$ext');
      if (!await File(candidate).exists()) return candidate;
    }
    throw StateError('Could not allocate unique path near $path');
  }
}
