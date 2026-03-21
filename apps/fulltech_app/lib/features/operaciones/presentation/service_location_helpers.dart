import 'package:latlong2/latlong.dart';

import '../../../core/utils/geo_utils.dart';

class ServiceLocationInfo {
  final String label;
  final Uri? mapsUri;

  const ServiceLocationInfo({required this.label, required this.mapsUri});

  bool get canOpenMaps => mapsUri != null;
}

ServiceLocationInfo buildServiceLocationInfo({
  required String addressOrText,
  String? mapsUrl,
  LatLng? latLng,
}) {
  final address = addressOrText.trim();
  final maps = (mapsUrl ?? '').trim();

  String? extractGpsTextFromSnapshot(String text) {
    for (final line in text.split('\n')) {
      final value = line.trim();
      if (value.isEmpty) continue;
      if (value.toLowerCase().startsWith('gps:')) {
        final gpsValue = value.substring(4).trim();
        if (gpsValue.isNotEmpty) return gpsValue;
      }
    }
    return null;
  }

  String bestLabelFromText(String text) {
    String? gps;
    String? maps;
    for (final line in text.split('\n')) {
      final v = line.trim();
      if (v.isEmpty) continue;

      final lower = v.toLowerCase();
      if (lower.startsWith('gps:')) {
        gps = v.substring(4).trim();
        continue;
      }
      if (lower.startsWith('maps:')) {
        maps = v.substring(5).trim();
        continue;
      }
      if (RegExp(r'https?://\S+', caseSensitive: false).hasMatch(v)) {
        continue;
      }

      // Prefer a real address/label line.
      return v;
    }

    // Fallbacks when the snapshot only contains GPS/MAPS.
    if (gps != null && gps.isNotEmpty) return gps;
    if (maps != null && maps.isNotEmpty) return 'Ubicación vía GPS';
    return 'Ubicación disponible';
  }

  Uri? extractMapsUriFromText(String text) {
    for (final line in text.split('\n')) {
      final v = line.trim();
      if (v.isEmpty) continue;

      if (v.toLowerCase().startsWith('maps:')) {
        final candidate = v.substring(5).trim();
        final parsed = Uri.tryParse(candidate);
        if (parsed != null) return parsed;
      }

      final match = RegExp(r'https?://\S+', caseSensitive: false).firstMatch(v);
      if (match != null) {
        final candidate = match.group(0) ?? '';
        final parsed = Uri.tryParse(candidate);
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  Uri? uriFromLatLng(LatLng point) {
    return Uri.parse(buildGoogleMapsSearchUrl(point));
  }

  Uri? uriFromAddress(String value) {
    if (value.trim().isEmpty) return null;
    final q = Uri.encodeQueryComponent(value.trim());
    return Uri.parse('https://www.google.com/maps/search/?api=1&query=$q');
  }

  final gpsText = extractGpsTextFromSnapshot(address);
  final parsedPoint =
      latLng ??
      (gpsText == null ? null : parseLatLngFromText(gpsText)) ??
      parseLatLngFromText(address);
  final locationLabel = bestLabelFromText(address);

  if (parsedPoint != null) {
    return ServiceLocationInfo(
      label: locationLabel,
      mapsUri: uriFromLatLng(parsedPoint),
    );
  }

  // 1) Explicit maps URL.
  if (maps.isNotEmpty) {
    final parsed = Uri.tryParse(maps);
    if (parsed != null) {
      return ServiceLocationInfo(label: locationLabel, mapsUri: parsed);
    }
  }

  // 1b) Embedded URL (e.g. "MAPS: https://..." inside address snapshot).
  final embedded = extractMapsUriFromText(address);
  if (embedded != null) {
    return ServiceLocationInfo(label: locationLabel, mapsUri: embedded);
  }

  // 4) Plain address.
  if (address.isNotEmpty) {
    return ServiceLocationInfo(
      label: locationLabel,
      mapsUri: uriFromAddress(address),
    );
  }

  return const ServiceLocationInfo(label: 'Sin ubicación', mapsUri: null);
}
