import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/binary_service.dart';
import '../../services/download_service.dart';
import '../../services/library_service.dart';
import '../../services/media_ingest_service.dart';
import '../../services/permission_service.dart';
import '../../services/plamus_paths.dart';
import '../../services/youtube_download_service.dart';

/// Shared import UI: URL field, pick files, drag-and-drop, and progress.
///
/// The download path branches on platform:
///   * Windows / Linux / macOS — runs the bundled `yt-dlp.exe` via
///     [DownloadService] (rich format support, MP3 transcoding).
///   * Android — uses the pure-Dart [YoutubeDownloadService] which streams the
///     highest-bitrate audio-only track from YouTube directly to disk.
///
/// The drag-and-drop area is desktop-only because Android does not expose the
/// underlying OS drop target; mobile users use the file picker instead.
class ImportPanel extends StatefulWidget {
  /// Called after a successful import so parents can refresh lists.
  const ImportPanel({super.key, this.onDone});

  final VoidCallback? onDone;

  @override
  State<ImportPanel> createState() => _ImportPanelState();
}

class _ImportPanelState extends State<ImportPanel> {
  final _urlCtrl = TextEditingController();
  bool _busy = false;
  double _progress = 0;
  String _status = '';

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _setBusy(bool v, {double p = 0, String msg = ''}) async {
    if (!mounted) return;
    setState(() {
      _busy = v;
      _progress = p;
      _status = msg;
    });
  }

  /// Imports a local path (file picker or drop).
  Future<void> _ingestPath(String path) async {
    final lib = context.read<LibraryService>();
    await _setBusy(true, p: 0.05, msg: 'Importing…');
    try {
      final root = await PlamusPaths.musicLibraryDirectory();
      await MediaIngestService.ingestAndRegister(
        sourcePath: path,
        libraryDirectory: root,
        onLog: (m) {
          if (!mounted) return;
          setState(() => _status = m);
        },
      );
      await lib.refreshAll();
      widget.onDone?.call();
      await _setBusy(false, msg: 'Done.');
    } catch (e) {
      await _setBusy(false, msg: 'Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: $e')),
        );
      }
    }
  }

  /// Downloads a remote URL — Windows uses yt-dlp, Android uses youtube_explode.
  Future<void> _downloadUrl() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Paste a valid link first.')),
      );
      return;
    }

    final lib = context.read<LibraryService>();
    await _setBusy(true, p: 0, msg: 'Starting download…');
    try {
      final root = await PlamusPaths.musicLibraryDirectory();
      late String out;
      if (Platform.isAndroid || Platform.isIOS) {
        out = await YoutubeDownloadService.downloadAudio(
          url: url,
          outputDirectory: root,
          onProgress: (p) {
            if (!mounted) return;
            setState(() {
              _progress = p.fraction;
              _status = p.message;
            });
          },
        );
      } else {
        final bin = BinaryService.instance.lastResolution;
        if (bin == null || !bin.ytDlpAvailable) {
          final detail = bin != null
              ? bin.errors.join(' ')
              : 'Binary resolution did not run.';
          throw StateError('yt-dlp is not available. $detail');
        }
        out = await DownloadService.downloadUrlToMp3(
          url: url,
          outputDirectory: root,
          ytDlpExecutablePath: bin.ytDlpPath,
          onProgress: (p) {
            if (!mounted) return;
            setState(() {
              _progress = p.fraction;
              _status = p.message;
            });
          },
        );
      }
      await lib.registerTrackFile(out);
      await lib.refreshAll();
      _urlCtrl.clear();
      widget.onDone?.call();
      await _setBusy(false, p: 1, msg: 'Download complete.');
    } catch (e) {
      await _setBusy(false, msg: 'Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $e')),
        );
      }
    }
  }

  Future<void> _pickFiles() async {
    if (Platform.isAndroid) {
      final granted = await PermissionService.ensureAudioAccess();
      if (!granted) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Storage permission denied — open Settings to grant access.',
            ),
          ),
        );
        return;
      }
    }
    final res = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (res == null || res.files.isEmpty) return;
    for (final f in res.files) {
      final path = f.path ?? '';
      if (path.isEmpty) continue;
      await _ingestPath(path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bin = BinaryService.instance.lastResolution;
    final isMobile = Platform.isAndroid || Platform.isIOS;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!isMobile && bin != null && bin.errors.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Material(
              color: theme.colorScheme.errorContainer.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  bin.errors.join('\n'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ),
          ),
        TextField(
          controller: _urlCtrl,
          decoration: InputDecoration(
            labelText: isMobile
                ? 'Paste a YouTube link'
                : 'Paste a link (YouTube, SoundCloud, Spotify page, etc.)',
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (_) => _downloadUrl(),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: _busy ? null : _downloadUrl,
              icon: const Icon(Icons.download),
              label: const Text('Download audio'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _pickFiles,
              icon: const Icon(Icons.folder_open),
              label: const Text('Browse files'),
            ),
          ],
        ),
        if (!isMobile) ...[
          const SizedBox(height: 16),
          SizedBox(
            height: 220,
            child: DropTarget(
              onDragDone: (detail) async {
                if (_busy) return;
                for (final f in detail.files) {
                  final path = f.path;
                  if (path.isEmpty) continue;
                  await _ingestPath(path);
                }
              },
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.dividerColor.withValues(alpha: 0.4),
                  ),
                ),
                child: Center(
                  child: Text(
                    'Drag and drop audio or video files here',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.textTheme.bodyLarge?.color
                          ?.withValues(alpha: 0.75),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
        ],
        if (_busy || _status.isNotEmpty) ...[
          const SizedBox(height: 12),
          if (_busy)
            LinearProgressIndicator(value: _progress == 0 ? null : _progress),
          if (_status.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _status,
                style: theme.textTheme.bodySmall,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ],
    );
  }
}
