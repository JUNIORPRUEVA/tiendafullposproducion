import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';

import '../errors/api_exception.dart';

class AppErrorDetails {
  final int eventId;
  final DateTime capturedAt;
  final String message;
  final String stackTrace;
  final String? context;
  final String? endpointUrl;
  final String? method;
  final String? apiResponse;
  final String? technicalDetails;
  final String errorType;

  const AppErrorDetails({
    required this.eventId,
    required this.capturedAt,
    required this.message,
    required this.stackTrace,
    required this.errorType,
    this.context,
    this.endpointUrl,
    this.method,
    this.apiResponse,
    this.technicalDetails,
  });

  String toConsoleString() {
    final lines = <String>[
      '[AppError][$eventId] $message',
      'type: $errorType',
      if (context != null && context!.trim().isNotEmpty) 'context: $context',
      if (method != null && method!.trim().isNotEmpty) 'method: $method',
      if (endpointUrl != null && endpointUrl!.trim().isNotEmpty)
        'endpoint: $endpointUrl',
      if (technicalDetails != null && technicalDetails!.trim().isNotEmpty)
        'details: $technicalDetails',
      if (apiResponse != null && apiResponse!.trim().isNotEmpty)
        'apiResponse:\n$apiResponse',
      if (stackTrace.trim().isNotEmpty) 'stackTrace:\n$stackTrace',
    ];
    return lines.join('\n');
  }

  String toClipboardString() {
    final lines = <String>[
      'Mensaje: $message',
      'Tipo: $errorType',
      if (context != null && context!.trim().isNotEmpty) 'Contexto: $context',
      if (method != null && method!.trim().isNotEmpty) 'Metodo: $method',
      if (endpointUrl != null && endpointUrl!.trim().isNotEmpty)
        'Endpoint: $endpointUrl',
      if (technicalDetails != null && technicalDetails!.trim().isNotEmpty)
        'Detalle tecnico: $technicalDetails',
      if (apiResponse != null && apiResponse!.trim().isNotEmpty)
        'Respuesta API:\n$apiResponse',
      if (stackTrace.trim().isNotEmpty) 'Stack trace:\n$stackTrace',
    ];
    return lines.join('\n\n');
  }
}

class AppErrorReporter {
  AppErrorReporter._();

  static final AppErrorReporter instance = AppErrorReporter._();

  int _eventSeq = 0;

  final ValueNotifier<AppErrorDetails?> lastError =
      ValueNotifier<AppErrorDetails?>(null);

  final List<AppErrorDetails> _history = <AppErrorDetails>[];

  List<AppErrorDetails> get history => List.unmodifiable(_history);

  void _setNotifierValueAfterFrame<T>(ValueNotifier<T> notifier, T value) {
    final binding = WidgetsBinding.instance;

    void apply() {
      if (notifier.value == value) return;
      notifier.value = value;
    }

    binding.addPostFrameCallback((_) => apply());
    binding.scheduleFrame();
  }

  void _setLastError(AppErrorDetails? value) {
    _setNotifierValueAfterFrame<AppErrorDetails?>(lastError, value);
  }

  void clear() => _setLastError(null);

  void record(Object error, StackTrace stack, {String? context}) {
    final details = _buildDetails(error, stack, context: context);
    _log(details);
    _remember(details);
    _setLastError(details);
  }

  void _remember(AppErrorDetails details) {
    _history.insert(0, details);
    if (_history.length > 10) {
      _history.removeRange(10, _history.length);
    }
  }

  void _log(AppErrorDetails details) {
    debugPrint(details.toConsoleString());
  }

  AppErrorDetails _buildDetails(
    Object error,
    StackTrace stack, {
    String? context,
  }) {
    final stackText = stack.toString();
    final normalizedStack = _truncate(stackText, maxChars: 16000);
    final normalizedContext = _clean(context);
    final eventId = ++_eventSeq;

    if (error is ApiException) {
      return AppErrorDetails(
        eventId: eventId,
        capturedAt: DateTime.now(),
        message: error.message,
        stackTrace: normalizedStack,
        context: normalizedContext,
        endpointUrl: error.uri?.toString(),
        method: _clean(error.method),
        apiResponse: _clean(error.responseBody),
        technicalDetails: _clean(error.technicalDetails),
        errorType: error.runtimeType.toString(),
      );
    }

    if (error is DioException) {
      return AppErrorDetails(
        eventId: eventId,
        capturedAt: DateTime.now(),
        message: error.message?.trim().isNotEmpty == true
            ? error.message!.trim()
            : error.toString(),
        stackTrace: normalizedStack,
        context: normalizedContext,
        endpointUrl: error.requestOptions.uri.toString(),
        method: _clean(error.requestOptions.method.toUpperCase()),
        apiResponse: _clean(_stringifyApiResponse(error.response?.data)),
        technicalDetails: _clean(error.error?.toString()),
        errorType: error.runtimeType.toString(),
      );
    }

    return AppErrorDetails(
      eventId: eventId,
      capturedAt: DateTime.now(),
      message: error.toString(),
      stackTrace: normalizedStack,
      context: normalizedContext,
      errorType: error.runtimeType.toString(),
    );
  }

  void recordFlutterError(FlutterErrorDetails details) {
    final exception = details.exception;
    final stack = details.stack ?? StackTrace.current;
    record(exception, stack, context: 'FlutterError');
  }

  String? _clean(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  String _truncate(String value, {required int maxChars}) {
    if (value.length <= maxChars) return value;
    return '${value.substring(0, maxChars)}\n…';
  }

  String? _stringifyApiResponse(dynamic data) {
    if (data == null) return null;
    final raw = data is String ? data : data.toString();
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    return _truncate(trimmed, maxChars: 6000);
  }
}
