class CedulaOcrResult {
  final String rawText;
  final String? cedula;
  final String? nombreCompleto;
  final DateTime? fechaNacimiento;

  const CedulaOcrResult({
    required this.rawText,
    this.cedula,
    this.nombreCompleto,
    this.fechaNacimiento,
  });
}

abstract class CedulaOcrService {
  Future<CedulaOcrResult> scan({
    required List<int> bytes,
    required String fileName,
  });
}
