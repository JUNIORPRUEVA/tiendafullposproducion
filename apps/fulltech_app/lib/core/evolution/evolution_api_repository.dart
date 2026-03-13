import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  String? _extractErrorMessageFromData(dynamic data) {
    if (data == null) return null;
    if (data is String) {
      final trimmed = data.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    if (data is Map) {
      final candidates = [
        data['message'],
        data['error'],
        data['msg'],
        data['detail'],
        data['description'],
      ];
      for (final c in candidates) {
        if (c is String && c.trim().isNotEmpty) return c.trim();
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
    }
    return null;
  }

  ApiException _asApiException(Object error, {required String fallback}) {
    if (error is DioException) {
      final status = error.response?.statusCode;

      final msg = _extractErrorMessageFromData(error.response?.data);
      if (msg != null) return ApiException(msg, status);

      final suffix = status == null ? '' : ' (HTTP $status)';
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return ApiException('Tiempo de espera agotado$suffix', status);
        case DioExceptionType.connectionError:
          return ApiException('Error de conexión$suffix', status);
        default:
          break;
      }
      return ApiException('$fallback$suffix', status);
    }
    return ApiException(fallback, null);
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

    try {
      await dio.post(
        '/message/sendMedia/${Uri.encodeComponent(instance)}',
        data: {
          'number': number,
          'mediatype': 'document',
          'mimetype': 'application/pdf',
          if ((caption ?? '').trim().isNotEmpty)
            'caption': (caption ?? '').trim(),
          'media': mediaBase64,
          'fileName': fileName.trim(),
        },
      );
    } catch (e) {
      throw _asApiException(
        e,
        fallback: 'No se pudo enviar PDF con Evolution API',
      );
    }
  }
}
