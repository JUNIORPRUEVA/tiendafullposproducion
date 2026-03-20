import 'package:flutter/widgets.dart';

class AppErrorReporter {
  AppErrorReporter._();

  static final AppErrorReporter instance = AppErrorReporter._();

  /// Last captured error message (debug only UI can display this).
  final ValueNotifier<String?> lastErrorMessage = ValueNotifier<String?>(null);

  /// Last captured stack trace (debug only).
  final ValueNotifier<String?> lastErrorStack = ValueNotifier<String?>(null);

  void _setNotifierValueAfterFrame<T>(ValueNotifier<T> notifier, T value) {
    final binding = WidgetsBinding.instance;

    void apply() {
      if (notifier.value == value) return;
      notifier.value = value;
    }

    binding.addPostFrameCallback((_) => apply());
    binding.scheduleFrame();
  }

  void _setLastMessage(String? value) {
    _setNotifierValueAfterFrame<String?>(lastErrorMessage, value);
  }

  void clear() => _setLastMessage(null);

  void _setLastStack(String? value) {
    _setNotifierValueAfterFrame<String?>(lastErrorStack, value);
  }

  void record(Object error, StackTrace stack, {String? context}) {
    final ctx = (context == null || context.trim().isEmpty)
        ? ''
        : '[$context] ';
    final message = '$ctx${error.toString()}';

    debugPrint('[AppError] $message');
    debugPrintStack(stackTrace: stack);

    final stackText = stack.toString();
    const maxStackChars = 8000;
    _setLastStack(
      stackText.length > maxStackChars
          ? '${stackText.substring(0, maxStackChars)}\n…'
          : stackText,
    );

    // Keep it short so it can fit on screen.
    final truncated = message.length > 240
        ? '${message.substring(0, 240)}…'
        : message;
    _setLastMessage(truncated);
  }

  void recordFlutterError(FlutterErrorDetails details) {
    final exception = details.exception;
    final stack = details.stack ?? StackTrace.current;
    record(exception, stack, context: 'FlutterError');
  }
}
