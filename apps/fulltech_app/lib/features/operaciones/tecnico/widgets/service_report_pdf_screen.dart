import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../../../core/utils/pdf_file_actions.dart';

class ServiceReportPdfScreen extends StatefulWidget {
  const ServiceReportPdfScreen({
    super.key,
    required this.fileName,
    required this.loadBytes,
  });

  final String fileName;
  final Future<Uint8List> Function() loadBytes;

  @override
  State<ServiceReportPdfScreen> createState() => _ServiceReportPdfScreenState();
}

class _ServiceReportPdfScreenState extends State<ServiceReportPdfScreen> {
  late final Future<Uint8List> _bytesFuture;

  @override
  void initState() {
    super.initState();
    _bytesFuture = widget.loadBytes();
  }

  Future<Uint8List> _bytes() => _bytesFuture;

  Future<void> _download() async {
    final messenger = ScaffoldMessenger.maybeOf(context);

    try {
      final bytes = await _bytes();
      final ok = await savePdfBytes(bytes: bytes, fileName: widget.fileName);
      if (!mounted) return;

      if (ok) {
        messenger?.showSnackBar(
          const SnackBar(content: Text('PDF guardado')),
        );
      }
    } catch (e) {
      messenger?.showSnackBar(
        SnackBar(content: Text('No se pudo guardar el PDF: $e')),
      );
    }
  }

  Future<void> _share() async {
    final messenger = ScaffoldMessenger.maybeOf(context);

    try {
      final bytes = await _bytes();
      await Printing.sharePdf(bytes: bytes, filename: widget.fileName);
    } catch (e) {
      messenger?.showSnackBar(
        SnackBar(content: Text('No se pudo compartir el PDF: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reporte (PDF)'),
        actions: [
          IconButton(
            tooltip: 'Descargar',
            onPressed: _download,
            icon: const Icon(Icons.download_outlined),
          ),
          IconButton(
            tooltip: 'Compartir',
            onPressed: _share,
            icon: const Icon(Icons.share_outlined),
          ),
        ],
      ),
      body: PdfPreview(
        pdfFileName: widget.fileName,
        canChangePageFormat: false,
        canChangeOrientation: false,
        allowPrinting: true,
        allowSharing: false,
        build: (format) async => await _bytes(),
      ),
    );
  }
}
