import 'dart:io';

/// Windows shell helpers (reveal file in Explorer).
class WindowsShell {
  WindowsShell._();

  /// Opens Explorer with the file pre-selected (Windows only).
  ///
  /// No-ops on non-Windows platforms. Throws if [filePath] is empty or the
  /// file does not exist.
  static Future<void> showInFolder(String filePath) async {
    if (!Platform.isWindows) return;
    final normalized = filePath.replaceAll('/', '\\');
    final f = File(normalized);
    if (!await f.exists()) {
      throw FileSystemException('Cannot show missing file in folder', filePath);
    }
    final explorerArgs = <String>['/select,${f.path}'];
    final result = await Process.run('explorer', explorerArgs);
    if (result.exitCode != 0) {
      throw ProcessException(
        'explorer',
        explorerArgs,
        result.stderr.toString().trim(),
        result.exitCode,
      );
    }
  }
}
