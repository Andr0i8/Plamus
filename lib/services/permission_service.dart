import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

/// Centralised Android runtime permission requests.
///
/// On Windows / Linux / macOS / iOS this class is a no-op so the rest of the
/// codebase can call it unconditionally. The actual Android permission set
/// changes per API level:
///
///   * **Android 13+ (API 33)** — `READ_MEDIA_AUDIO` + `POST_NOTIFICATIONS`.
///   * **Android 12 (API 32) and below** — `READ_EXTERNAL_STORAGE`.
///
/// `permission_handler` maps these enum values to the right manifest permission
/// at runtime.
class PermissionService {
  PermissionService._();

  /// Requests the minimum permissions Plamus needs at startup so the user is
  /// only ever shown a single dialog batch.
  ///
  /// Returns silently — failures are non-fatal because individual flows
  /// (Library scan, Import) re-request the specific permissions they need.
  static Future<void> requestStartupPermissions() async {
    if (!Platform.isAndroid) return;
    await [
      Permission.audio,
      Permission.notification,
      Permission.storage,
    ].request();
  }

  /// Returns true when the app may read user audio files for ingestion.
  static Future<bool> ensureAudioAccess() async {
    if (!Platform.isAndroid) return true;
    final audio = await Permission.audio.request();
    if (audio.isGranted || audio.isLimited) return true;
    // Pre-API-33 fallback (older devices ignore Permission.audio).
    final storage = await Permission.storage.request();
    return storage.isGranted || storage.isLimited;
  }

  /// Returns true when the app may post the persistent media notification.
  static Future<bool> ensureNotificationAccess() async {
    if (!Platform.isAndroid) return true;
    final result = await Permission.notification.request();
    return result.isGranted;
  }
}
