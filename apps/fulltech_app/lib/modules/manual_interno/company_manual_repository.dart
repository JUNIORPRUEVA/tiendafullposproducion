import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';

import 'package:archive/archive.dart';
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
    const action = 'cargar el manual interno';
    Response<dynamic>? res;
    try {
      res = await _dio
          .get(
            path,
            queryParameters: query,
            options: _jsonOptions(extra: extra),
          )
          .timeout(_timeout);
      return _requireMap(res.data, action);
    } on ApiException catch (e) {
      // Some deployments serve the PWA and proxy the API under /api.
      // If the response looks like HTML (SPA shell), retry once toggling the /api prefix.
      if (res != null) {
        // Some adapters/proxies return empty bytes even when the server sent JSON.
        // Retry once with ResponseType.plain to get a reliable string payload.
        if (_looksLikeEmptyPayload(res.data)) {
          try {
            final alt = await _dio
                .getUri(
                  res.realUri.replace(
                    queryParameters: {
                      ...res.realUri.queryParameters,
                      ...?query?.map(
                        (k, v) => MapEntry(k, v?.toString() ?? ''),
                      ),
                    },
                  ),
                  options: _plainOptions(extra: extra),
                )
                .timeout(_timeout);

            final raw = (alt.data ?? '').toString();
            final decoded = jsonDecode(_stripBom(raw).trim());
            return _requireMap(decoded, action);
          } catch (_) {
            // Fall through to other retries / enriched error.
          }
        }

        final altUri = _toggleApiPrefix(res.realUri);
        if (altUri != null && _looksLikeHtmlResponse(res.data)) {
          try {
            final alt = await _dio
                .getUri(
                  altUri.replace(
                    queryParameters: {
                      ...altUri.queryParameters,
                      ...?query?.map(
                        (k, v) => MapEntry(k, v?.toString() ?? ''),
                      ),
                    },
                  ),
                  options: _jsonOptions(extra: extra),
                )
                .timeout(_timeout);
            return _requireMap(alt.data, action);
          } catch (_) {
            // Fall through to enriched error below.
          }
        }

        throw ApiException(
          _enrichManualError(
            e.message,
            uri: res.realUri,
            baseUrl: _dio.options.baseUrl,
          ),
        );
      }

      rethrow;
    } on FormatException {
      throw ApiException(_invalidResponseMessage(action));
    } on TypeError {
      throw ApiException(_invalidResponseMessage(action));
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
          .post(path, data: body, options: _jsonOptions())
          .timeout(_timeout);
      return _requireMap(res.data, 'guardar la entrada del manual interno');
    } on FormatException {
      throw ApiException(
        _invalidResponseMessage('guardar la entrada del manual interno'),
      );
    } on TypeError {
      throw ApiException(
        _invalidResponseMessage('guardar la entrada del manual interno'),
      );
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
          .patch(path, data: body, options: _jsonOptions())
          .timeout(_timeout);
      return _requireMap(res.data, 'actualizar la entrada del manual interno');
    } on FormatException {
      throw ApiException(
        _invalidResponseMessage('actualizar la entrada del manual interno'),
      );
    } on TypeError {
      throw ApiException(
        _invalidResponseMessage('actualizar la entrada del manual interno'),
      );
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

  Map<String, dynamic> _requireMap(dynamic data, String action) {
    final normalized = _decodeResponseBody(data, action);
    if (normalized is Map<String, dynamic>) {
      return normalized;
    }
    if (normalized is Map) {
      return normalized.cast<String, dynamic>();
    }
    throw ApiException(_invalidResponseMessage(action));
  }

  dynamic _decodeResponseBody(dynamic data, String action) {
    if (data == null) {
      throw ApiException(_invalidResponseMessage(action));
    }
    if (data is Map || data is List) {
      return data;
    }
    // Dio Web adapter can return a ByteBuffer for ResponseType.bytes.
    if (data is ByteBuffer) {
      return _decodeJsonFromBytes(data.asUint8List(), action);
    }
    if (data is Uint8List) {
      return _decodeJsonFromBytes(data, action);
    }
    if (data is List<int>) {
      return _decodeJsonFromBytes(Uint8List.fromList(data), action);
    }
    if (data is String) {
      try {
        final raw = _stripBom(data).trim();
        if (raw.isEmpty) {
          throw ApiException(_invalidResponseMessage(action));
        }
        return jsonDecode(raw);
      } on FormatException catch (e) {
        throw ApiException(
          _invalidResponseMessage(action) + _formatDecodeHint(data, e),
        );
      }
    }
    throw ApiException(_invalidResponseMessage(action));
  }

  dynamic _decodeJsonFromBytes(Uint8List bytes, String action) {
    if (bytes.isEmpty) {
      throw ApiException(_invalidResponseMessage(action));
    }

    Uint8List payload = bytes;
    if (_looksLikeGzip(payload)) {
      try {
        payload = Uint8List.fromList(GZipDecoder().decodeBytes(payload));
      } catch (_) {
        // If it's not actually valid gzip, continue with raw bytes.
        payload = bytes;
      }
    }

    String decoded;
    try {
      decoded = utf8.decode(payload);
    } on FormatException {
      // Some servers omit charset; fall back to latin1 to avoid throwing.
      decoded = latin1.decode(payload);
    }

    final raw = _stripBom(decoded).trim();
    if (raw.isEmpty) {
      throw ApiException(_invalidResponseMessage(action));
    }

    try {
      return jsonDecode(raw);
    } on FormatException catch (e) {
      throw ApiException(
        _invalidResponseMessage(action) + _formatDecodeHint(raw, e),
      );
    }
  }

  bool _looksLikeGzip(Uint8List bytes) {
    return bytes.length >= 2 && bytes[0] == 0x1F && bytes[1] == 0x8B;
  }

  String _formatDecodeHint(String raw, FormatException e) {
    final preview = raw.trimLeft();
    final shortPreview = preview.length > 80
        ? preview.substring(0, 80)
        : preview;
    final printable = shortPreview.replaceAll(RegExp(r'\s+'), ' ');

    final htmlHint = _looksLikeHtmlText(printable)
        ? '\nPista: parece HTML (no JSON). Revisa API_BASE_URL; si es PWA, configura proxy /api con API_UPSTREAM_URL.'
        : '';

    return '\nDetalle: ${e.message}\nInicio de respuesta: "$printable"$htmlHint';
  }

  bool _looksLikeHtmlResponse(dynamic data) {
    final preview = _peekTextPreview(data);
    if (preview == null) return false;
    return _looksLikeHtmlText(preview);
  }

  bool _looksLikeHtmlText(String text) {
    final t = text.trimLeft().toLowerCase();
    return t.startsWith('<!doctype') ||
        t.startsWith('<html') ||
        t.startsWith('<head') ||
        t.startsWith('<meta') ||
        t.startsWith('<script') ||
        t.startsWith('<body') ||
        t.contains('<html');
  }

  String? _peekTextPreview(dynamic data) {
    try {
      if (data is String) {
        return data.trimLeft();
      }
      if (data is ByteBuffer) {
        return _peekTextPreview(data.asUint8List());
      }
      if (data is Uint8List) {
        if (data.isEmpty) return null;
        final take = data.length > 256 ? data.sublist(0, 256) : data;
        try {
          return utf8.decode(take, allowMalformed: true).trimLeft();
        } catch (_) {
          return latin1.decode(take).trimLeft();
        }
      }
      if (data is List<int>) {
        return _peekTextPreview(Uint8List.fromList(data));
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Uri? _toggleApiPrefix(Uri uri) {
    // Toggle an '/api' prefix on the *first* path segment.
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return null;

    List<String> toggled;
    if (segments.first.toLowerCase() == 'api') {
      toggled = segments.sublist(1);
    } else {
      toggled = ['api', ...segments];
    }

    return uri.replace(pathSegments: toggled);
  }

  String _enrichManualError(
    String message, {
    required Uri uri,
    required String baseUrl,
  }) {
    return '$message\nEndpoint: ${uri.path}\nURI: $uri\nBaseURL: $baseUrl';
  }

  String _stripBom(String value) {
    if (value.startsWith('\uFEFF')) {
      return value.substring(1);
    }
    return value;
  }

  String _invalidResponseMessage(String action) {
    return 'El servidor devolvió una respuesta inválida al $action.';
  }

  Options _jsonOptions({Map<String, dynamic>? extra}) {
    // Use bytes to reliably handle gzip or mis-labeled encodings.
    return _options(extra: extra).copyWith(responseType: ResponseType.bytes);
  }

  Options _plainOptions({Map<String, dynamic>? extra}) {
    return _options(extra: extra).copyWith(responseType: ResponseType.plain);
  }

  bool _looksLikeEmptyPayload(dynamic data) {
    if (data == null) return true;
    if (data is Uint8List) return data.isEmpty;
    if (data is ByteBuffer) return data.lengthInBytes == 0;
    if (data is List<int>) return data.isEmpty;
    if (data is String) return data.trim().isEmpty;
    return false;
  }

  Options _options({Map<String, dynamic>? extra}) {
    return Options(extra: {'skipLoader': true, ...?extra});
  }

  String _extractMessage(DioException e, String fallback) {
    final data = e.response?.data;

    dynamic decoded;
    try {
      if (data is Map || data is List) {
        decoded = data;
      } else if (data is ByteBuffer) {
        decoded = _decodeJsonFromBytes(data.asUint8List(), 'procesar el error');
      } else if (data is Uint8List) {
        decoded = _decodeJsonFromBytes(data, 'procesar el error');
      } else if (data is List<int>) {
        decoded = _decodeJsonFromBytes(
          Uint8List.fromList(data),
          'procesar el error',
        );
      } else if (data is String) {
        final raw = _stripBom(data).trim();
        if (raw.isNotEmpty) decoded = jsonDecode(raw);
      }
    } catch (_) {
      decoded = null;
    }

    if (decoded is Map) {
      final message = decoded['message'];
      if (message is String && message.trim().isNotEmpty) return message.trim();
      if (message is List) {
        final first = message.whereType<String>().firstOrNull;
        if (first != null && first.trim().isNotEmpty) return first.trim();
      }
      final error = decoded['error'];
      if (error is String && error.trim().isNotEmpty) return error.trim();
    }

    final status = e.response?.statusCode;
    if (status == 401) {
      return 'No autorizado. Inicia sesión nuevamente.';
    }
    if (status == 403) {
      return 'No tienes permisos para ver el manual interno.';
    }

    return fallback;
  }
}

extension _FirstOrNullExt<T> on Iterable<T> {
  T? get firstOrNull {
    final it = iterator;
    if (!it.moveNext()) return null;
    return it.current;
  }
}
