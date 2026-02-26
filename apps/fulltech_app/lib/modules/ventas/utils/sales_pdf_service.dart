import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../sales_models.dart';

Future<Uint8List> buildSalesSummaryPdf({
  required String employeeName,
  required DateTime from,
  required DateTime to,
  required SalesSummaryModel summary,
  required List<SaleModel> sales,
}) async {
  final currency = NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$');
  final dateFmt = DateFormat('dd/MM/yyyy');

  final doc = pw.Document(
    title: 'Resumen de ventas',
    author: 'FullTech',
  );

  doc.addPage(
    pw.MultiPage(
      margin: const pw.EdgeInsets.all(24),
      pageTheme: const pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
      ),
      build: (context) => [
        pw.Text(
          'Resumen de ventas',
          style: pw.TextStyle(
            fontSize: 22,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.blue900,
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Text('Empleado: $employeeName'),
        pw.Text('Rango: ${dateFmt.format(from)} - ${dateFmt.format(to)}'),
        pw.SizedBox(height: 12),
        pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            color: PdfColors.blue50,
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            border: pw.Border.all(color: PdfColors.blue200),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Total vendido: ${currency.format(summary.totalSold)}'),
              pw.Text('Total costo: ${currency.format(summary.totalCost)}'),
              pw.Text('Utilidad: ${currency.format(summary.totalProfit)}'),
              pw.Text('Comisión: ${currency.format(summary.totalCommission)}'),
            ],
          ),
        ),
        pw.SizedBox(height: 12),
        pw.TableHelper.fromTextArray(
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          cellAlignment: pw.Alignment.centerLeft,
          headers: const [
            'Fecha',
            'Cliente',
            'Vendido',
            'Costo',
            'Utilidad',
            'Comisión',
          ],
          data: sales
              .map(
                (sale) => [
                  dateFmt.format(sale.saleDate ?? DateTime.now()),
                  sale.customerName ?? 'Sin cliente',
                  currency.format(sale.totalSold),
                  currency.format(sale.totalCost),
                  currency.format(sale.totalProfit),
                  currency.format(sale.commissionAmount),
                ],
              )
              .toList(),
        ),
      ],
    ),
  );

  return doc.save();
}

Future<void> downloadSalesSummaryPdf({
  required Uint8List bytes,
  required DateTime from,
  required DateTime to,
}) async {
  final dateFmt = DateFormat('yyyyMMdd');
  final fileName =
      'resumen_ventas_${dateFmt.format(from)}_${dateFmt.format(to)}.pdf';

  await Printing.sharePdf(bytes: bytes, filename: fileName);
}
