import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

LatLng? parseLatLngFromText(String input) {
  final raw = input.trim();
  if (raw.isEmpty) return null;

  bool inRange(double lat, double lng) {
    if (lat.isNaN || lng.isNaN) return false;
    return lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180;
  }

  LatLng? fromPair(String? latRaw, String? lngRaw) {
    if (latRaw == null || lngRaw == null) return null;
    final lat = double.tryParse(latRaw);
    final lng = double.tryParse(lngRaw);
    if (lat == null || lng == null) return null;
    if (!inRange(lat, lng)) return null;
    return LatLng(lat, lng);
  }

  LatLng? firstPairMatch(String text, List<RegExp> patterns) {
    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      final parsed = fromPair(match?.group(1), match?.group(2));
      if (parsed != null) return parsed;
    }
    return null;
  }

  String normalizeCoordinateCandidate(String value) {
    var normalized = value.trim();
    final lower = normalized.toLowerCase();
    if (lower.startsWith('loc:') || lower.startsWith('geo:')) {
      normalized = normalized.substring(4).trim();
    }
    return normalized;
  }

  final decodedRaw = Uri.decodeFull(raw);

  // 1) Plain "lat,lng" anywhere in the text.
  final pair = RegExp(
    r'(-?\d{1,2}(?:\.\d+)?)\s*,\s*(-?\d{1,3}(?:\.\d+)?)',
  ).firstMatch(decodedRaw);
  final direct = fromPair(pair?.group(1), pair?.group(2));
  if (direct != null) return direct;

  final regexPatterns = <RegExp>[
    RegExp(r'@(-?\d{1,2}(?:\.\d+)?),\s*(-?\d{1,3}(?:\.\d+)?)(?:,|$)'),
    RegExp(r'center=(-?\d{1,2}(?:\.\d+)?),\s*(-?\d{1,3}(?:\.\d+)?)(?:&|$)'),
    RegExp(r'll=(-?\d{1,2}(?:\.\d+)?),\s*(-?\d{1,3}(?:\.\d+)?)(?:&|$)'),
    RegExp(r'!3d(-?\d{1,2}(?:\.\d+)?)!4d(-?\d{1,3}(?:\.\d+)?)'),
    RegExp(r'query=(-?\d{1,2}(?:\.\d+)?),\s*(-?\d{1,3}(?:\.\d+)?)(?:&|$)'),
    RegExp(
      r'destination=(-?\d{1,2}(?:\.\d+)?),\s*(-?\d{1,3}(?:\.\d+)?)(?:&|$)',
    ),
  ];
  final regexDirect = firstPairMatch(decodedRaw, regexPatterns);
  if (regexDirect != null) return regexDirect;

  // 2) Google Maps URLs commonly shared by WhatsApp:
  // - https://maps.google.com/?q=lat,lng
  // - https://www.google.com/maps/search/?api=1&query=lat,lng
  // - https://www.google.com/maps/@lat,lng,17z
  final url = decodedRaw;

  String? extractParam(String name) {
    final match = RegExp(
      '(?:\\?|&)' + RegExp.escape(name) + r'=([^&]+)',
    ).firstMatch(url);
    if (match == null) return null;
    final value = match.group(1) ?? '';
    return Uri.decodeComponent(value.replaceAll('+', ' '));
  }

  final q =
      extractParam('q') ??
      extractParam('query') ??
      extractParam('destination') ??
      extractParam('center') ??
      extractParam('ll');
  if (q != null) {
    final qPair = RegExp(
      r'(-?\d{1,2}(?:\.\d+)?)\s*,\s*(-?\d{1,3}(?:\.\d+)?)',
    ).firstMatch(normalizeCoordinateCandidate(q));
    final parsed = fromPair(qPair?.group(1), qPair?.group(2));
    if (parsed != null) return parsed;
  }

  final at = RegExp(
    r'@(-?\d{1,2}(?:\.\d+)?),\s*(-?\d{1,3}(?:\.\d+)?),',
  ).firstMatch(url);
  final fromAt = fromPair(at?.group(1), at?.group(2));
  if (fromAt != null) return fromAt;

  final uri = Uri.tryParse(url);
  if (uri != null) {
    for (final segment in uri.pathSegments) {
      final nested = firstPairMatch(Uri.decodeComponent(segment), [
        RegExp(r'(-?\d{1,2}(?:\.\d+)?)\s*,\s*(-?\d{1,3}(?:\.\d+)?)'),
      ]);
      if (nested != null) return nested;
    }

    for (final entry in uri.queryParameters.entries) {
      final value = normalizeCoordinateCandidate(
        Uri.decodeFull(entry.value).replaceAll('+', ' '),
      );
      if (value.isEmpty) continue;
      final nested = parseLatLngFromText(value);
      if (nested != null) return nested;
    }
  }

  // 3) geo:lat,lng
  final geo = RegExp(
    r'geo:(-?\d{1,2}(?:\.\d+)?),\s*(-?\d{1,3}(?:\.\d+)?)',
    caseSensitive: false,
  ).firstMatch(raw);
  final fromGeo = fromPair(geo?.group(1), geo?.group(2));
  if (fromGeo != null) return fromGeo;

  return null;
}

String buildGoogleMapsSearchUrl(LatLng point) {
  final lat = _round(point.latitude, 6);
  final lng = _round(point.longitude, 6);
  return 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
}

String formatLatLng(LatLng point) {
  final lat = _round(point.latitude, 6);
  final lng = _round(point.longitude, 6);
  return '$lat,$lng';
}

double _round(double value, int decimals) {
  final factor = math.pow(10, decimals).toDouble();
  return (value * factor).roundToDouble() / factor;
}
