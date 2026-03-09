import 'package:flutter/material.dart';

import '../debug/trace_log.dart';

class AppFeedback {
  static Future<void> showInfo(
    BuildContext context,
    String message, {
    BuildContext? fallbackContext,
    String scope = 'AppFeedback',
  }) {
    return _showMessage(
      context,
      message,
      fallbackContext: fallbackContext,
      scope: scope,
    );
  }

  static Future<void> showError(
    BuildContext context,
    String message, {
    BuildContext? fallbackContext,
    String scope = 'AppFeedback',
  }) {
    return _showMessage(
      context,
      message,
      fallbackContext: fallbackContext,
      scope: scope,
      isError: true,
    );
  }

  static Future<void> _showMessage(
    BuildContext context,
    String message, {
    BuildContext? fallbackContext,
    required String scope,
    bool isError = false,
  }) async {
    final seq = TraceLog.nextSeq();
    TraceLog.log(
      scope,
      'feedback requested message="$message" primaryMounted=${context.mounted} fallbackMounted=${fallbackContext?.mounted ?? false}',
      seq: seq,
    );

    final messenger =
        _resolveMessenger(context) ?? _resolveMessenger(fallbackContext);
    if (messenger != null) {
      TraceLog.log(scope, 'feedback via SnackBar', seq: seq);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: isError ? Colors.red.shade700 : null,
          ),
        );
      return;
    }

    final dialogContext =
        _resolveContext(fallbackContext) ?? _resolveContext(context);
    if (dialogContext == null) {
      TraceLog.log(
        scope,
        'feedback dropped: no valid context available',
        seq: seq,
      );
      return;
    }

    TraceLog.log(scope, 'feedback via AlertDialog fallback', seq: seq);
    await showDialog<void>(
      context: dialogContext,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        title: Text(isError ? 'Error' : 'Mensaje'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
  }

  static ScaffoldMessengerState? _resolveMessenger(BuildContext? context) {
    if (context == null || !context.mounted) return null;
    return ScaffoldMessenger.maybeOf(context);
  }

  static BuildContext? _resolveContext(BuildContext? context) {
    if (context == null || !context.mounted) return null;
    return context;
  }
}
