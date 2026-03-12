import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api/api_routes.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/errors/api_exception.dart';
import 'company_manual_models.dart';

final companyManualRepositoryProvider = Provider<CompanyManualRepository>((
  ref,
) {
  return CompanyManualRepository(ref, ref.watch(dioProvider));
});

final companyManualSummaryProvider = FutureProvider<CompanyManualSummary>((
  ref,
) {
  return ref.read(companyManualRepositoryProvider).loadSummary();
});

class CompanyManualRepository {
  CompanyManualRepository(this.ref, this._dio);

  static const Duration _timeout = Duration(seconds: 15);
  static const String _seenAtKeyPrefix = 'company_manual_seen_at';

  final Ref ref;
  final Dio _dio;

  Future<List<CompanyManualEntry>> listEntries({
    CompanyManualEntryKind? kind,
    CompanyManualAudience? audience,
    String? moduleKey,
    bool includeHidden = false,
  }) async {
    final data = await _getMap(
      ApiRoutes.companyManualEntries,
      query: {
        if (kind != null) 'kind': kind.apiValue,
        if (audience != null) 'audience': audience.apiValue,
        if (moduleKey != null && moduleKey.trim().isNotEmpty)
          'moduleKey': moduleKey.trim().toLowerCase(),
        if (includeHidden) 'includeHidden': 'true',
      },
    );

    final items = data['items'];
    if (items is! List) return const [];
    return items
        .whereType<Map>()
        .map((row) => CompanyManualEntry.fromMap(row.cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<CompanyManualEntry> getEntryById(String id) async {
    final data = await _getMap(ApiRoutes.companyManualEntryDetail(id));
    return CompanyManualEntry.fromMap(data);
  }

  Future<CompanyManualEntry> createEntry(CompanyManualEntry entry) async {
    final data = await _postMap(
      ApiRoutes.companyManualEntries,
      entry.toUpsertDto(),
    );
    return CompanyManualEntry.fromMap(data);
  }

  Future<CompanyManualEntry> updateEntry(CompanyManualEntry entry) async {
    final data = await _patchMap(
      ApiRoutes.companyManualEntryDetail(entry.id),
      entry.toUpsertDto(),
    );
    return CompanyManualEntry.fromMap(data);
  }

  Future<void> deleteEntry(String id) async {
    try {
      await _dio
          .delete(ApiRoutes.companyManualEntryDetail(id), options: _options())
          .timeout(_timeout);
    } on TimeoutException {
      throw ApiException(
        'La operación tardó demasiado al eliminar la entrada.',
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e, 'No se pudo eliminar la entrada'),
        e.response?.statusCode,
      );
    }
  }

  Future<CompanyManualSummary> loadSummary() async {
    final seenAt = await getSeenAt();
    final map = await _getMap(
      ApiRoutes.companyManualSummary,
      query: {if (seenAt != null) 'seenAt': seenAt.toIso8601String()},
      extra: const {'silent': true},
    );
    return CompanyManualSummary.fromMap(map);
  }

  Future<DateTime?> getSeenAt() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_seenKey());
    if (raw == null || raw.trim().isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  Future<void> markSeen(DateTime seenAt) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_seenKey(), seenAt.toIso8601String());
  }

  String _seenKey() {
    final userId = (ref.read(authStateProvider).user?.id ?? 'anon').trim();
    return '$_seenAtKeyPrefix:$userId';
  }

  Future<Map<String, dynamic>> _getMap(
    String path, {
    Map<String, dynamic>? query,
    Map<String, dynamic>? extra,
  }) async {
    try {
      final res = await _dio
          .get(
            path,
            queryParameters: query,
            options: _options(extra: extra),
          )
          .timeout(_timeout);
      if (res.data is Map<String, dynamic>) {
        return res.data as Map<String, dynamic>;
      }
      if (res.data is Map) {
        return (res.data as Map).cast<String, dynamic>();
      }
      throw ApiException('Respuesta inválida del servidor');
    } on TimeoutException {
      throw ApiException(
        'La operación tardó demasiado al cargar el manual interno.',
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e, 'No se pudo cargar el manual interno'),
        e.response?.statusCode,
      );
    }
  }

  Future<Map<String, dynamic>> _postMap(
    String path,
    Map<String, dynamic> body,
  ) async {
    try {
      final res = await _dio
          .post(path, data: body, options: _options())
          .timeout(_timeout);
      if (res.data is Map<String, dynamic>) {
        return res.data as Map<String, dynamic>;
      }
      if (res.data is Map) {
        return (res.data as Map).cast<String, dynamic>();
      }
      throw ApiException('Respuesta inválida del servidor');
    } on TimeoutException {
      throw ApiException('La operación tardó demasiado al guardar la entrada.');
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e, 'No se pudo guardar la entrada'),
        e.response?.statusCode,
      );
    }
  }

  Future<Map<String, dynamic>> _patchMap(
    String path,
    Map<String, dynamic> body,
  ) async {
    try {
      final res = await _dio
          .patch(path, data: body, options: _options())
          .timeout(_timeout);
      if (res.data is Map<String, dynamic>) {
        return res.data as Map<String, dynamic>;
      }
      if (res.data is Map) {
        return (res.data as Map).cast<String, dynamic>();
      }
      throw ApiException('Respuesta inválida del servidor');
    } on TimeoutException {
      throw ApiException(
        'La operación tardó demasiado al actualizar la entrada.',
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e, 'No se pudo actualizar la entrada'),
        e.response?.statusCode,
      );
    }
  }

  Options _options({Map<String, dynamic>? extra}) {
    return Options(extra: {'skipLoader': true, ...?extra});
  }

  String _extractMessage(DioException e, String fallback) {
    final data = e.response?.data;
    if (data is Map) {
      final message = data['message'];
      if (message is String && message.trim().isNotEmpty) return message;
      if (message is List && message.isNotEmpty && message.first is String) {
        return (message.first as String).trim();
      }
    }
    return fallback;
  }
}
