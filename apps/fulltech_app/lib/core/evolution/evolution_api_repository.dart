import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http_parser/http_parser.dart';

import '../company/company_settings_repository.dart';
import '../errors/api_exception.dart';

final evolutionApiRepositoryProvider = Provider<EvolutionApiRepository>((ref) {
  return EvolutionApiRepository(ref);
});

class EvolutionApiRepository {
  final Ref _ref;

  EvolutionApiRepository(this._ref);

  String _normalizeBaseUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    return trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
  }

  String _stringifyJsonPreview(Object? value, {int maxChars = 800}) {
    if (value == null) return '';
    try {
      final encoded = jsonEncode(value);
      if (encoded.length <= maxChars) return encoded;
      return '${encoded.substring(0, maxChars)}…';
    } catch (_) {
      return value.toString();
    }
  }

  String? _extractErrorMessageFromData(dynamic data) {
    if (data == null) return null;
    if (data is String) {
      final trimmed = data.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    if (data is Map) {
      String? pick(dynamic value) {
        if (value == null) return null;
        if (value is String) {
          final trimmed = value.trim();
          return trimmed.isEmpty ? null : trimmed;
        }
        if (value is Map) return _extractErrorMessageFromData(value);
        if (value is List && value.isNotEmpty) {
          final first = value.first;
          return pick(first);
        }
        return null;
      }

      final candidates = <dynamic>[
        data['message'],
        data['error'],
        data['msg'],
        data['detail'],
        data['description'],
        data['response'],
        data['data'],
        data['result'],
      ];
      for (final c in candidates) {
        final found = pick(c);
        if (found != null) return found;
      }

      // Some APIs respond with { errors: ["..."] } or { errors: [{message:""}] }
      final errors = data['errors'];
      if (errors is List && errors.isNotEmpty) {
        final first = errors.first;
        if (first is String && first.trim().isNotEmpty) return first.trim();
        if (first is Map && first['message'] is String) {
          final m = (first['message'] as String).trim();
          if (m.isNotEmpty) return m;
        }
      }

      final preview = _stringifyJsonPreview(data);
      if (preview.trim().isNotEmpty) return preview;
    }
    return null;
  }

  ApiException _asApiException(
    Object error, {
    required String fallback,
    String? context,
  }) {
    if (error is DioException) {
      final status = error.response?.statusCode;
      final uri = error.requestOptions.uri.toString();
      final endpoint = error.requestOptions.path;

      String requestCtx() {
        final parts = <String>[];
        if (endpoint.trim().isNotEmpty) parts.add('Endpoint: $endpoint');
        if (uri.trim().isNotEmpty) parts.add('URI: $uri');
        return parts.isEmpty ? '' : parts.join(' · ');
      }

      final msg = _extractErrorMessageFromData(error.response?.data);
      if (msg != null) {
        final suffix = status == null ? '' : ' (HTTP $status)';
        final withCode = msg.contains('HTTP ') ? msg : '$msg$suffix';
        final withContext = (context == null || context.trim().isEmpty)
            ? withCode
            : '$withCode · $context';

        // If the server returns a generic string, still append request/response
        // diagnostics to help troubleshooting (common with 500).
        final statusMessage = (error.response?.statusMessage ?? '').trim();
        final responsePreview = _stringifyJsonPreview(error.response?.data);
        final diagnostics = <String>[];
        final req = requestCtx();
        if (req.isNotEmpty) diagnostics.add(req);
        if (statusMessage.isNotEmpty) diagnostics.add(statusMessage);
        // Avoid duplicating the same text.
        if (responsePreview.trim().isNotEmpty && responsePreview != msg) {
          diagnostics.add('Response: $responsePreview');
        }

        // Only append diagnostics when they add value.
        final diagText = diagnostics.isEmpty
            ? ''
            : ' · ${diagnostics.join(' · ')}';
        return ApiException('$withContext$diagText', status);
      }

      final statusMessage = (error.response?.statusMessage ?? '').trim();
      final responsePreview = _stringifyJsonPreview(error.response?.data);
      final hasResponsePreview = responsePreview.trim().isNotEmpty;
      final diagnostic = <String>[];
      final req = requestCtx();
      if (req.isNotEmpty) diagnostic.add(req);
      if (statusMessage.isNotEmpty) diagnostic.add(statusMessage);
      if (hasResponsePreview) diagnostic.add('Response: $responsePreview');

      final suffix = status == null ? '' : ' (HTTP $status)';
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return ApiException(
            'Tiempo de espera agotado$suffix${context == null ? '' : ' · $context'}',
            status,
          );
        case DioExceptionType.connectionError:
          return ApiException(
            'Error de conexión$suffix${context == null ? '' : ' · $context'}',
            status,
          );
        default:
          break;
      }

      final diagText = diagnostic.isEmpty ? '' : ' · ${diagnostic.join(' · ')}';
      return ApiException(
        '$fallback$suffix${context == null ? '' : ' · $context'}$diagText',
        status,
      );
    }
    return ApiException(
      '$fallback${context == null ? '' : ' · $context'}',
      null,
    );
  }

  /// Tries to normalize a human-entered phone to Evolution/WhatsApp `number`.
  ///
  /// Supports common user inputs:
  /// - `+1 (829) 555-1234`
  /// - `829-555-1234`
  /// - `wa.me/18295551234`
  /// - JIDs like `18295551234@c.us` / `18295551234@s.whatsapp.net`
  ///
  /// Returns digits-only E164 (e.g. `1829XXXXXXX`).
  String normalizeWhatsAppNumber(String raw) {
    var input = raw.trim();
    if (input.isEmpty) return '';

    // Extract from wa.me links.
    final waMeMatch = RegExp(
      r'wa\.me/([0-9]+)',
      caseSensitive: false,
    ).firstMatch(input);
    if (waMeMatch != null) {
      input = waMeMatch.group(1) ?? input;
    }

    // Strip WhatsApp JID suffix.
    input = input.replaceAll(
      RegExp(r'(@c\.us|@s\.whatsapp\.net)$', caseSensitive: false),
      '',
    );

    // Keep digits only.
    var digits = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return '';

    // Handle international prefix 00...
    if (digits.startsWith('00')) {
      digits = digits.replaceFirst(RegExp(r'^00+'), '');
      if (digits.isEmpty) return '';
    }

    // Dominican Republic (NANP): local mobile numbers are commonly stored as 10 digits
    // starting with 809/829/849.
    final isDominicanLocal =
        digits.length == 10 && RegExp(r'^(809|829|849)').hasMatch(digits);
    if (isDominicanLocal) return '1$digits';

    // If already NANP E164 with country code 1.
    if (digits.length == 11 && digits.startsWith('1')) return digits;

    return digits;
  }

  Dio _buildDio({required String baseUrl, required String apiKey}) {
    return Dio(
      BaseOptions(
        baseUrl: baseUrl,
        headers: {
          // Evolution Manager calls it "API Key Global". The common header is `apikey`.
          'apikey': apiKey,
          'content-type': 'application/json',
        },
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 60),
      ),
    );
  }

  /// Sends a plain text WhatsApp message via Evolution API.
  ///
  /// NOTE: Evolution API endpoint paths may vary by version/config.
  /// This implementation targets the common v2 pattern:
  /// POST `/message/sendText/{instanceName}`
  /// Header: `apikey: <globalApiKey>`
  /// Body: `{ "number": "<E164>", "text": "..." }`
  Future<void> sendTextMessage({
    required String toNumber,
    required String message,
  }) async {
    final settings = await _ref
        .read(companySettingsRepositoryProvider)
        .getSettings();

    final baseUrl = _normalizeBaseUrl(settings.evolutionApiBaseUrl);
    final instance = settings.evolutionApiInstanceName.trim();
    final apiKey = settings.evolutionApiApiKey.trim();

    if (baseUrl.isEmpty) {
      throw ApiException(
        'Evolution API: falta Base URL en Configuración.',
        null,
      );
    }
    if (instance.isEmpty) {
      throw ApiException(
        'Evolution API: falta Instance name en Configuración.',
        null,
      );
    }
    if (apiKey.isEmpty) {
      throw ApiException(
        'Evolution API: falta API Key en Configuración.',
        null,
      );
    }

    final dio = _buildDio(baseUrl: baseUrl, apiKey: apiKey);

    final number = normalizeWhatsAppNumber(toNumber);
    if (number.isEmpty) {
      throw ApiException('Número de WhatsApp inválido.', null);
    }

    try {
      await dio.post(
        '/message/sendText/${Uri.encodeComponent(instance)}',
        data: {'number': number, 'text': message},
      );
    } catch (e) {
      throw _asApiException(
        e,
        fallback: 'No se pudo enviar mensaje con Evolution API',
      );
    }
  }

  /// Sends a PDF document via Evolution API.
  ///
  /// Target endpoint (common v2 pattern):
  /// POST `/message/sendMedia/{instanceName}`
  /// Header: `apikey: <globalApiKey>`
  ///
  /// Body keys vary across versions; this implementation uses the common:
  /// `{ number, mediatype: 'document', mimetype: 'application/pdf', caption, media: <base64>, fileName }`
  Future<void> sendPdfDocument({
    required String toNumber,
    required Uint8List bytes,
    required String fileName,
    String? caption,
    CancelToken? cancelToken,
  }) async {
    final settings = await _ref
        .read(companySettingsRepositoryProvider)
        .getSettings();

    final baseUrl = _normalizeBaseUrl(settings.evolutionApiBaseUrl);
    final instance = settings.evolutionApiInstanceName.trim();
    final apiKey = settings.evolutionApiApiKey.trim();

    if (baseUrl.isEmpty) {
      throw ApiException(
        'Evolution API: falta Base URL en Configuración.',
        null,
      );
    }
    if (instance.isEmpty) {
      throw ApiException(
        'Evolution API: falta Instance name en Configuración.',
        null,
      );
    }
    if (apiKey.isEmpty) {
      throw ApiException(
        'Evolution API: falta API Key en Configuración.',
        null,
      );
    }

    final number = normalizeWhatsAppNumber(toNumber);
    if (number.isEmpty) {
      throw ApiException('Número de WhatsApp inválido.', null);
    }
    if (bytes.isEmpty) {
      throw ApiException('El PDF está vacío y no se puede enviar.', null);
    }

    final dio = _buildDio(baseUrl: baseUrl, apiKey: apiKey);
    final mediaBase64 = base64Encode(bytes);
    final trimmedCaption = (caption ?? '').trim();
    final safeFileName = fileName.trim().isEmpty
        ? 'cotizacion.pdf'
        : fileName.trim();

    final endpoint = '/message/sendMedia/${Uri.encodeComponent(instance)}';

    // Evolution's documented payload typically expects digits-only E164.
    // Some deployments accept JIDs, but others crash with 500; keep it safe.
    final numbersToTry = <String>[number];

    final multipartOptions = Options(contentType: 'multipart/form-data');
    final multipartFieldNames = <String>['media', 'file', 'document'];

    MultipartFile pdfFile() => MultipartFile.fromBytes(
      bytes,
      filename: safeFileName,
      contentType: MediaType('application', 'pdf'),
    );

    Iterable<({String label, Object data, Options? options})>
    buildAttempts() sync* {
      // Prioritize documented/nested + simplest flat payloads.
      for (final n in numbersToTry) {
        yield (
          label: 'nested:mediaMessage:$n',
          data: {
            'number': n,
            if (trimmedCaption.isNotEmpty) 'caption': trimmedCaption,
            'mediaMessage': {
              'mediatype': 'document',
              'mimetype': 'application/pdf',
              if (trimmedCaption.isNotEmpty) 'caption': trimmedCaption,
              'media': mediaBase64,
              'fileName': safeFileName,
            },
          },
          options: null,
        );

        yield (
          label: 'flat:media+fileName:$n',
          data: {
            'number': n,
            'mediatype': 'document',
            'mimetype': 'application/pdf',
            if (trimmedCaption.isNotEmpty) 'caption': trimmedCaption,
            'media': mediaBase64,
            'fileName': safeFileName,
          },
          options: null,
        );
      }

      // Multipart minimal (fast to test; avoids extra keys that sometimes crash servers).
      for (final fileField in multipartFieldNames) {
        yield (
          label: 'multipart:min:$fileField',
          data: FormData.fromMap({
            'number': number,
            if (trimmedCaption.isNotEmpty) 'caption': trimmedCaption,
            fileField: pdfFile(),
          }),
          options: multipartOptions,
        );
      }

      // One "full" multipart variant as a last resort.
      yield (
        label: 'multipart:full:media:fileName:mimetype:mediatype',
        data: FormData.fromMap({
          'number': number,
          if (trimmedCaption.isNotEmpty) 'caption': trimmedCaption,
          'mediatype': 'document',
          'mimetype': 'application/pdf',
          'fileName': safeFileName,
          'media': pdfFile(),
        }),
        options: multipartOptions,
      );
    }

    final token = cancelToken ?? CancelToken();
    final stopwatch = Stopwatch()..start();
    Object? lastError;
    String? lastAttempt;
    var attemptsTried = 0;
    var serverErrors = 0;

    for (final attempt in buildAttempts()) {
      if (token.isCancelled) break;
      if (attemptsTried >= 12) break;
      if (stopwatch.elapsed > const Duration(seconds: 20)) break;
      attemptsTried++;
      try {
        await dio.post(
          endpoint,
          data: attempt.data,
          options: attempt.options,
          cancelToken: token,
        );
        return;
      } catch (e) {
        lastError = e;
        lastAttempt = attempt.label;

        if (e is DioException) {
          final status = e.response?.statusCode;

          if (status != null && status >= 500) {
            serverErrors++;
            // Avoid long spinner loops if the server keeps crashing.
            if (serverErrors >= 2) break;
          }

          // Do not retry on auth/config issues.
          if (status == 401 || status == 403) break;

          // Retry on common schema mismatches.
          final retryable =
              status == null ||
              status == 400 ||
              status == 404 ||
              status == 415 ||
              status == 422 ||
              status >= 500;
          if (retryable) continue;
        }

        break;
      }
    }

    throw _asApiException(
      lastError ?? Exception('Unknown error'),
      fallback: 'No se pudo enviar PDF con Evolution API',
      context: lastAttempt == null ? null : 'Payload: $lastAttempt',
    );
  }
}
