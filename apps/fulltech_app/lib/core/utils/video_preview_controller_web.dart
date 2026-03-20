import 'dart:typed_data';

import 'package:video_player/video_player.dart';

VideoPlayerController? createVideoPreviewController({
  String? path,
  Uint8List? bytes,
  String? fileName,
}) {
  // No local file preview on web from FilePicker paths.
  return null;
}
