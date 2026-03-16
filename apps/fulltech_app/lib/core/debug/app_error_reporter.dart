import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

class AppErrorReporter {
  AppErrorReporter._();

  static final AppErrorReporter instance = AppErrorReporter._();

  /// Last captured error message (debug only UI can display this).
  final ValueNotifier<String?> lastErrorMessage = ValueNotifier<String?>(null);

  /// Last captured stack trace (debug only).
  final ValueNotifier<String?> lastErrorStack = ValueNotifier<String?>(null);

  void _setLastMessage(String? value) {
    // Avoid notifying listeners while Flutter is building/layout/paint.
    final binding = WidgetsBinding.instance;
    final phase = SchedulerBinding.instance.schedulerPhase;

    void apply() {
      if (lastErrorMessage.value == value) return;
      lastErrorMessage.value = value;
    }

    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks) {
      apply();
      return;
    }

    binding.addPostFrameCallback((_) => apply());
  }

  void clear() => _setLastMessage(null);

  void _setLastStack(String? value) {
    final binding = WidgetsBinding.instance;
    final phase = SchedulerBinding.instance.schedulerPhase;

    void apply() {
      if (lastErrorStack.value == value) return;
      lastErrorStack.value = value;
    }

    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks) {
      apply();
      return;
    }

    binding.addPostFrameCallback((_) => apply());
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
