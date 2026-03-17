import 'local_file_bytes_stub.dart'
    if (dart.library.io) 'local_file_bytes_io.dart';

Future<List<int>> readLocalFileBytes(String path) {
  return readLocalFileBytesImpl(path);
}
