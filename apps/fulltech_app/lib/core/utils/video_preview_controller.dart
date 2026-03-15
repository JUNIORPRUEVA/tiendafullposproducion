import 'package:video_player/video_player.dart';

import 'video_preview_controller_io.dart'
    if (dart.library.html) 'video_preview_controller_web.dart'
    as impl;

VideoPlayerController? createVideoPreviewControllerFromPath(String path) {
  return impl.createVideoPreviewControllerFromPath(path);
}
