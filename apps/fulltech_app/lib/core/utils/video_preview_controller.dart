import 'dart:typed_data';

import 'package:video_player/video_player.dart';

import 'video_preview_controller_io.dart'
    if (dart.library.html) 'video_preview_controller_web.dart'
    as impl;

VideoPlayerController? createVideoPreviewController({
  String? path,
  Uint8List? bytes,
  String? fileName,
}) {
  return impl.createVideoPreviewController(
    path: path,
    bytes: bytes,
    fileName: fileName,
  );
}
