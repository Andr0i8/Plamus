import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Centralized filesystem locations for music files and support data.
class PlamusPaths {
  PlamusPaths._();

  /// Ensures the on-disk music library folder exists and returns its path.
  ///
  /// Lives under application support so it is writable and user-specific.
  static Future<String> musicLibraryDirectory() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'music_library'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir.path;
  }
}
