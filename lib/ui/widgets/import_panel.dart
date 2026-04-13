import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/binary_service.dart';
import '../../services/download_service.dart';
import '../../services/library_service.dart';
import '../../services/media_ingest_service.dart';
import '../../services/plamus_paths.dart';

/// Shared import UI: URL field, pick files, drag-and-drop, and progress.
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

  /// Downloads a remote URL via yt-dlp into the library folder.
  Future<void> _downloadUrl() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Paste a valid link first.')),
      );
      return;
    }

    final bin = BinaryService.instance.lastResolution;
    if (bin == null || !bin.ytDlpAvailable) {
      final detail =
          bin != null ? bin.errors.join(' ') : 'Binary resolution did not run.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'yt-dlp is not available. $detail',
          ),
        ),
      );
      return;
    }

    final lib = context.read<LibraryService>();
    await _setBusy(true, p: 0, msg: 'Starting download…');
    try {
      final root = await PlamusPaths.musicLibraryDirectory();
      final out = await DownloadService.downloadUrlToMp3(
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (bin != null && bin.errors.isNotEmpty)
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
          decoration: const InputDecoration(
            labelText: 'Paste a link (YouTube, SoundCloud, Spotify page, etc.)',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _downloadUrl(),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            FilledButton.icon(
              onPressed: _busy ? null : _downloadUrl,
              icon: const Icon(Icons.download),
              label: const Text('Download audio'),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: _busy ? null : _pickFiles,
              icon: const Icon(Icons.folder_open),
              label: const Text('Browse files'),
            ),
          ],
        ),
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
        if (_busy || _status.isNotEmpty) ...[
          const SizedBox(height: 12),
          if (_busy) LinearProgressIndicator(value: _progress == 0 ? null : _progress),
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
