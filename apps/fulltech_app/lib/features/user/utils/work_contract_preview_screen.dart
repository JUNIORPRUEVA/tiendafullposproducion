import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

class WorkContractPreviewScreen extends StatelessWidget {
  final Uint8List bytes;
  final String fileName;

  const WorkContractPreviewScreen({
    super.key,
    required this.bytes,
    required this.fileName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contrato (PDF)'),
      ),
      body: PdfPreview(
        pdfFileName: fileName,
        canChangeOrientation: false,
        canChangePageFormat: false,
        build: (format) async => bytes,
      ),
    );
  }
}
