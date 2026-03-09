import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

class AppErrorReporter {
  AppErrorReporter._();

  static final AppErrorReporter instance = AppErrorReporter._();

  /// Last captured error message (debug only UI can display this).
  final ValueNotifier<String?> lastErrorMessage = ValueNotifier<String?>(null);

  void clear() => lastErrorMessage.value = null;

  void record(Object error, StackTrace stack, {String? context}) {
    final ctx = (context == null || context.trim().isEmpty)
        ? ''
        : '[$context] ';
    final message = '$ctx${error.toString()}';

    debugPrint('[AppError] $message');
    debugPrintStack(stackTrace: stack);

    // Keep it short so it can fit on screen.
    final truncated = message.length > 240
        ? '${message.substring(0, 240)}…'
        : message;
    lastErrorMessage.value = truncated;
  }

  void recordFlutterError(FlutterErrorDetails details) {
    final exception = details.exception;
    final stack = details.stack ?? StackTrace.current;
    record(exception, stack, context: 'FlutterError');
  }
}
