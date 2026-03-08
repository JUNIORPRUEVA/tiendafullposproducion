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
    return trimmed.endsWith('/') ? trimmed.substring(0, trimmed.length - 1) : trimmed;
  }

  ApiException _asApiException(Object error, {required String fallback}) {
    if (error is DioException) {
      final data = error.response?.data;
      final status = error.response?.statusCode;
      if (data is Map && data['message'] is String) {
        return ApiException((data['message'] as String).toString(), status);
      }
      if (data is String && data.trim().isNotEmpty) {
        return ApiException(data, status);
      }
      return ApiException(fallback, status);
    }
    return ApiException(fallback, null);
  }

  /// Sends a plain text WhatsApp message via Evolution API.
  ///
  /// NOTE: Evolution API endpoint paths may vary by version/config.
  /// This implementation targets the common v2 pattern:
  /// POST /message/sendText/{instanceName}
  /// Header: apikey: <globalApiKey>
  /// Body: { "number": "<E164>", "text": "..." }
  Future<void> sendTextMessage({
    required String toNumber,
    required String message,
  }) async {
    final settings = await _ref.read(companySettingsRepositoryProvider).getSettings();

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

    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        headers: {
          // Evolution Manager calls it "API Key Global". The common header is `apikey`.
          'apikey': apiKey,
          'content-type': 'application/json',
        },
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 30),
      ),
    );

    try {
      await dio.post(
        '/message/sendText/${Uri.encodeComponent(instance)}',
        data: {
          'number': toNumber.trim(),
          'text': message,
        },
      );
    } catch (e) {
      throw _asApiException(e, fallback: 'No se pudo enviar mensaje con Evolution API');
    }
  }
}
