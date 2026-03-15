import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

Future<bool> savePdfBytes({
  required Uint8List bytes,
  required String fileName,
}) async {
  final path = await FilePicker.platform.saveFile(
    dialogTitle: 'Guardar PDF',
    fileName: fileName,
    type: FileType.custom,
    allowedExtensions: const ['pdf'],
  );

  if (path == null || path.trim().isEmpty) return false;

  await File(path).writeAsBytes(bytes, flush: true);
  return true;
}
