import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/fiscal_invoice_model.dart';

Future<Uint8List> buildFiscalInvoicesPdf({
  required DateTime from,
  required DateTime to,
  required List<FiscalInvoiceModel> invoices,
}) async {
  final doc = pw.Document(
    title: 'Reporte de facturas fiscales',
    author: 'FULLTECH, SRL',
  );

  final dateFmt = DateFormat('dd/MM/yyyy');
  final sales = invoices.where((i) => i.kind == FiscalInvoiceKind.sale).toList();
  final purchases =
      invoices.where((i) => i.kind == FiscalInvoiceKind.purchase).toList();

  final salesImages = <String, pw.ImageProvider?>{};
  for (final item in sales) {
    try {
      final bytes = await networkImage(item.imageUrl);
      salesImages[item.id] = bytes;
    } catch (_) {
      salesImages[item.id] = null;
    }
  }

  final purchaseImages = <String, pw.ImageProvider?>{};
  for (final item in purchases) {
    try {
      final bytes = await networkImage(item.imageUrl);
      purchaseImages[item.id] = bytes;
    } catch (_) {
      purchaseImages[item.id] = null;
    }
  }

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(24),
      build: (_) => [
        pw.Text(
          'FULLTECH, SRL',
          style: pw.TextStyle(
            fontSize: 20,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.blue900,
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Text('RNC: 133080209'),
        pw.Text(
          'Reporte de facturas fiscales del ${dateFmt.format(from)} al ${dateFmt.format(to)}',
        ),
        pw.SizedBox(height: 10),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            color: PdfColors.blue50,
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
            border: pw.Border.all(color: PdfColors.blue200),
          ),
          child: pw.Row(
            children: [
              pw.Expanded(
                child: _summaryChip('Total facturas', invoices.length.toString()),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: _summaryChip('Compras', purchases.length.toString()),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: _summaryChip('Ventas', sales.length.toString()),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 14),
        _sectionTitle('Facturas de compras'),
        pw.SizedBox(height: 8),
        ..._buildInvoiceSection(purchases, purchaseImages, dateFmt),
        pw.SizedBox(height: 14),
        _sectionTitle('Facturas de ventas'),
        pw.SizedBox(height: 8),
        ..._buildInvoiceSection(sales, salesImages, dateFmt),
      ],
    ),
  );

  return doc.save();
}

List<pw.Widget> _buildInvoiceSection(
  List<FiscalInvoiceModel> rows,
  Map<String, pw.ImageProvider?> images,
  DateFormat dateFmt,
) {
  if (rows.isEmpty) {
    return [pw.Text('Sin facturas en este apartado.')];
  }

  return rows
      .map(
        (item) => pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 10),
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            border: pw.Border.all(color: PdfColors.grey400),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                children: [
                  pw.Expanded(
                    child: pw.Text(
                      item.kind.label,
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  pw.Text(
                    'Registrada: ${dateFmt.format(item.createdAt)}',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                ],
              ),
              pw.SizedBox(height: 4),
              pw.Text('Fecha factura: ${dateFmt.format(item.invoiceDate)}'),
              pw.Text(
                'Registrado por: ${item.createdByName ?? item.createdById ?? 'N/D'}',
              ),
              if ((item.note ?? '').trim().isNotEmpty)
                pw.Text('Nota: ${item.note!.trim()}'),
              pw.SizedBox(height: 6),
              if (images[item.id] != null)
                pw.Container(
                  height: 220,
                  width: double.infinity,
                  alignment: pw.Alignment.center,
                  child: pw.Image(
                    images[item.id]!,
                    fit: pw.BoxFit.contain,
                  ),
                )
              else
                pw.Text('Imagen no disponible en PDF (verificar URL).'),
            ],
          ),
        ),
      )
      .toList();
}

pw.Widget _summaryChip(String label, String value) {
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    decoration: pw.BoxDecoration(
      color: PdfColors.white,
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      border: pw.Border.all(color: PdfColors.blue100),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 9)),
        pw.SizedBox(height: 2),
        pw.Text(
          value,
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13),
        ),
      ],
    ),
  );
}

pw.Widget _sectionTitle(String title) {
  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: const pw.BoxDecoration(
      color: PdfColors.grey200,
      borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
    ),
    child: pw.Text(
      title,
      style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12),
    ),
  );
}
