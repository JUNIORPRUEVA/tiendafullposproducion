import 'dart:convert';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<bool> saveMediaBytes({
  required Uint8List bytes,
  required String fileName,
  required List<String> allowedExtensions,
  String? mimeType,
}) async {
  final dataUrl = Uri.dataFromBytes(
    bytes,
    mimeType: mimeType ?? 'application/octet-stream',
    encoding: utf8,
  ).toString();

  final anchor = web.HTMLAnchorElement()
    ..href = dataUrl
    ..download = fileName
    ..style.display = 'none';

  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  return true;
}