import 'dart:io';

import 'package:flutter/widgets.dart';

ImageProvider? localFileImageProvider(String path) {
  final p = path.trim();
  if (p.isEmpty) return null;

  try {
    final f = File(p);
    if (!f.existsSync()) return null;
    return FileImage(f);
  } catch (_) {
    return null;
  }
}
