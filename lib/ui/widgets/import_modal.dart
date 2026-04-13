import 'package:flutter/material.dart';

import 'import_panel.dart';

/// Shows the dedicated import modal (link paste, browse, drag-and-drop).
Future<void> showPlamusImportDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: const Text('Import music'),
        content: SizedBox(
          width: 560,
          height: 480,
          child: ImportPanel(
            onDone: () {
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}
