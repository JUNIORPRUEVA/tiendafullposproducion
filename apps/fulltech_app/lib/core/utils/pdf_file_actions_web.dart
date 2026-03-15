import 'dart:typed_data';

import 'package:printing/printing.dart';

Future<bool> savePdfBytes({
  required Uint8List bytes,
  required String fileName,
}) async {
  // On web, the share action typically triggers a download flow.
  await Printing.sharePdf(bytes: bytes, filename: fileName);
  return true;
}
