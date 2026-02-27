import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_routes.dart';
import '../auth/auth_repository.dart';
import '../errors/api_exception.dart';
import 'company_settings_model.dart';

final companySettingsRepositoryProvider = Provider<CompanySettingsRepository>((
  ref,
) {
  return CompanySettingsRepository(ref.watch(dioProvider));
});

class CompanySettingsRepository {
  final Dio _dio;

  CompanySettingsRepository(this._dio);

  String _extractMessage(dynamic data, String fallback) {
    if (data is String && data.trim().isNotEmpty) return data;
    if (data is Map) {
      final message = data['message'];
      if (message is String && message.trim().isNotEmpty) return message;
      if (message is List && message.isNotEmpty) {
        final normalized = message
            .whereType<String>()
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList();
        if (normalized.isNotEmpty) return normalized.join(' | ');
      }
    }
    return fallback;
  }

  Future<CompanySettings> getSettings() async {
    try {
      final res = await _dio.get(ApiRoutes.settings);
      return CompanySettings.fromMap((res.data as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return CompanySettings.empty();
      }
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo cargar configuración'),
        e.response?.statusCode,
      );
    } catch (_) {
      return CompanySettings.empty();
    }
  }

  Future<void> saveSettings(CompanySettings settings) async {
    try {
      await _dio.patch(
        ApiRoutes.settings,
        data: {
          'companyName': settings.companyName,
          'rnc': settings.rnc,
          'phone': settings.phone,
          'address': settings.address,
          'logoBase64': settings.logoBase64,
          'openAiApiKey': settings.openAiApiKey,
        },
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        throw ApiException(
          'La API en nube aún no tiene /settings desplegado. Actualiza el backend para guardar configuración global.',
          e.response?.statusCode,
        );
      }
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo guardar configuración'),
        e.response?.statusCode,
      );
    }
  }
}
