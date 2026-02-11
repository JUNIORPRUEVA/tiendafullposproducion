import 'package:http_parser/http_parser.dart';

MediaType? detectImageMime(String filename) {
  final lower = filename.toLowerCase();
  if (lower.endsWith('.png')) return MediaType.parse('image/png');
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
    return MediaType.parse('image/jpeg');
  }
  if (lower.endsWith('.webp')) return MediaType.parse('image/webp');
  return null;
}

bool isImageExtension(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.png') ||
      lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.webp');
}
