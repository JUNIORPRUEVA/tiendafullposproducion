import 'package:video_player/video_player.dart';

VideoPlayerController? createVideoPreviewControllerFromPath(String path) {
  // No local file preview on web from FilePicker paths.
  return null;
}
