import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_kit.dart' as ffmpeg_kit;
import 'package:ffmpeg_kit_flutter_new_audio/return_code.dart' as ffmpeg_rc;
import 'package:path/path.dart' as p;

import '../database/database_helper.dart';
import '../models/track_model.dart';
import 'binary_service.dart';

/// Handles local file import: copy or transcode into the library folder.
///
/// Audio files are copied (or optionally left in place — here we normalize
/// into the app library directory). Video containers are passed through
/// `ffmpeg` to extract the audio track.
///
/// Cross-platform implementation:
///   * **Windows / Linux / macOS** — spawns the bundled `ffmpeg.exe` resolved
///     by [BinaryService] as a child process.
///   * **Android** — calls into the in-process `ffmpeg_kit_flutter_new_audio`
///     library instead. Same flags, same result, no executable to manage.
class MediaIngestService {
  MediaIngestService._();

  /// Extensions treated as audio-only (no ffmpeg transcode).
  static const Set<String> audioExtensions = {
    '.mp3',
    '.wav',
    '.flac',
    '.m4a',
    '.aac',
    '.ogg',
  };

  /// Extensions treated as video; audio is extracted to MP3 via ffmpeg.
  static const Set<String> videoExtensions = {
    '.mp4',
    '.mkv',
    '.webm',
    '.mov',
    '.avi',
  };

  /// Imports [sourcePath] into [libraryDirectory], returns final audio path.
  ///
  /// [onLog] receives ffmpeg / file copy status lines for progress UI.
  static Future<String> ingestLocalFile({
    required String sourcePath,
    required String libraryDirectory,
    void Function(String message)? onLog,
  }) async {
    final src = File(sourcePath);
    if (!await src.exists()) {
      throw FileSystemException('Source file does not exist', sourcePath);
    }

    final ext = p.extension(sourcePath).toLowerCase();
    final libDir = Directory(libraryDirectory);
    if (!await libDir.exists()) {
      await libDir.create(recursive: true);
    }

    if (audioExtensions.contains(ext)) {
      onLog?.call('Copying audio into library…');
      return _copyAudioToLibrary(src, libDir, ext);
    }

    if (videoExtensions.contains(ext)) {
      onLog?.call('Extracting audio from video with ffmpeg…');
      return _extractAudioWithFfmpeg(
        videoFile: src,
        libraryDir: libDir,
        onLog: onLog,
      );
    }

    throw UnsupportedError(
      'Unsupported file type "$ext". Use MP3, WAV, MP4, MKV, or other '
      'common audio/video containers.',
    );
  }

  /// Copies [src] into [libDir] with a unique file name if needed.
  static Future<String> _copyAudioToLibrary(
    File src,
    Directory libDir,
    String ext,
  ) async {
    final base = p.basenameWithoutExtension(src.path);
    var target = File(p.join(libDir.path, '$base$ext'));
    target = File(await _uniquePath(target.path));
    await src.copy(target.path);
    return target.path;
  }

  /// Runs ffmpeg to encode audio to high-quality MP3 (VBR q 0).
  ///
  /// Dispatches to the platform-appropriate backend (bundled exe on desktop,
  /// in-process libffmpeg on Android).
  static Future<String> _extractAudioWithFfmpeg({
    required File videoFile,
    required Directory libraryDir,
    void Function(String message)? onLog,
  }) async {
    final base = p.basenameWithoutExtension(videoFile.path);
    var outPath = p.join(libraryDir.path, '$base.mp3');
    outPath = await _uniquePath(outPath);

    if (Platform.isAndroid) {
      return _extractAudioWithFfmpegKit(
        videoFile: videoFile,
        outPath: outPath,
        onLog: onLog,
      );
    }
    return _extractAudioWithFfmpegBinary(
      videoFile: videoFile,
      outPath: outPath,
      onLog: onLog,
    );
  }

  /// Desktop path: spawn the bundled ffmpeg.exe as a child process.
  static Future<String> _extractAudioWithFfmpegBinary({
    required File videoFile,
    required String outPath,
    required void Function(String message)? onLog,
  }) async {
    final res = BinaryService.instance.lastResolution;
    if (res == null || !res.ffmpegAvailable) {
      throw StateError(
        'ffmpeg is not available. Add ffmpeg.exe to assets/bin/ and restart. '
        '${res?.errors.join(' ')}',
      );
    }

    final args = <String>[
      '-y',
      '-i',
      videoFile.path,
      '-vn',
      '-codec:a',
      'libmp3lame',
      '-q:a',
      '0',
      outPath,
    ];

    onLog?.call('ffmpeg ${args.join(' ')}');

    final result = await Process.run(
      res.ffmpegPath,
      args,
      runInShell: false,
      environment: {...Platform.environment},
    );

    if (result.exitCode != 0) {
      final err = result.stderr.toString().trim();
      final out = result.stdout.toString().trim();
      throw ProcessException(
        res.ffmpegPath,
        args,
        'ffmpeg failed: ${err.isNotEmpty ? err : out}',
        result.exitCode,
      );
    }

    final outFile = File(outPath);
    if (!await outFile.exists()) {
      throw StateError('ffmpeg reported success but output missing: $outPath');
    }
    return outPath;
  }

  /// Android path: call into ffmpeg_kit_flutter_new_audio's in-process FFmpeg.
  static Future<String> _extractAudioWithFfmpegKit({
    required File videoFile,
    required String outPath,
    required void Function(String message)? onLog,
  }) async {
    final args = <String>[
      '-y',
      '-i',
      videoFile.path,
      '-vn',
      '-codec:a',
      'libmp3lame',
      '-q:a',
      '0',
      outPath,
    ];
    onLog?.call('ffmpeg ${args.join(' ')}');

    final session = await ffmpeg_kit.FFmpegKit.executeWithArguments(args);
    final code = await session.getReturnCode();
    if (!ffmpeg_rc.ReturnCode.isSuccess(code)) {
      final logs = await session.getAllLogsAsString();
      throw StateError(
        'ffmpeg failed (rc=${code?.getValue()}). ${logs ?? ''}',
      );
    }

    final outFile = File(outPath);
    if (!await outFile.exists()) {
      throw StateError('ffmpeg reported success but output missing: $outPath');
    }
    return outPath;
  }

  /// If [path] exists, appends _1, _2, … before the extension.
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

  /// Probes duration with just_audio is preferred in UI layer; optional stub
  /// using ffmpeg ffprobe could be added later. [durationMs] may be 0 here.
  static Future<TrackModel> buildTrackRow({
    required String filePath,
    required String title,
    String artist = 'Unknown',
    int durationMs = 0,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    return TrackModel(
      title: title,
      artist: artist,
      filePath: filePath,
      durationMs: durationMs,
      dateAdded: now,
    );
  }

  /// Inserts a new track after ingest if [filePath] is not already registered.
  static Future<int> ingestAndRegister({
    required String sourcePath,
    required String libraryDirectory,
    void Function(String message)? onLog,
  }) async {
    final path = await ingestLocalFile(
      sourcePath: sourcePath,
      libraryDirectory: libraryDirectory,
      onLog: onLog,
    );

    final helper = DatabaseHelper.instance;
    final sqlite = await helper.database;
    final existing = await sqlite.query(
      'tracks',
      columns: ['id'],
      where: 'filePath = ?',
      whereArgs: [path],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      return existing.first['id'] as int;
    }

    final title = p.basenameWithoutExtension(path);
    final track = await buildTrackRow(filePath: path, title: title);
    return helper.insertTrack(track);
  }
}
