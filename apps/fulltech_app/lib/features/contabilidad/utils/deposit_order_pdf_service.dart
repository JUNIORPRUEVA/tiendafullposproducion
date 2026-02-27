import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/models/close_model.dart';

class DepositOrderPdfData {
  final DateTime generatedAt;
  final DateTime windowFrom;
  final DateTime windowTo;
  final double reserveInCash;
  final double totalAvailableCash;
  final double depositTotal;
  final Map<CloseType, int> closesCountByType;
  final Map<CloseType, double> depositByType;
  final Map<CloseType, String> accountByType;

  const DepositOrderPdfData({
    required this.generatedAt,
    required this.windowFrom,
    required this.windowTo,
    required this.reserveInCash,
    required this.totalAvailableCash,
    required this.depositTotal,
    required this.closesCountByType,
    required this.depositByType,
    required this.accountByType,
  });
}

Future<Uint8List> buildDepositOrderPdf({
  required DepositOrderPdfData data,
}) async {
  final money = NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$ ');
  final dateFmt = DateFormat('dd/MM/yyyy');
  final dateTimeFmt = DateFormat('dd/MM/yyyy HH:mm');

  final doc = pw.Document(
    title: 'Carta de Depósito Bancario',
    author: 'FULLTECH, SRL',
  );

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
        pw.Text('Carta de Depósito Bancario · Banco Popular'),
        pw.Text('Fecha emisión: ${dateTimeFmt.format(data.generatedAt)}'),
        pw.SizedBox(height: 12),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            border: pw.Border.all(color: PdfColors.grey400),
            color: PdfColors.grey100,
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Instrucción:',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'Favor realizar depósito bancario de los valores indicados por categoría, manteniendo un fondo fijo en caja de ${money.format(data.reserveInCash)}.',
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'Período evaluado: ${dateFmt.format(data.windowFrom)} - ${dateFmt.format(data.windowTo)}',
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 12),
        pw.TableHelper.fromTextArray(
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          headers: const [
            'Categoría',
            'Cantidad de cierres',
            'Cuenta destino',
            'Monto a depositar',
          ],
          data: CloseType.values
              .map(
                (type) => [
                  _typeLabel(type),
                  '${data.closesCountByType[type] ?? 0}',
                  data.accountByType[type] ?? '-',
                  money.format(data.depositByType[type] ?? 0),
                ],
              )
              .toList(),
        ),
        pw.SizedBox(height: 10),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Container(
            width: 310,
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
              border: pw.Border.all(color: PdfColors.grey400),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                _totalLine('Efectivo disponible', money.format(data.totalAvailableCash)),
                _totalLine('Fondo fijo en caja', money.format(data.reserveInCash)),
                pw.Divider(height: 10),
                _totalLine(
                  'Total a depositar',
                  money.format(data.depositTotal),
                  highlight: true,
                ),
              ],
            ),
          ),
        ),
        pw.SizedBox(height: 18),
        pw.Text('Mensajero responsable: ______________________________'),
        pw.SizedBox(height: 24),
        pw.Text('Firma autorizado FULLTECH, SRL: ______________________'),
      ],
    ),
  );

  return doc.save();
}

pw.Widget _totalLine(String label, String value, {bool highlight = false}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(
      children: [
        pw.Expanded(
          child: pw.Text(
            label,
            style: pw.TextStyle(
              fontWeight: highlight ? pw.FontWeight.bold : pw.FontWeight.normal,
              fontSize: 10,
            ),
          ),
        ),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontWeight: highlight ? pw.FontWeight.bold : pw.FontWeight.normal,
            fontSize: 10,
          ),
        ),
      ],
    ),
  );
}

String _typeLabel(CloseType type) {
  switch (type) {
    case CloseType.capsulas:
      return 'Pastilla';
    case CloseType.pos:
      return 'Software';
    case CloseType.tienda:
      return 'Tienda';
  }
}
