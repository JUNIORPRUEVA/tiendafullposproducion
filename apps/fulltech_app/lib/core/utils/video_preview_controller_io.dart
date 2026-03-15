import 'dart:io';

import 'package:video_player/video_player.dart';

VideoPlayerController? createVideoPreviewControllerFromPath(String path) {
  final p = path.trim();
  if (p.isEmpty) return null;

  final uri = Uri.tryParse(p);

  // Handle real URIs (http/https, file://, content://)
  if (uri != null && uri.hasScheme) {
    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'http' || scheme == 'https') {
      return VideoPlayerController.networkUrl(uri);
    }
    if (scheme == 'file') {
      return VideoPlayerController.file(File.fromUri(uri));
    }
    if (scheme == 'content') {
      // Android content URIs: let the platform handle it.
      return VideoPlayerController.networkUrl(uri);
    }
  }

  // Plain file path (Windows/Android cached path)
  return VideoPlayerController.file(File(p));
}
