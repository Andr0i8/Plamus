import 'dart:io';

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Resolved paths to external CLI tools used by Plamus.
///
/// [ytDlpPath] and [ffmpegPath] point under application support after
/// [BinaryService.ensureBinariesExtracted] runs. [errors] lists human-readable
/// problems (e.g. missing asset) without throwing from the initializer.
class BinaryResolution {
  /// Creates a resolution result.
  const BinaryResolution({
    required this.ytDlpPath,
    required this.ffmpegPath,
    required this.ytDlpAvailable,
    required this.ffmpegAvailable,
    this.errors = const [],
  });

  /// Absolute path where `yt-dlp.exe` should live (may be missing).
  final String ytDlpPath;

  /// Absolute path where `ffmpeg.exe` should live (may be missing).
  final String ffmpegPath;

  /// True when [ytDlpPath] exists and looks like a real executable (> 1 KiB).
  final bool ytDlpAvailable;

  /// True when [ffmpegPath] exists and looks like a real executable.
  final bool ffmpegAvailable;

  /// Non-fatal extraction or environment issues for UI messaging.
  final List<String> errors;
}

/// Extracts bundled `yt-dlp.exe` and `ffmpeg.exe` from Flutter assets into
/// the per-user application support directory (Windows: `%AppData%`-style).
///
/// Assets must be declared under `assets/bin/` in `pubspec.yaml`. If an asset
/// is absent (developer forgot to copy the EXE), the app still starts and
/// [BinaryResolution.errors] explains what is missing.
class BinaryService {
  BinaryService._();

  static final BinaryService instance = BinaryService._();

  static const String _assetYtDlp = 'assets/bin/yt-dlp.exe';
  static const String _assetFfmpeg = 'assets/bin/ffmpeg.exe';

  BinaryResolution? _cached;

  /// Last successful or attempted resolution (null until [ensureBinariesExtracted]).
  BinaryResolution? get lastResolution => _cached;

  /// Copies bundled binaries next to app data if needed and validates sizes.
  ///
  /// Safe to call on every launch: skips rewrite when the on-disk file already
  /// matches the embedded asset byte length.
  Future<BinaryResolution> ensureBinariesExtracted() async {
    final errors = <String>[];
    try {
      final support = await getApplicationSupportDirectory();
      final binDir = Directory(p.join(support.path, 'bin'));
      if (!await binDir.exists()) {
        await binDir.create(recursive: true);
      }

      final ytTarget = File(p.join(binDir.path, 'yt-dlp.exe'));
      final ffTarget = File(p.join(binDir.path, 'ffmpeg.exe'));

      await _materializeAssetExecutable(
        assetPath: _assetYtDlp,
        target: ytTarget,
        label: 'yt-dlp',
        errors: errors,
      );
      await _materializeAssetExecutable(
        assetPath: _assetFfmpeg,
        target: ffTarget,
        label: 'ffmpeg',
        errors: errors,
      );

      final ytOk = await _isPlausibleExecutable(ytTarget);
      final ffOk = await _isPlausibleExecutable(ffTarget);

      if (!ytOk) {
        errors.add(
          'yt-dlp.exe is missing or invalid. Add assets/bin/yt-dlp.exe and rebuild.',
        );
      }
      if (!ffOk) {
        errors.add(
          'ffmpeg.exe is missing or invalid. Add assets/bin/ffmpeg.exe and rebuild.',
        );
      }

      _cached = BinaryResolution(
        ytDlpPath: ytTarget.path,
        ffmpegPath: ffTarget.path,
        ytDlpAvailable: ytOk,
        ffmpegAvailable: ffOk,
        errors: List.unmodifiable(errors),
      );
      return _cached!;
    } catch (e, st) {
      errors.add('Binary extraction failed: $e');
      assert(() {
        // ignore: avoid_print
        print(st);
        return true;
      }());
      _cached = BinaryResolution(
        ytDlpPath: '',
        ffmpegPath: '',
        ytDlpAvailable: false,
        ffmpegAvailable: false,
        errors: List.unmodifiable(errors),
      );
      return _cached!;
    }
  }

  /// Writes [assetPath] to [target] when the asset exists and size differs.
  static Future<void> _materializeAssetExecutable({
    required String assetPath,
    required File target,
    required String label,
    required List<String> errors,
  }) async {
    try {
      final data = await rootBundle.load(assetPath);
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      const minExeBytes = 4096;
      if (bytes.length < minExeBytes) {
        errors.add(
          '$label: bundled asset at $assetPath is too small (${bytes.length} B) — '
          'replace with a real Windows build.',
        );
        return;
      }
      if (await target.exists() && await target.length() == bytes.length) {
        return;
      }
      await target.writeAsBytes(bytes, flush: true);
    } on FileSystemException catch (e) {
      errors.add(
        '$label: cannot write "${target.path}" (${e.message}). '
        'Check disk space and that Plamus may write to application support (AppData).',
      );
    } on FlutterError catch (e) {
      errors.add(
        '$label: could not load $assetPath (${e.message}). '
        'Ensure the file exists under assets/bin/ and flutter pub get was run.',
      );
    } catch (e) {
      errors.add('$label: unexpected error loading $assetPath: $e');
    }
  }

  /// True if file exists and is larger than a trivial placeholder.
  static Future<bool> _isPlausibleExecutable(File f) async {
    if (!await f.exists()) return false;
    final len = await f.length();
    return len > 4096;
  }
}
