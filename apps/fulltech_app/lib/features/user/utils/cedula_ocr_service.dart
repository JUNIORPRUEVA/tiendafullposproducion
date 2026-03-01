import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'cedula_ocr_types.dart';
import 'cedula_ocr_service_stub.dart'
    if (dart.library.io) 'cedula_ocr_service_io.dart';

final cedulaOcrServiceProvider = Provider<CedulaOcrService>((ref) {
  return CedulaOcrServiceImpl();
});
