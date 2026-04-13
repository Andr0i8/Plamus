import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'database/database_helper.dart';
import 'services/audio_player_service.dart';
import 'services/binary_service.dart';
import 'services/library_service.dart';
import 'theme/app_theme.dart';
import 'ui/shell/plamus_shell.dart';
import 'ui/theme/theme_controller.dart';

/// Application entry: desktop SQLite FFI, binary extraction, audio session, UI.
///
/// **Windows audio:** `just_audio` does not ship a native Windows implementation.
/// [JustAudioMediaKit.ensureInitialized] registers the media_kit backend. After
/// changing audio dependencies, do a full cold restart (see README / user docs).
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Required on Windows or core `just_audio` hits MissingPluginException (no
  // first-party Windows plugin). Add `media_kit_libs_linux` + linux: true if
  // you target Linux.
  if (Platform.isWindows) {
    JustAudioMediaKit.ensureInitialized(windows: true, linux: false);
    JustAudioMediaKit.title = 'Plamus';
  }

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  await BinaryService.instance.ensureBinariesExtracted();

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
      home: const PlamusShell(),
    );
  }
}
