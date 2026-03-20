import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_error_reporter.dart';

class AppErrorOverlay extends StatelessWidget {
  const AppErrorOverlay({super.key});

  Future<void> _showDetails(BuildContext context, String msg) async {
    final stack = AppErrorReporter.instance.lastErrorStack.value;
    final full = stack == null || stack.trim().isEmpty ? msg : '$msg\n\n$stack';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Error (debug)'),
          content: SizedBox(
            width: 720,
            child: SingleChildScrollView(
              child: SelectableText(full),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: full));
                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext);
              },
              child: const Text('Copiar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;

    return ValueListenableBuilder<String?>(
      valueListenable: AppErrorReporter.instance.lastErrorMessage,
      builder: (context, msg, _) {
        if (msg == null || msg.trim().isEmpty) return const SizedBox.shrink();

        return Positioned(
          left: 8,
          right: 8,
          top: MediaQuery.paddingOf(context).top + 8,
          child: Material(
            color: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: scheme.error.withValues(alpha: 0.35)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      msg,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: scheme.onErrorContainer),
                    ),
                  ),
                  IconButton(
                    onPressed: () => _showDetails(context, msg),
                    icon: Icon(Icons.bug_report, color: scheme.onErrorContainer),
                  ),
                  IconButton(
                    onPressed: AppErrorReporter.instance.clear,
                    icon: Icon(Icons.close, color: scheme.onErrorContainer),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
