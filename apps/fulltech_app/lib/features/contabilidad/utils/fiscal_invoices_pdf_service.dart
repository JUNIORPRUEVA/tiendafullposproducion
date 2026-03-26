import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/fiscal_invoice_model.dart';
import 'fiscal_invoice_image_url.dart';
import 'fiscal_invoice_pdf_image_processor.dart';

const _companyName = 'FULLTECH, SRL';
const _companyRnc = '133080209';

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
  final generatedFmt = DateFormat('dd/MM/yyyy HH:mm');
  final salesByCard = invoices
      .where((i) => i.kind == FiscalInvoiceKind.saleCard)
      .toList();
  final sales = invoices
      .where((i) => i.kind == FiscalInvoiceKind.sale)
      .toList();
  final purchases = invoices
      .where((i) => i.kind == FiscalInvoiceKind.purchase)
      .toList();

  final salesByCardImages = await _loadInvoiceImages(salesByCard);
  final salesImages = await _loadInvoiceImages(sales);
  final purchaseImages = await _loadInvoiceImages(purchases);

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(24),
      build: (_) => [
        _buildCompanyHeader(
          from: from,
          to: to,
          dateFmt: dateFmt,
          generatedFmt: generatedFmt,
        ),
        pw.SizedBox(height: 12),
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
                child: _summaryChip(
                  'Total facturas',
                  invoices.length.toString(),
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: _summaryChip('Tarjeta', salesByCard.length.toString()),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: _summaryChip('Ventas', sales.length.toString()),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: _summaryChip('Compras', purchases.length.toString()),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 14),
        _sectionTitle('Informe de ventas por tarjeta'),
        pw.SizedBox(height: 8),
        ..._buildInvoiceSection(salesByCard, salesByCardImages, dateFmt),
        pw.SizedBox(height: 14),
        _sectionTitle('Informe de ventas'),
        pw.SizedBox(height: 8),
        ..._buildInvoiceSection(sales, salesImages, dateFmt),
        pw.SizedBox(height: 14),
        _sectionTitle('Informe de compras'),
        pw.SizedBox(height: 8),
        ..._buildInvoiceSection(purchases, purchaseImages, dateFmt),
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
    return [
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: PdfColors.grey100,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
          border: pw.Border.all(color: PdfColors.grey300),
        ),
        child: pw.Text('Sin facturas en este apartado.'),
      ),
    ];
  }

  return rows
      .map(
        (item) => pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 10),
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            color: PdfColors.white,
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
            border: pw.Border.all(color: PdfColors.blue100),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                children: [
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.blue50,
                      borderRadius: const pw.BorderRadius.all(
                        pw.Radius.circular(999),
                      ),
                    ),
                    child: pw.Text(
                      item.kind.label,
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 10,
                        color: PdfColors.blue900,
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 8),
                  pw.Expanded(
                    child: pw.Text(
                      'Factura: ${dateFmt.format(item.invoiceDate)}',
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
                  child: pw.Image(images[item.id]!, fit: pw.BoxFit.contain),
                )
              else
                pw.Text('Imagen no disponible en PDF (verificar URL).'),
            ],
          ),
        ),
      )
      .toList();
}

Future<Map<String, pw.ImageProvider?>> _loadInvoiceImages(
  List<FiscalInvoiceModel> rows,
) async {
  final images = <String, pw.ImageProvider?>{};
  for (final item in rows) {
    try {
      final bytes = await _downloadImageBytes(
        resolveFiscalInvoiceImageUrl(item.imageUrl),
      );
      final encoded = enhanceFiscalInvoiceImageForPdf(bytes);
      images[item.id] = pw.MemoryImage(encoded ?? bytes);
    } catch (_) {
      images[item.id] = null;
    }
  }
  return images;
}

pw.Widget _buildCompanyHeader({
  required DateTime from,
  required DateTime to,
  required DateFormat dateFmt,
  required DateFormat generatedFmt,
}) {
  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.all(16),
    decoration: const pw.BoxDecoration(
      color: PdfColors.blue900,
      borderRadius: pw.BorderRadius.all(pw.Radius.circular(12)),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          _companyName,
          style: pw.TextStyle(
            fontSize: 21,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.white,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'RNC: $_companyRnc',
          style: const pw.TextStyle(color: PdfColors.white),
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          'Informe de facturas fiscales',
          style: pw.TextStyle(
            fontSize: 14,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.white,
          ),
        ),
        pw.SizedBox(height: 3),
        pw.Text(
          'Periodo: ${dateFmt.format(from)} al ${dateFmt.format(to)}',
          style: const pw.TextStyle(color: PdfColors.white),
        ),
        pw.Text(
          'Generado: ${generatedFmt.format(DateTime.now())}',
          style: const pw.TextStyle(color: PdfColors.white),
        ),
      ],
    ),
  );
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

Future<Uint8List> _downloadImageBytes(String imageUrl) async {
  if (imageUrl.trim().isEmpty) {
    throw StateError('Fiscal invoice image URL is empty');
  }

  final uri = Uri.parse(imageUrl);
  final assetBundle = NetworkAssetBundle(uri);
  final byteData = await assetBundle.load(uri.toString());
  return byteData.buffer.asUint8List(
    byteData.offsetInBytes,
    byteData.lengthInBytes,
  );
}
