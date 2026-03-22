class ClientLocationPreview {
  final double? latitude;
  final double? longitude;

  const ClientLocationPreview({this.latitude, this.longitude});

  bool get hasCoordinates =>
      latitude != null &&
      longitude != null &&
      latitude!.isFinite &&
      longitude!.isFinite;
}

ClientLocationPreview parseClientLocationPreview(String? rawUrl) {
  final locationUrl = (rawUrl ?? '').trim();
  if (locationUrl.isEmpty) return const ClientLocationPreview();

  final decoded = Uri.decodeFull(locationUrl);
  final patterns = <RegExp>[
    RegExp(
      r'[?&]q=(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?)',
      caseSensitive: false,
    ),
    RegExp(r'@(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?)', caseSensitive: false),
    RegExp(r'(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?)'),
  ];

  for (final pattern in patterns) {
    final match = pattern.firstMatch(decoded);
    if (match == null) continue;

    final latitude = double.tryParse(match.group(1) ?? '');
    final longitude = double.tryParse(match.group(2) ?? '');

    if (latitude == null || longitude == null) continue;
    if (latitude < -90 || latitude > 90) continue;
    if (longitude < -180 || longitude > 180) continue;

    return ClientLocationPreview(latitude: latitude, longitude: longitude);
  }

  return const ClientLocationPreview();
}
