import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'download_service.dart';

/// Pure-Dart YouTube audio downloader for Android (and any platform without
/// `yt-dlp`).
///
/// Resolves a video URL/ID to its highest-bitrate audio-only stream via
/// `youtube_explode_dart`, then fetches the audio bytes with **parallel HTTP
/// range requests** — the same trick `yt-dlp --concurrent-fragments` uses to
/// saturate a fast mobile connection. The on-disk file is assembled by writing
/// each chunk in order once all fetches complete.
///
/// Progress events are reported in the shape of [DownloadProgress] so
/// `import_panel.dart` stays platform-agnostic. We keep the original audio
/// container (`.m4a` or `.webm`) — `just_audio` plays both natively on Android,
/// so transcoding to MP3 would only add CPU cost and battery drain without
/// quality benefit.
class YoutubeDownloadService {
  YoutubeDownloadService._();

  /// Hard cap so a stalled stream cannot leave the UI on "Starting…" forever.
  static const Duration timeout = Duration(minutes: 30);

  /// Default number of parallel HTTP range requests. 8 is a sweet spot for
  /// modern mobile networks: enough parallelism to saturate the link without
  /// triggering YouTube's per-IP connection caps.
  static const int defaultParallelChunks = 8;

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
    int parallelChunks = defaultParallelChunks,
  }) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(url, 'url', 'URL must not be empty');
    }
    final clampedChunks = parallelChunks.clamp(1, 16);

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
      sink = File(outPath);

      onProgress?.call(
        DownloadProgress(
          fraction: 0.05,
          message: 'Downloading "${video.title}"…',
        ),
      );

      final total = audio.size.totalBytes;
      if (total > 0) {
        await _downloadParallel(
          streamUri: audio.url,
          totalBytes: total,
          outFile: sink,
          chunks: clampedChunks,
          onProgress: onProgress,
        );
      } else {
        // Manifest didn't expose a size — fall back to a single sequential
        // stream so the download still works.
        await _downloadSingleStream(
          yt: yt,
          info: audio,
          outFile: sink,
          totalBytes: total,
          onProgress: onProgress,
        );
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

  /// Splits [totalBytes] into [chunks] equal byte ranges, then:
  ///   1. Fetches chunk 0 alone as a probe.
  ///      - If it returns HTTP 206, ranges are supported — fire the remaining
  ///        chunks in parallel and reuse the probe's bytes as chunk 0.
  ///      - If it returns HTTP 200 (range header ignored by the CDN), the
  ///        server has streamed the full body to us already. We write that
  ///        body straight to disk and skip the parallel path. This avoids the
  ///        worst-case N×totalBytes bandwidth waste of letting all parallel
  ///        requests each drain the full response.
  ///   2. Reassembles the file with [RandomAccessFile.writeFrom] in chunk
  ///      order.
  static Future<void> _downloadParallel({
    required Uri streamUri,
    required int totalBytes,
    required File outFile,
    required int chunks,
    required void Function(DownloadProgress p)? onProgress,
  }) async {
    final ranges = <_ByteRange>[];
    final chunkSize = (totalBytes / chunks).ceil();
    for (var i = 0; i < chunks; i++) {
      final start = i * chunkSize;
      if (start >= totalBytes) break;
      final end = ((i + 1) * chunkSize - 1).clamp(0, totalBytes - 1);
      ranges.add(_ByteRange(i, start, end));
    }

    final buffers = List<Uint8List?>.filled(ranges.length, null);
    var totalReceived = 0;

    void reportProgress(int delta) {
      totalReceived += delta;
      if (onProgress == null) return;
      final frac = (totalReceived / totalBytes).clamp(0.0, 1.0);
      onProgress(
        DownloadProgress(
          fraction: frac,
          message: '${(frac * 100).toStringAsFixed(1)}%',
        ),
      );
    }

    final client = http.Client();
    Uint8List? fullBodyFromProbe;
    try {
      // Probe with chunk 0 first. If the CDN ignores Range and returns 200,
      // we capture the full body in one shot (the server sends it whether we
      // asked for it or not) and skip the parallel path entirely — avoiding
      // the worst-case N×totalBytes bandwidth waste of letting all parallel
      // requests each drain the full response.
      final probe = ranges.first;
      final probeResult = await _fetchRange(
        client: client,
        streamUri: streamUri,
        start: probe.start,
        end: probe.end,
        onChunkBytes: reportProgress,
      );
      if (probeResult.rangeIgnored) {
        fullBodyFromProbe = probeResult.body;
        // Skip parallel — we already have the entire file from the probe.
      } else {
        buffers[probe.index] = probeResult.body;

        // Probe confirmed 206 — fetch the remaining chunks in parallel.
        if (ranges.length > 1) {
          await Future.wait(
            ranges.skip(1).map(
                  (r) async {
                    final res = await _fetchRange(
                      client: client,
                      streamUri: streamUri,
                      start: r.start,
                      end: r.end,
                      onChunkBytes: reportProgress,
                    );
                    if (res.rangeIgnored) {
                      // CDN flipped to 200 mid-flight on a follow-up chunk
                      // (extremely unusual but treat it as a hard failure so
                      // we don't end up with a partial file).
                      throw const HttpException(
                        'CDN stopped honouring Range header partway through '
                        'a parallel download',
                      );
                    }
                    buffers[r.index] = res.body;
                  },
                ),
            eagerError: true,
          );
        }
      }
    } finally {
      client.close();
    }

    // CDN ignored Range — write the probe's full body directly. No need to
    // re-download via youtube_explode_dart.
    if (fullBodyFromProbe != null) {
      final raf = await outFile.open(mode: FileMode.write);
      try {
        await raf.writeFrom(fullBodyFromProbe);
      } finally {
        await raf.close();
      }
      return;
    }

    // Assemble the file by writing each chunk at its natural position.
    final raf = await outFile.open(mode: FileMode.write);
    try {
      for (final buf in buffers) {
        if (buf == null) {
          throw StateError('Internal error: chunk buffer missing');
        }
        await raf.writeFrom(buf);
      }
    } finally {
      await raf.close();
    }
  }

  /// Issues a single ranged GET.
  ///
  /// On HTTP 206: returns the requested byte range with `rangeIgnored: false`.
  ///
  /// On HTTP 200 (CDN ignores Range): returns the **entire** response body
  /// with `rangeIgnored: true`. Callers use this to skip the parallel path
  /// without wasting another full download.
  ///
  /// Throws on any other status.
  static Future<_RangeFetchResult> _fetchRange({
    required http.Client client,
    required Uri streamUri,
    required int start,
    required int end,
    required void Function(int n) onChunkBytes,
  }) async {
    final req = http.Request('GET', streamUri);
    req.headers['Range'] = 'bytes=$start-$end';
    // YouTube's CDN occasionally rejects requests without a UA.
    req.headers['User-Agent'] =
        'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

    final resp = await client.send(req).timeout(timeout);
    if (resp.statusCode != 200 && resp.statusCode != 206) {
      // Drain so the underlying connection can be reused / closed cleanly.
      await resp.stream.drain<void>().catchError((Object _) {});
      throw HttpException(
        'Range request failed (HTTP ${resp.statusCode}) for bytes=$start-$end',
        uri: streamUri,
      );
    }

    final rangeIgnored = resp.statusCode == 200;
    final builder = BytesBuilder(copy: false);
    await for (final chunk in resp.stream.timeout(timeout)) {
      builder.add(chunk);
      // Always credit bytes-received to progress, both for the 206 chunk path
      // and the 200 full-body fallback. The caller's progress callback
      // divides by `totalBytes` so it works for either: streaming the whole
      // body via 200 looks like a single big "chunk" advancing the bar to
      // ~100%, which is the user-visible behaviour we want.
      onChunkBytes(chunk.length);
    }
    return _RangeFetchResult(
      body: builder.takeBytes(),
      rangeIgnored: rangeIgnored,
    );
  }

  /// Sequential fallback used when the manifest has no size, or the CDN does
  /// not honour range requests. Uses youtube_explode_dart's stream client so
  /// throttled streams continue to work.
  static Future<void> _downloadSingleStream({
    required YoutubeExplode yt,
    required AudioOnlyStreamInfo info,
    required File outFile,
    required int totalBytes,
    required void Function(DownloadProgress p)? onProgress,
  }) async {
    final ioSink = outFile.openWrite();
    var received = 0;
    try {
      final stream = yt.videos.streamsClient.get(info);
      final completer = Completer<void>();
      StreamSubscription<List<int>>? sub;
      sub = stream.listen(
        (chunk) {
          received += chunk.length;
          ioSink.add(chunk);
          if (totalBytes > 0 && onProgress != null) {
            final frac = (received / totalBytes).clamp(0.0, 1.0);
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

class _ByteRange {
  const _ByteRange(this.index, this.start, this.end);
  final int index;
  final int start;
  final int end;
}

class _RangeFetchResult {
  const _RangeFetchResult({required this.body, required this.rangeIgnored});
  final Uint8List body;
  final bool rangeIgnored;
}
