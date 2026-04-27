import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:provider/provider.dart';
// Both factories are imported so we can pick the right one at runtime.
// `package:sqflite/sqflite.dart` registers the Android/iOS native plugin and
// sets the default `databaseFactory` global; `sqflite_common_ffi` provides
// the desktop `databaseFactoryFfi` we assign on Windows / Linux / macOS.
import 'package:sqflite/sqflite.dart' as sqflite_native;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'database/database_helper.dart';
import 'services/audio_player_service.dart';
import 'services/binary_service.dart';
import 'services/library_service.dart';
import 'services/permission_service.dart';
import 'theme/app_theme.dart';
import 'ui/shell/mobile_shell.dart';
import 'ui/shell/plamus_shell.dart';
import 'ui/theme/theme_controller.dart';

/// Application entry: configures the per-platform audio + storage backends,
/// extracts bundled binaries (desktop only), and mounts the shell.
///
/// Platform matrix:
///   * **Windows** — `just_audio` has no first-party Windows plugin, so the
///     media_kit backend is registered via [JustAudioMediaKit.ensureInitialized].
///     SQLite is provided by `sqflite_common_ffi`. After changing audio
///     dependencies, do a full cold restart (see CLAUDE.md).
///   * **Android** — `just_audio` uses its native plugin and
///     [JustAudioBackground.init] wires the lock-screen / notification media
///     session. SQLite is provided by the `sqflite` plugin (auto-registered).
///   * **Linux / macOS / iOS** — supported in principle by the same code paths
///     but not exercised in this repo.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows) {
    JustAudioMediaKit.ensureInitialized(windows: true, linux: false);
    JustAudioMediaKit.title = 'Plamus';
  }

  if (Platform.isAndroid || Platform.isIOS) {
    // Background playback service: the foreground service shows the persistent
    // media notification and routes lock-screen / Bluetooth controls back to
    // the just_audio player. Channel ids must be unique to this app.
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.example.plamus.audio',
      androidNotificationChannelName: 'Plamus playback',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    );
  }

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  } else if (Platform.isAndroid || Platform.isIOS) {
    // Touching `databaseFactory` from `package:sqflite` ensures the native
    // plugin is registered before the first DB open — without this reference
    // the import could be tree-shaken away.
    // ignore: unnecessary_statements
    sqflite_native.databaseFactory;
  }

  await BinaryService.instance.ensureBinariesExtracted();

  if (Platform.isAndroid) {
    // Best-effort: the storage / notification permissions are also requested
    // lazily from the Import flow when needed, but kicking the dialog here
    // means first-launch users see the prompt before they even browse the UI.
    unawaited(PermissionService.requestStartupPermissions());
  }

  final audio = AudioPlayerService();
  await audio.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => LibraryService(DatabaseHelper.instance),
        ),
        ChangeNotifierProvider.value(value: audio),
        ChangeNotifierProvider(create: (_) => ThemeController()),
      ],
      child: const PlamusApp(),
    ),
  );
}

/// Root [MaterialApp] wired to [ThemeController] and Plamus themes.
///
/// The shell is chosen at runtime: a mobile-first [MobileShell] on Android
/// (BottomNavigationBar + expandable player) and the desktop [PlamusShell]
/// (sidebar + glass player bar) everywhere else.
class PlamusApp extends StatelessWidget {
  /// Creates the root widget.
  const PlamusApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeCtrl = context.watch<ThemeController>();
    return MaterialApp(
      title: 'Plamus',
      debugShowCheckedModeBanner: false,
      theme: PlamusTheme.light(),
      darkTheme: PlamusTheme.dark(),
      themeMode: themeCtrl.mode,
      home: Platform.isAndroid || Platform.isIOS
          ? const MobileShell()
          : const PlamusShell(),
    );
  }
}
