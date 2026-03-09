import 'dart:async';

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

final companySettingsProvider = FutureProvider<CompanySettings>((ref) async {
  return ref.watch(companySettingsRepositoryProvider).getSettings();
});

class CompanySettingsRepository {
  final Dio _dio;
  static const Duration _settingsTimeout = Duration(seconds: 20);

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
      final res = await _dio
          .get(
            ApiRoutes.settings,
            options: Options(extra: const {'skipLoader': true}),
          )
          .timeout(_settingsTimeout);
      return CompanySettings.fromMap((res.data as Map).cast<String, dynamic>());
    } on TimeoutException {
      throw ApiException(
        'La configuración tardó demasiado en cargar. Inténtalo de nuevo.',
      );
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
      await _dio
          .patch(
            ApiRoutes.settings,
            options: Options(extra: const {'skipLoader': true}),
            data: {
              'companyName': settings.companyName,
              'rnc': settings.rnc,
              'phone': settings.phone,
              'address': settings.address,
              'legalRepresentativeName': settings.legalRepresentativeName,
              'legalRepresentativeCedula': settings.legalRepresentativeCedula,
              'legalRepresentativeRole': settings.legalRepresentativeRole,
              'legalRepresentativeNationality':
                  settings.legalRepresentativeNationality,
              'legalRepresentativeCivilStatus':
                  settings.legalRepresentativeCivilStatus,
              'logoBase64': settings.logoBase64,
              'openAiApiKey': settings.openAiApiKey,
              'evolutionApiBaseUrl': settings.evolutionApiBaseUrl,
              'evolutionApiInstanceName': settings.evolutionApiInstanceName,
              'evolutionApiApiKey': settings.evolutionApiApiKey,
            },
          )
          .timeout(_settingsTimeout);
    } on TimeoutException {
      throw ApiException(
        'Guardar la configuración tardó demasiado. El backend no respondió a tiempo.',
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
