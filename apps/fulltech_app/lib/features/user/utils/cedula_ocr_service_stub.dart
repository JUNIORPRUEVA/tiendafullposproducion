import 'cedula_ocr_types.dart';

class CedulaOcrServiceImpl implements CedulaOcrService {
  @override
  Future<CedulaOcrResult> scan({
    required List<int> bytes,
    required String fileName,
  }) async {
    throw UnsupportedError(
      'Escaneo de cédula no disponible en esta plataforma.',
    );
  }
}
