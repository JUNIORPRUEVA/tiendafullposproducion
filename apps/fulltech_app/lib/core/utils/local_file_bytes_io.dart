import 'dart:io';

Future<List<int>> readLocalFileBytesImpl(String path) {
  return File(path).readAsBytes();
}
