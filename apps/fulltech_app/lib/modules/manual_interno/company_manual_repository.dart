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
    try {
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
    } on ApiException {
      rethrow;
    } catch (e) {
      // Ensure UI always gets a contextual ApiException instead of a raw FormatException.
      throw ApiException(
        _enrichManualError(
          e.toString(),
          uri: Uri.parse(
            '${_dio.options.baseUrl}${ApiRoutes.companyManualEntries}',
          ),
          baseUrl: _dio.options.baseUrl,
        ),
      );
    }
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
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_seenKey());
      if (raw == null || raw.trim().isEmpty) return null;
      return DateTime.tryParse(raw);
    } catch (_) {
      // SharedPreferences can get corrupted on some desktop setups.
      // SeenAt is non-critical; ignore failures.
      return null;
    }
  }

  Future<void> markSeen(DateTime seenAt) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_seenKey(), seenAt.toIso8601String());
    } catch (_) {
      // Non-critical: manual can work without this.
    }
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
        final isInvalid = e.message.trim().startsWith(
          _invalidResponseMessage(action),
        );

        // Some adapters/proxies return empty bytes even when the server sent JSON,
        // or return bytes that need a different decoding path.
        // Retry with ResponseType.plain first (string payload), then ResponseType.stream
        // to force reading the raw byte stream.
        if (_looksLikeEmptyPayload(res.data) || isInvalid) {
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
            // Try reading as a stream as a stronger fallback.
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
                    options: _streamOptions(extra: extra),
                  )
                  .timeout(_timeout);

              final body = alt.data;
              if (body is ResponseBody) {
                final bytes = await _collectResponseBytes(body);
                final decoded = _decodeJsonFromBytes(bytes, action);
                return _requireMap(decoded, action);
              }
            } catch (_) {
              // Fall through to other retries / enriched error.
            }
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
            statusCode: res.statusCode,
            headers: res.headers.map,
            data: res.data,
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

    final candidates = <Uint8List>[bytes];

    // gzip
    if (_looksLikeGzip(bytes)) {
      try {
        candidates.add(Uint8List.fromList(GZipDecoder().decodeBytes(bytes)));
      } catch (_) {
        // ignore
      }
    }

    // zlib/deflate (sometimes proxies compress without proper headers)
    try {
      candidates.add(Uint8List.fromList(ZLibDecoder().decodeBytes(bytes)));
    } catch (_) {
      // ignore
    }

    Object? lastError;
    for (final payload in candidates) {
      // UTF-8 first (allow malformed so we can still show diagnostics)
      final decodedUtf8 = utf8.decode(payload, allowMalformed: true);
      final rawUtf8 = _stripBom(decodedUtf8).trim();
      if (rawUtf8.isNotEmpty) {
        try {
          return jsonDecode(rawUtf8);
        } on FormatException catch (e) {
          lastError = e;
        }
      }

      // If it looks like UTF-16, try that too.
      final decodedUtf16 = _tryDecodeUtf16(payload);
      if (decodedUtf16 != null) {
        final rawUtf16 = _stripBom(decodedUtf16).trim();
        if (rawUtf16.isNotEmpty) {
          try {
            return jsonDecode(rawUtf16);
          } on FormatException catch (e) {
            lastError = e;
          }
        }
      }

      // latin1 last-resort
      final decodedLatin1 = latin1.decode(payload);
      final rawLatin1 = _stripBom(decodedLatin1).trim();
      if (rawLatin1.isNotEmpty) {
        try {
          return jsonDecode(rawLatin1);
        } on FormatException catch (e) {
          lastError = e;
        }
      }
    }

    if (lastError is FormatException) {
      final preview = _peekTextPreview(bytes) ?? '';
      throw ApiException(
        _invalidResponseMessage(action) + _formatDecodeHint(preview, lastError),
      );
    }

    throw ApiException(_invalidResponseMessage(action));
  }

  String? _tryDecodeUtf16(Uint8List bytes) {
    if (bytes.length < 4) return null;
    // BOM-based detection
    final hasLeBom = bytes[0] == 0xFF && bytes[1] == 0xFE;
    final hasBeBom = bytes[0] == 0xFE && bytes[1] == 0xFF;

    // Heuristic: lots of NUL bytes in even/odd positions.
    int nulEven = 0;
    int nulOdd = 0;
    final sampleLen = bytes.length > 200 ? 200 : bytes.length;
    for (var i = 0; i < sampleLen; i++) {
      if (bytes[i] == 0x00) {
        if (i.isEven) {
          nulEven++;
        } else {
          nulOdd++;
        }
      }
    }
    final looksLe =
        hasLeBom || (nulOdd > (sampleLen / 10) && nulEven < (sampleLen / 50));
    final looksBe =
        hasBeBom || (nulEven > (sampleLen / 10) && nulOdd < (sampleLen / 50));
    if (!looksLe && !looksBe) return null;

    final start = (hasLeBom || hasBeBom) ? 2 : 0;
    final codeUnits = <int>[];
    for (var i = start; i + 1 < bytes.length; i += 2) {
      final unit = looksLe
          ? (bytes[i] | (bytes[i + 1] << 8))
          : ((bytes[i] << 8) | bytes[i + 1]);
      codeUnits.add(unit);
    }
    return String.fromCharCodes(codeUnits);
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
    int? statusCode,
    Map<String, List<String>>? headers,
    dynamic data,
  }) {
    final ct =
        headers?['content-type']?.firstOrNull ??
        headers?['Content-Type']?.firstOrNull;
    final cl =
        headers?['content-length']?.firstOrNull ??
        headers?['Content-Length']?.firstOrNull;
    final ce =
        headers?['content-encoding']?.firstOrNull ??
        headers?['Content-Encoding']?.firstOrNull;
    final rt = data == null ? 'null' : data.runtimeType.toString();

    String? hex;
    try {
      Uint8List? bytes;
      if (data is Uint8List) bytes = data;
      if (data is ByteBuffer) bytes = data.asUint8List();
      if (data is List<int>) bytes = Uint8List.fromList(data);
      if (bytes != null && bytes.isNotEmpty) {
        final take = bytes.length > 16 ? bytes.sublist(0, 16) : bytes;
        hex = take.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
      }
    } catch (_) {
      hex = null;
    }

    final preview = _peekTextPreview(data);

    String? len;
    try {
      if (data is Uint8List) len = data.length.toString();
      if (data is ByteBuffer) len = data.lengthInBytes.toString();
      if (data is List<int>) len = data.length.toString();
      if (data is String) len = data.length.toString();
    } catch (_) {
      len = null;
    }

    final meta = <String>[
      if (statusCode != null) 'Status: $statusCode',
      if (ct != null && ct.trim().isNotEmpty) 'Content-Type: $ct',
      if (cl != null && cl.trim().isNotEmpty) 'Content-Length: $cl',
      if (ce != null && ce.trim().isNotEmpty) 'Content-Encoding: $ce',
      'DataType: $rt',
      if (len != null) 'DataLen: $len',
      if (hex != null) 'FirstBytes(hex): $hex',
      if (preview != null && preview.trim().isNotEmpty)
        'Preview: "${preview.replaceAll(RegExp(r"\s+"), " ").trim()}"',
    ];

    return '$message\nEndpoint: ${uri.path}\nURI: $uri\nBaseURL: $baseUrl\n${meta.join('\n')}';
  }

  Options _streamOptions({Map<String, dynamic>? extra}) {
    return _options(extra: extra).copyWith(responseType: ResponseType.stream);
  }

  Future<Uint8List> _collectResponseBytes(ResponseBody body) async {
    final chunks = <int>[];
    await for (final chunk in body.stream) {
      chunks.addAll(chunk);
    }
    return Uint8List.fromList(chunks);
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
    // (We decode ourselves in _decodeResponseBody/_decodeJsonFromBytes.)
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
    // Prevent servers/CDNs from sending brotli/deflate that may not be decoded
    // consistently across desktop adapters.
    return Options(
      extra: {'skipLoader': true, ...?extra},
      headers: const {'Accept-Encoding': 'identity'},
    );
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
