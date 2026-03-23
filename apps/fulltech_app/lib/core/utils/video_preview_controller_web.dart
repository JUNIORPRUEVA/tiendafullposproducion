import 'dart:typed_data';

import 'package:video_player/video_player.dart';

VideoPlayerController? createVideoPreviewController({
  String? path,
  Uint8List? bytes,
  String? fileName,
}) {
  final source = (path ?? '').trim();
  if (source.isEmpty) return null;

  final uri = Uri.tryParse(source);
  if (uri != null && uri.hasScheme) {
    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'http' || scheme == 'https') {
      return VideoPlayerController.networkUrl(uri);
    }
  }

  // No local file preview on web from FilePicker paths.
  return null;
}
