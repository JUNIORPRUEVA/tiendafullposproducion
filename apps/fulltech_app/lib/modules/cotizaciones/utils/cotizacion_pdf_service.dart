import 'dart:convert';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/company/company_settings_model.dart';
import '../cotizacion_models.dart';

Future<Uint8List> buildCotizacionPdf({
  required CotizacionModel cotizacion,
  CompanySettings? company,
}) async {
  final money = NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$');
  final dateFmt = DateFormat('dd/MM/yyyy HH:mm');

  final doc = pw.Document(title: 'Cotización', author: 'FullTech');

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(24),
      build: (context) => [
        _companyHeader(company),
        pw.SizedBox(height: 10),
        pw.Text(
          'Cotización',
          style: pw.TextStyle(
            fontSize: 22,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.blue900,
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Text('No.: ${cotizacion.id.substring(0, 8)}'),
        pw.Text('Fecha: ${dateFmt.format(cotizacion.createdAt)}'),
        pw.Text('Cliente: ${cotizacion.customerName}'),
        if ((cotizacion.customerPhone ?? '').trim().isNotEmpty)
          pw.Text('Teléfono: ${cotizacion.customerPhone}'),
        if (cotizacion.note.trim().isNotEmpty) ...[
          pw.SizedBox(height: 4),
          pw.Text('Nota: ${cotizacion.note}'),
        ],
        pw.SizedBox(height: 12),
        pw.TableHelper.fromTextArray(
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          headers: const ['Producto', 'Cant.', 'Precio', 'Total'],
          data: cotizacion.items
              .map(
                (item) => [
                  item.nombre,
                  item.qty.toStringAsFixed(item.qty % 1 == 0 ? 0 : 2),
                  money.format(item.unitPrice),
                  money.format(item.total),
                ],
              )
              .toList(),
          cellAlignments: {
            1: pw.Alignment.center,
            2: pw.Alignment.centerRight,
            3: pw.Alignment.centerRight,
          },
        ),
        pw.SizedBox(height: 14),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Container(
            width: 300,
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
              border: pw.Border.all(color: PdfColors.grey400),
              color: PdfColors.grey100,
            ),
            child: pw.Column(
              children: [
                _line('Subtotal', money.format(cotizacion.subtotal)),
                _line(
                  'ITBIS (${(cotizacion.itbisRate * 100).toStringAsFixed(0)}%)',
                  cotizacion.includeItbis
                      ? money.format(cotizacion.itbisAmount)
                      : 'No aplicado',
                ),
                pw.Divider(height: 12),
                _line('Total', money.format(cotizacion.total), highlight: true),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  return doc.save();
}

pw.Widget _companyHeader(CompanySettings? company) {
  final hasLogo = (company?.logoBase64 ?? '').trim().isNotEmpty;
  pw.MemoryImage? logoImage;

  if (hasLogo) {
    try {
      logoImage = pw.MemoryImage(base64Decode(company!.logoBase64!.trim()));
    } catch (_) {
      logoImage = null;
    }
  }

  final name = (company?.companyName ?? '').trim();
  final rnc = (company?.rnc ?? '').trim();
  final phone = (company?.phone ?? '').trim();
  final address = (company?.address ?? '').trim();

  return pw.Container(
    padding: const pw.EdgeInsets.all(10),
    decoration: pw.BoxDecoration(
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      border: pw.Border.all(color: PdfColors.grey400),
      color: PdfColors.grey100,
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (logoImage != null)
          pw.Container(
            width: 52,
            height: 52,
            margin: const pw.EdgeInsets.only(right: 10),
            child: pw.Image(logoImage, fit: pw.BoxFit.cover),
          ),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                name.isEmpty ? 'Empresa no configurada' : name,
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              if (rnc.isNotEmpty) pw.Text('RNC: $rnc'),
              if (phone.isNotEmpty) pw.Text('Tel: $phone'),
              if (address.isNotEmpty) pw.Text('Dir: $address'),
            ],
          ),
        ),
      ],
    ),
  );
}

Future<void> shareCotizacionPdf({
  required Uint8List bytes,
  required CotizacionModel cotizacion,
}) async {
  final dateFmt = DateFormat('yyyyMMdd_HHmm');
  final filename =
      'cotizacion_${dateFmt.format(cotizacion.createdAt)}_${cotizacion.id.substring(0, 6)}.pdf';
  await Printing.sharePdf(bytes: bytes, filename: filename);
}

pw.Widget _line(String label, String value, {bool highlight = false}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(
      children: [
        pw.Expanded(
          child: pw.Text(
            label,
            style: pw.TextStyle(
              fontWeight: highlight ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        ),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontWeight: highlight ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      ],
    ),
  );
}
