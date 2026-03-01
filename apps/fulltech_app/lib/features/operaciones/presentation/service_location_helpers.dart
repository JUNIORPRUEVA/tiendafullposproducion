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

  Uri? uriFromLatLng(LatLng point) {
    return Uri.parse(buildGoogleMapsSearchUrl(point));
  }

  Uri? uriFromAddress(String value) {
    if (value.trim().isEmpty) return null;
    final q = Uri.encodeQueryComponent(value.trim());
    return Uri.parse('https://www.google.com/maps/search/?api=1&query=$q');
  }

  // 1) Explicit maps URL.
  if (maps.isNotEmpty) {
    final parsed = Uri.tryParse(maps);
    if (parsed != null) {
      return ServiceLocationInfo(
        label: 'Ubicación disponible',
        mapsUri: parsed,
      );
    }
  }

  // 2) Explicit lat/lng.
  if (latLng != null) {
    return ServiceLocationInfo(
      label: 'Ubicación disponible',
      mapsUri: uriFromLatLng(latLng),
    );
  }

  // 3) Try to extract lat/lng from text (address field sometimes contains maps links).
  final parsedPoint = parseLatLngFromText(address);
  if (parsedPoint != null) {
    return ServiceLocationInfo(
      label: 'Ubicación disponible',
      mapsUri: uriFromLatLng(parsedPoint),
    );
  }

  // 4) Plain address.
  if (address.isNotEmpty) {
    return ServiceLocationInfo(
      label: address,
      mapsUri: uriFromAddress(address),
    );
  }

  return const ServiceLocationInfo(label: 'Sin ubicación', mapsUri: null);
}
