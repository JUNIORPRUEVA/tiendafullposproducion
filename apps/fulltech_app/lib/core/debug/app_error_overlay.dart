import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_error_reporter.dart';

class AppErrorOverlay extends StatelessWidget {
  const AppErrorOverlay({super.key});

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
                    tooltip: 'Cerrar',
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
