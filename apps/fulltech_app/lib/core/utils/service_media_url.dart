import 'package:flutter/foundation.dart';

import '../api/env.dart';

String resolveServiceMediaUrl(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return '';

  final normalized = value.replaceAll('\\', '/');
  final uri = Uri.tryParse(normalized);
  final appBaseUrl = Env.appBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
  final apiBaseUrl = Env.apiBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');

  String joinBase(String baseUrl, String path) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    if (baseUrl.isEmpty) return normalizedPath;
    return '$baseUrl$normalizedPath';
  }

  String? extractUploadsPath(String candidate) {
    const marker = '/uploads/';
    final markerIndex = candidate.indexOf(marker);
    if (markerIndex >= 0) {
      return candidate.substring(markerIndex);
    }
    if (candidate.startsWith('uploads/')) return '/$candidate';
    if (candidate.startsWith('./uploads/')) return candidate.substring(1);
    return null;
  }

  if (uri != null && uri.hasScheme) {
    if (kIsWeb) {
      final uploadsPath = extractUploadsPath(normalized);
      if (uploadsPath != null && appBaseUrl.isNotEmpty) {
        return joinBase(appBaseUrl, uploadsPath);
      }
    }
    return uri.toString();
  }

  final uploadsPath = extractUploadsPath(normalized);
  if (uploadsPath != null) {
    return joinBase(appBaseUrl, uploadsPath);
  }

  return joinBase(
    apiBaseUrl,
    normalized.startsWith('/') ? normalized : '/$normalized',
  );
}
