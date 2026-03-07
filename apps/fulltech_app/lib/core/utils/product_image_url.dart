String buildProductImageUrl({
  required String imageUrl,
  String? version,
}) {
  final trimmedUrl = imageUrl.trim();
  final trimmedVersion = version?.trim() ?? '';
  if (trimmedUrl.isEmpty || trimmedVersion.isEmpty) {
    return trimmedUrl;
  }

  try {
    final uri = Uri.parse(trimmedUrl);
    final queryParameters = <String, List<String>>{
      for (final entry in uri.queryParametersAll.entries)
        entry.key: List<String>.from(entry.value),
    };
    queryParameters['v'] = [trimmedVersion];

    final query = queryParameters.entries
        .expand(
          (entry) => entry.value.map(
            (value) =>
                '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(value)}',
          ),
        )
        .join('&');

    return uri.replace(query: query).toString();
  } catch (_) {
    final separator = trimmedUrl.contains('?') ? '&' : '?';
    return '$trimmedUrl${separator}v=${Uri.encodeQueryComponent(trimmedVersion)}';
  }
}