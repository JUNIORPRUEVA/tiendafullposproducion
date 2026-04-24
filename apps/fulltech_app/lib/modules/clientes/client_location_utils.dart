import 'package:dio/dio.dart';

class ClientLocationPreview {
  final double? latitude;
  final double? longitude;
  final String? resolvedUrl;

  const ClientLocationPreview({
    this.latitude,
    this.longitude,
    this.resolvedUrl,
  });

  bool get hasCoordinates => _isValidCoordinatePair(latitude, longitude);
}

bool _isValidCoordinatePair(double? latitude, double? longitude) {
  if (latitude == null || longitude == null) {
    return false;
  }

  return latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;
}

String normalizeClientLocationUrl(String? rawUrl) {
  final value = (rawUrl ?? '').trim();
  if (value.isEmpty) return '';

  final lower = value.toLowerCase();
  if (lower.startsWith('http://') ||
      lower.startsWith('https://') ||
      lower.startsWith('geo:')) {
    return value;
  }

  if (value.startsWith('://')) {
    return 'https$value';
  }

  if (value.startsWith('//')) {
    return 'https:$value';
  }

  if (lower.startsWith('maps.app.goo.gl') ||
      lower.startsWith('goo.gl/maps') ||
      lower.startsWith('google.com/maps') ||
      lower.startsWith('www.google.com/maps') ||
      lower.startsWith('maps.google.com')) {
    return 'https://$value';
  }

  return value;
}

ClientLocationPreview parseClientLocationPreview(String? rawUrl) {
  final normalized = normalizeClientLocationUrl(rawUrl);
  if (normalized.isEmpty) return const ClientLocationPreview();

  final decoded = Uri.decodeFull(normalized);
  final patterns = <RegExp>[
    RegExp(
      r'[?&]q=\+?(-?\d+(?:\.\d+)?),[\s+]*(-?\d+(?:\.\d+)?)',
      caseSensitive: false,
    ),
    RegExp(
      r'/maps/search/\+?(-?\d+(?:\.\d+)?),[\s+]*(-?\d+(?:\.\d+)?)',
      caseSensitive: false,
    ),
    RegExp(
      r'@\+?(-?\d+(?:\.\d+)?),[\s+]*(-?\d+(?:\.\d+)?)',
      caseSensitive: false,
    ),
    RegExp(r'!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)', caseSensitive: false),
    RegExp(r'\+?(-?\d+(?:\.\d+)?),[\s+]*(-?\d+(?:\.\d+)?)'),
  ];

  for (final pattern in patterns) {
    final match = pattern.firstMatch(decoded);
    if (match == null) continue;

    final latitude = double.tryParse(match.group(1) ?? '');
    final longitude = double.tryParse(match.group(2) ?? '');

    if (!_isValidCoordinatePair(latitude, longitude)) continue;

    return ClientLocationPreview(
      latitude: latitude,
      longitude: longitude,
      resolvedUrl: normalized,
    );
  }

  return ClientLocationPreview(resolvedUrl: normalized);
}

Future<ClientLocationPreview> resolveClientLocationPreview(
  String? rawUrl, {
  Dio? dio,
}) async {
  final direct = parseClientLocationPreview(rawUrl);
  if (direct.hasCoordinates || (direct.resolvedUrl ?? '').isEmpty) {
    return direct;
  }

  final uri = Uri.tryParse(direct.resolvedUrl!);
  if (uri == null) return direct;

  if (!(uri.host.contains('goo.gl') || uri.host.contains('google.com'))) {
    return direct;
  }

  final client = dio ?? Dio();
  try {
    final response = await client.getUri<String>(
      uri,
      options: Options(
        responseType: ResponseType.plain,
        receiveTimeout: const Duration(seconds: 8),
        sendTimeout: const Duration(seconds: 8),
        validateStatus: (status) => status != null && status < 400,
      ),
    );

    final finalUri = response.realUri.toString();
    final resolved = parseClientLocationPreview(finalUri);
    if (resolved.hasCoordinates) return resolved;

    final body = response.data ?? '';
    final bodyResolved = parseClientLocationPreview(body);
    if (bodyResolved.hasCoordinates) {
      return ClientLocationPreview(
        latitude: bodyResolved.latitude,
        longitude: bodyResolved.longitude,
        resolvedUrl: finalUri,
      );
    }

    return ClientLocationPreview(resolvedUrl: finalUri);
  } catch (_) {
    return direct;
  } finally {
    if (dio == null) {
      client.close(force: true);
    }
  }
}
