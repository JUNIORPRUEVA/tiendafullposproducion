import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/company/company_settings_model.dart';
import '../cotizacion_models.dart';

final PdfColor _pageBackground = PdfColor.fromHex('#FFFFFF');
final PdfColor _sectionBorder = PdfColor.fromHex('#E2E7EE');
final PdfColor _softDivider = PdfColor.fromHex('#EDF1F5');
final PdfColor _textPrimary = PdfColor.fromHex('#1E2430');
final PdfColor _textMuted = PdfColor.fromHex('#667180');
final PdfColor _textStrong = PdfColor.fromHex('#111827');

Future<Uint8List> buildCotizacionPdf({
  required CotizacionModel cotizacion,
  CompanySettings? company,
}) async {
  final money = NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$');
  final dateFmt = DateFormat('dd/MM/yyyy h:mm a', 'es_DO');
  final qtyFmt = NumberFormat('#,##0.##', 'es_DO');
  final logoImage = await _resolveCompanyLogo(company);
  final companyName = _fallback(company?.companyName, fallback: 'FULLTECH');

  final doc = pw.Document(title: 'Cotizacion', author: companyName);

  doc.addPage(
    pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(26, 24, 26, 22),
        buildBackground: (context) => pw.FullPage(
          ignoreMargins: true,
          child: pw.Container(color: _pageBackground),
        ),
      ),
      header: (context) => _pageHeader(
        company: company,
        logoImage: logoImage,
        cotizacion: cotizacion,
        dateFmt: dateFmt,
        isContinuation: context.pageNumber > 1,
      ),
      footer: (context) => _pageFooter(context.pageNumber, context.pagesCount),
      build: (context) => [
        _detailSection(cotizacion, money, qtyFmt),
        pw.SizedBox(height: 12),
        _bottomSection(cotizacion, money),
      ],
    ),
  );

  return doc.save();
}

pw.Widget _pageHeader({
  required CompanySettings? company,
  required pw.MemoryImage? logoImage,
  required CotizacionModel cotizacion,
  required DateFormat dateFmt,
  required bool isContinuation,
}) {
  final companyName = _fallback(company?.companyName, fallback: 'FULLTECH');
  final quoteCode = _buildQuoteCode(cotizacion.id);
  final rnc = _clean(company?.rnc);
  final phone = _clean(company?.phone);
  final address = _clean(company?.address);
  final customerName = _fallback(
    cotizacion.customerName,
    fallback: 'Cliente no especificado',
  );
  final customerPhone = _fallback(
    cotizacion.customerPhone,
    fallback: 'No registrado',
  );
  final sellerName = _fallback(
    cotizacion.createdByUserName,
    fallback: 'Equipo comercial',
  );

  return _sectionBox(
    margin: const pw.EdgeInsets.only(bottom: 14),
    padding: const pw.EdgeInsets.fromLTRB(16, 14, 16, 14),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              flex: 6,
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _logoFrame(companyName: companyName, logoImage: logoImage),
                  pw.SizedBox(width: 12),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          companyName,
                          style: pw.TextStyle(
                            fontSize: 16,
                            fontWeight: pw.FontWeight.bold,
                            color: _textStrong,
                          ),
                        ),
                        pw.SizedBox(height: 6),
                        if (rnc.isNotEmpty) _subtleLine('RNC: $rnc'),
                        if (phone.isNotEmpty) _subtleLine('Tel: $phone'),
                        if (address.isNotEmpty) _subtleLine(address),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(width: 16),
            pw.Expanded(
              flex: 4,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _headerFact('Cotización', quoteCode),
                  pw.SizedBox(height: 5),
                  _headerFact('Fecha', dateFmt.format(cotizacion.createdAt)),
                  if (cotizacion.includeItbis) ...[
                    pw.SizedBox(height: 5),
                    _headerFact(
                      'Impuesto',
                      '${(cotizacion.itbisRate * 100).toStringAsFixed(0)}% ITBIS',
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 12),
          child: pw.Container(height: 1, color: _softDivider),
        ),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: _infoBlock(
                title: 'Cliente',
                lines: [customerName, customerPhone],
              ),
            ),
            pw.SizedBox(width: 12),
            pw.Expanded(
              child: _infoBlock(
                title: 'Vendedor',
                lines: [sellerName],
              ),
            ),
          ],
        ),
        if (isContinuation) ...[
          pw.SizedBox(height: 8),
          pw.Text(
            'Continuación de la cotización',
            style: pw.TextStyle(
              fontSize: 8,
              color: _textMuted,
              fontStyle: pw.FontStyle.italic,
            ),
          ),
        ],
      ],
    ),
  );
}

pw.Widget _pageFooter(int pageNumber, int totalPages) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(top: 6),
    child: pw.Row(
      children: [
        pw.Text(
          pageNumber > 1
              ? 'Esta página continúa la cotización anterior'
              : 'Documento comercial',
          style: pw.TextStyle(fontSize: 8, color: _textMuted),
        ),
        pw.Spacer(),
        pw.Text(
          'Página $pageNumber de $totalPages',
          style: pw.TextStyle(fontSize: 8, color: _textMuted),
        ),
      ],
    ),
  );
}

pw.Widget _detailSection(
  CotizacionModel cotizacion,
  NumberFormat money,
  NumberFormat qtyFmt,
) {
  return _sectionBox(
    padding: const pw.EdgeInsets.fromLTRB(14, 14, 14, 12),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _sectionTitle('Detalle de productos'),
        pw.SizedBox(height: 10),
        _detailLabelsRow(),
        pw.SizedBox(height: 6),
        if (cotizacion.items.isEmpty)
          _emptyDetailRow()
        else
          ...cotizacion.items.map(
            (item) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 7),
              child: _detailItemRow(item, money, qtyFmt),
            ),
          ),
      ],
    ),
  );
}

pw.Widget _bottomSection(CotizacionModel cotizacion, NumberFormat money) {
  final note = cotizacion.note.trim();

  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        child: note.isEmpty
            ? pw.SizedBox()
            : _sectionBox(
                padding: const pw.EdgeInsets.fromLTRB(14, 14, 14, 14),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _sectionTitle('Observaciones'),
                    pw.SizedBox(height: 8),
                    pw.Text(
                      note,
                      style: pw.TextStyle(
                        fontSize: 9.6,
                        color: _textPrimary,
                        lineSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ),
      ),
      if (note.isNotEmpty) pw.SizedBox(width: 12),
      pw.SizedBox(width: 224, child: _totalsCard(cotizacion, money)),
    ],
  );
}

pw.Widget _totalsCard(CotizacionModel cotizacion, NumberFormat money) {
  return _sectionBox(
    padding: const pw.EdgeInsets.fromLTRB(14, 14, 14, 14),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _sectionTitle('Totales'),
        pw.SizedBox(height: 10),
        _totalLine('Subtotal', money.format(cotizacion.subtotalBeforeDiscount)),
        if (cotizacion.hasDiscount)
          _totalLine(
            'Descuento aplicado',
            '-${money.format(cotizacion.discountAmount)}',
          ),
        if (cotizacion.hasDiscount)
          _totalLine('Subtotal con descuento', money.format(cotizacion.subtotal)),
        if (cotizacion.includeItbis)
          _totalLine('ITBIS', money.format(cotizacion.itbisAmount)),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 8),
          child: pw.Container(height: 1, color: _softDivider),
        ),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: pw.BoxDecoration(
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
            border: pw.Border.all(color: _sectionBorder, width: 0.6),
          ),
          child: pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text(
                  'Total general',
                  style: pw.TextStyle(
                    fontSize: 10.2,
                    fontWeight: pw.FontWeight.bold,
                    color: _textStrong,
                  ),
                ),
              ),
              pw.Text(
                money.format(cotizacion.total),
                style: pw.TextStyle(
                  fontSize: 11.4,
                  fontWeight: pw.FontWeight.bold,
                  color: _textStrong,
                ),
              ),
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
      'cotizacion_${dateFmt.format(cotizacion.createdAt)}_${_buildFileToken(cotizacion.id, length: 6, fallback: 'manual')}.pdf';
  await Printing.sharePdf(bytes: bytes, filename: filename);
}

Future<pw.MemoryImage?> _resolveCompanyLogo(CompanySettings? company) async {
  final rawLogo = _clean(company?.logoBase64);
  if (rawLogo.isNotEmpty) {
    try {
      return pw.MemoryImage(base64Decode(rawLogo));
    } catch (_) {}
  }

  try {
    final asset = await rootBundle.load('assets/image/logo.png');
    return pw.MemoryImage(asset.buffer.asUint8List());
  } catch (_) {
    return null;
  }
}

String _buildQuoteCode(String id) {
  final token = _buildFileToken(id, length: 8, fallback: 'MANUAL');
  return 'COT-$token';
}

String _buildFileToken(
  String id, {
  required int length,
  required String fallback,
}) {
  final normalized = id.replaceAll('-', '').trim();
  if (normalized.isEmpty) return fallback;
  return normalized.length > length
      ? normalized.substring(0, length).toUpperCase()
      : normalized.toUpperCase();
}

String _fallback(String? value, {required String fallback}) {
  final cleaned = _clean(value);
  return cleaned.isEmpty ? fallback : cleaned;
}

String _clean(String? value) => (value ?? '').trim();

pw.Widget _sectionBox({
  required pw.Widget child,
  pw.EdgeInsetsGeometry padding = const pw.EdgeInsets.all(12),
  pw.EdgeInsetsGeometry margin = pw.EdgeInsets.zero,
}) {
  return pw.Container(
    margin: margin,
    padding: padding,
    decoration: pw.BoxDecoration(
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
      border: pw.Border.all(color: _sectionBorder, width: 0.45),
    ),
    child: child,
  );
}

pw.Widget _sectionTitle(String text) {
  return pw.Text(
    text,
    style: pw.TextStyle(
      fontSize: 11.4,
      color: _textStrong,
      fontWeight: pw.FontWeight.bold,
      letterSpacing: 0.15,
    ),
  );
}

pw.Widget _logoFrame({
  required String companyName,
  required pw.MemoryImage? logoImage,
}) {
  return pw.Container(
    width: 58,
    height: 58,
    padding: const pw.EdgeInsets.all(8),
    decoration: pw.BoxDecoration(
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
      border: pw.Border.all(color: _sectionBorder, width: 0.45),
    ),
    child: logoImage != null
        ? pw.Image(logoImage, fit: pw.BoxFit.contain)
        : pw.Center(
            child: pw.Text(
              companyName.substring(0, 1).toUpperCase(),
              style: pw.TextStyle(
                fontSize: 20,
                fontWeight: pw.FontWeight.bold,
                color: _textStrong,
              ),
            ),
          ),
  );
}

pw.Widget _subtleLine(String text) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 2),
    child: pw.Text(
      text,
      style: pw.TextStyle(fontSize: 8.6, color: _textMuted),
    ),
  );
}

pw.Widget _headerFact(String label, String value) {
  final cleanValue = value.trim();
  if (cleanValue.isEmpty) return pw.SizedBox();

  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.SizedBox(
        width: 54,
        child: pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: 7.6,
            fontWeight: pw.FontWeight.bold,
            color: _textMuted,
          ),
        ),
      ),
      pw.Expanded(
        child: pw.Text(
          cleanValue,
          style: pw.TextStyle(fontSize: 8.4, color: _textPrimary),
        ),
      ),
    ],
  );
}

pw.Widget _infoBlock({required String title, required List<String> lines}) {
  final visibleLines = lines
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);

  return pw.Container(
    padding: const pw.EdgeInsets.fromLTRB(10, 9, 10, 9),
    decoration: pw.BoxDecoration(
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      border: pw.Border.all(color: _sectionBorder, width: 0.4),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          title.toUpperCase(),
          style: pw.TextStyle(
            fontSize: 7.5,
            fontWeight: pw.FontWeight.bold,
            color: _textMuted,
            letterSpacing: 0.4,
          ),
        ),
        pw.SizedBox(height: 5),
        for (var index = 0; index < visibleLines.length; index++)
          pw.Padding(
            padding: pw.EdgeInsets.only(
              bottom: index == visibleLines.length - 1 ? 0 : 3,
            ),
            child: pw.Text(
              visibleLines[index],
              style: pw.TextStyle(fontSize: 9.1, color: _textPrimary),
            ),
          ),
      ],
    ),
  );
}

pw.Widget _detailLabelsRow() {
  return pw.Container(
    padding: const pw.EdgeInsets.fromLTRB(10, 0, 10, 6),
    child: pw.Row(
      children: [
        pw.Expanded(
          flex: 52,
          child: _detailLabel('Descripción', align: pw.TextAlign.left),
        ),
        pw.SizedBox(width: 8),
        pw.Expanded(
          flex: 12,
          child: _detailLabel('Cant.', align: pw.TextAlign.center),
        ),
        pw.SizedBox(width: 8),
        pw.Expanded(
          flex: 16,
          child: _detailLabel('Unitario', align: pw.TextAlign.right),
        ),
        pw.SizedBox(width: 8),
        pw.Expanded(
          flex: 20,
          child: _detailLabel('Importe', align: pw.TextAlign.right),
        ),
      ],
    ),
  );
}

pw.Widget _detailLabel(String text, {required pw.TextAlign align}) {
  return pw.Text(
    text,
    textAlign: align,
    style: pw.TextStyle(
      fontSize: 7.7,
      color: _textMuted,
      fontWeight: pw.FontWeight.bold,
      letterSpacing: 0.35,
    ),
  );
}

pw.Widget _detailItemRow(
  CotizacionItem item,
  NumberFormat money,
  NumberFormat qtyFmt,
) {
  return pw.Container(
    padding: const pw.EdgeInsets.fromLTRB(10, 9, 10, 9),
    decoration: pw.BoxDecoration(
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      border: pw.Border.all(color: _sectionBorder, width: 0.42),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          flex: 52,
          child: pw.Text(
            item.nombre.trim().isEmpty
                ? 'Producto sin descripción'
                : item.nombre.trim(),
            style: pw.TextStyle(
              fontSize: 9.2,
              color: _textPrimary,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
        pw.SizedBox(width: 8),
        pw.Expanded(
          flex: 12,
          child: pw.Text(
            qtyFmt.format(item.qty),
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 9, color: _textPrimary),
          ),
        ),
        pw.SizedBox(width: 8),
        pw.Expanded(
          flex: 16,
          child: pw.Text(
            money.format(item.unitPrice),
            textAlign: pw.TextAlign.right,
            style: pw.TextStyle(fontSize: 9, color: _textPrimary),
          ),
        ),
        pw.SizedBox(width: 8),
        pw.Expanded(
          flex: 20,
          child: pw.Text(
            money.format(item.total),
            textAlign: pw.TextAlign.right,
            style: pw.TextStyle(
              fontSize: 9.2,
              color: _textStrong,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
      ],
    ),
  );
}

pw.Widget _emptyDetailRow() {
  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 11),
    decoration: pw.BoxDecoration(
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      border: pw.Border.all(color: _sectionBorder, width: 0.42),
    ),
    child: pw.Text(
      'No hay productos registrados en esta cotización.',
      style: pw.TextStyle(fontSize: 9.1, color: _textMuted),
    ),
  );
}

pw.Widget _totalLine(String label, String value) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 3),
    child: pw.Row(
      children: [
        pw.Expanded(
          child: pw.Text(
            label,
            style: pw.TextStyle(fontSize: 9.2, color: _textPrimary),
          ),
        ),
        pw.Text(
          value,
          style: pw.TextStyle(fontSize: 9.2, color: _textPrimary),
        ),
      ],
    ),
  );
}import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/company/company_settings_model.dart';
import '../cotizacion_models.dart';

final PdfColor _pageBackground = PdfColor.fromHex('#FFFFFF');
final PdfColor _cardBackground = PdfColor.fromHex('#FFFFFF');
final PdfColor _lineColor = PdfColor.fromHex('#E7ECF2');
final PdfColor _tableBorderColor = PdfColor.fromHex('#B9C2CF');
final PdfColor _brandDark = PdfColor.fromHex('#243145');
final PdfColor _brandBlue = PdfColor.fromHex('#2F67FF');
final PdfColor _brandBlueStrong = PdfColor.fromHex('#D9E6FF');
final PdfColor _brandNeutralSoft = PdfColor.fromHex('#F8FAFC');
final PdfColor _brandNeutralSurface = PdfColor.fromHex('#F3F5F8');
final PdfColor _textPrimary = PdfColor.fromHex('#1F2430');
final PdfColor _textMuted = PdfColor.fromHex('#687385');
final PdfColor _tableAlt = PdfColor.fromHex('#FAFBFD');

Future<Uint8List> buildCotizacionPdf({
  required CotizacionModel cotizacion,
  CompanySettings? company,
}) async {
  final money = NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$');
  final dateFmt = DateFormat('dd/MM/yyyy h:mm a', 'es_DO');
  final qtyFmt = NumberFormat('#,##0.##', 'es_DO');
  final logoImage = await _resolveCompanyLogo(company);
  final companyName = _fallback(company?.companyName, fallback: 'FULLTECH');
  final quoteCode = _buildQuoteCode(cotizacion.id);
  final customerName = _fallback(
    cotizacion.customerName,
    fallback: 'Cliente no especificado',
  );

  final doc = pw.Document(title: 'Cotizacion', author: companyName);

  doc.addPage(
    pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(26, 26, 26, 22),
        buildBackground: (context) => pw.FullPage(
          ignoreMargins: true,
          child: pw.Container(color: _pageBackground),
        ),
      ),
      header: (context) => _pageHeader(
        company: company,
        logoImage: logoImage,
        cotizacion: cotizacion,
        customerName: customerName,
        quoteCode: quoteCode,
        dateFmt: dateFmt,
        isContinuation: context.pageNumber > 1,
      ),
      footer: (context) => _pageFooter(context.pageNumber, context.pagesCount),
      build: (context) => [
        _detailCard(cotizacion, money, qtyFmt),
        pw.SizedBox(height: 12),
        _bottomSection(cotizacion, money),
      ],
    ),
  );

  return doc.save();
}

pw.Widget _pageHeader({
  required CompanySettings? company,
  required pw.MemoryImage? logoImage,
  required CotizacionModel cotizacion,
  required String customerName,
  required String quoteCode,
  required DateFormat dateFmt,
  required bool isContinuation,
}) {
  final companyName = _fallback(company?.companyName, fallback: 'FULLTECH');
  final rnc = _clean(company?.rnc);
  final phone = _clean(company?.phone);
  final address = _clean(company?.address);
  final sellerName = _fallback(
    cotizacion.createdByUserName,
    fallback: 'Equipo comercial',
  );
  final customerPhone = _fallback(
    cotizacion.customerPhone,
    fallback: 'No registrado',
  );
  final taxLabel = cotizacion.includeItbis
      ? '${(cotizacion.itbisRate * 100).toStringAsFixed(0)}% ITBIS'
      : '';

  return pw.Container(
    margin: const pw.EdgeInsets.only(bottom: 14),
    padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: pw.BoxDecoration(
      color: _cardBackground,
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(14)),
      border: pw.Border.all(color: _lineColor),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(
                    width: 62,
                    height: 62,
                    padding: const pw.EdgeInsets.all(8),
                    decoration: pw.BoxDecoration(
                      color: _brandNeutralSurface,
                      borderRadius: const pw.BorderRadius.all(
                        pw.Radius.circular(12),
                      ),
                      border: pw.Border.all(color: _lineColor),
                    ),
                    child: logoImage != null
                        ? pw.Image(logoImage, fit: pw.BoxFit.contain)
                        : pw.Center(
                            child: pw.Text(
                              companyName.substring(0, 1).toUpperCase(),
                              style: pw.TextStyle(
                                fontSize: 22,
                                fontWeight: pw.FontWeight.bold,
                                color: _brandDark,
                              ),
                            ),
                          ),
                  ),
                  pw.SizedBox(width: 14),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          companyName,
                          style: pw.TextStyle(
                            fontSize: 16.5,
                            fontWeight: pw.FontWeight.bold,
                            color: _brandDark,
                          ),
                        ),
                        if (rnc.isNotEmpty)
                          pw.Padding(
                            padding: const pw.EdgeInsets.only(top: 3),
                            child: pw.Text(
                              'RNC: $rnc',
                              style: pw.TextStyle(
                                fontSize: 8.8,
                                color: _textMuted,
                              ),
                            ),
                          ),
                        if (phone.isNotEmpty)
                          pw.Text(
                            'Tel: $phone',
                            style: pw.TextStyle(
                              fontSize: 8.8,
                              color: _textMuted,
                            ),
                          ),
                        if (address.isNotEmpty)
                          pw.Text(
                            address,
                            style: pw.TextStyle(
                              fontSize: 8.6,
                              color: _textMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(width: 12),
            pw.SizedBox(
              width: 220,
              child: _metaPanel(
                title: 'Cotizacion',
                lines: [
                  quoteCode,
                  dateFmt.format(cotizacion.createdAt),
                  taxLabel,
                ],
              ),
            ),
          ],
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 10),
          child: pw.Container(height: 1, color: _lineColor),
        ),
        _sectionTitle('Informacion de la cotizacion'),
        pw.SizedBox(height: 8),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: _metaPanel(
                title: 'Cliente',
                lines: [customerName, customerPhone],
              ),
            ),
            pw.SizedBox(width: 12),
            pw.Expanded(
              child: _metaPanel(
                title: 'Vendedor que le asistio',
                lines: [sellerName],
              ),
            ),
          ],
        ),
        if (isContinuation) ...[
          pw.SizedBox(height: 6),
          pw.Text(
            'Continuacion de la cotizacion',
            style: pw.TextStyle(
              fontSize: 8.4,
              color: _brandBlue,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ],
    ),
  );
}

pw.Widget _pageFooter(int pageNumber, int totalPages) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(top: 6),
    child: pw.Row(
      children: [
        pw.Text(
          pageNumber > 1
              ? 'Esta pagina continua la cotizacion anterior'
              : 'Documento comercial',
          style: pw.TextStyle(fontSize: 8, color: _textMuted),
        ),
        pw.Spacer(),
        pw.Text(
          'Pagina $pageNumber de $totalPages',
          style: pw.TextStyle(fontSize: 8, color: _textMuted),
        ),
      ],
    ),
  );
}

pw.Widget _detailCard(
  CotizacionModel cotizacion,
  NumberFormat money,
  NumberFormat qtyFmt,
) {
  final rows = <pw.TableRow>[
    pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.black),
      children: [
        _headerCell('Descripcion'),
        _headerCell('Cant.', align: pw.TextAlign.center),
        _headerCell('Unitario', align: pw.TextAlign.right),
        _headerCell('Importe', align: pw.TextAlign.right),
      ],
    ),
  ];

  if (cotizacion.items.isEmpty) {
    rows.add(
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.white),
        children: [
          _bodyCell('No hay items registrados en esta cotizacion.'),
          _bodyCell('-', align: pw.TextAlign.center),
          _bodyCell('-', align: pw.TextAlign.right),
          _bodyCell(money.format(0), align: pw.TextAlign.right),
        ],
      ),
    );
  } else {
    for (var index = 0; index < cotizacion.items.length; index++) {
      final item = cotizacion.items[index];
      rows.add(
        pw.TableRow(
          decoration: pw.BoxDecoration(
            color: index.isEven ? PdfColors.white : _tableAlt,
          ),
          children: [
            _bodyCell(item.nombre.trim()),
            _bodyCell(qtyFmt.format(item.qty), align: pw.TextAlign.center),
            _bodyCell(money.format(item.unitPrice), align: pw.TextAlign.right),
            _bodyCell(
              money.format(item.total),
              align: pw.TextAlign.right,
              bold: true,
            ),
          ],
        ),
      );
    }
  }

  return _card(
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _sectionTitle('Detalle de ventas'),
        pw.SizedBox(height: 10),
        pw.Table(
          border: pw.TableBorder.all(color: _tableBorderColor, width: 0.45),
          columnWidths: {
            0: const pw.FlexColumnWidth(4.9),
            1: const pw.FlexColumnWidth(1.0),
            2: const pw.FlexColumnWidth(1.6),
            3: const pw.FlexColumnWidth(1.7),
          },
          children: rows,
        ),
      ],
    ),
  );
}

pw.Widget _bottomSection(CotizacionModel cotizacion, NumberFormat money) {
  final note = cotizacion.note.trim();

  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        child: note.isEmpty
            ? pw.SizedBox()
            : _card(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _sectionTitle('Nota'),
                    pw.SizedBox(height: 8),
                    pw.Text(
                      note,
                      style: pw.TextStyle(
                        fontSize: 10,
                        color: _textPrimary,
                        lineSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ),
      ),
      if (note.isNotEmpty) pw.SizedBox(width: 12),
      pw.SizedBox(width: 220, child: _totalsCard(cotizacion, money)),
    ],
  );
}

pw.Widget _totalsCard(CotizacionModel cotizacion, NumberFormat money) {
  return _card(
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _sectionTitle('Totales'),
        pw.SizedBox(height: 10),
        _totalLine('Subtotal', money.format(cotizacion.subtotalBeforeDiscount)),
        if (cotizacion.hasDiscount)
          _totalLine(
            'Descuento aplicado',
            '-${money.format(cotizacion.discountAmount)}',
            valueColor: PdfColor.fromHex('#B42318'),
          ),
        if (cotizacion.hasDiscount)
          _totalLine(
            'Subtotal con descuento',
            money.format(cotizacion.subtotal),
          ),
        if (cotizacion.includeItbis)
          _totalLine('ITBIS', money.format(cotizacion.itbisAmount)),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 8),
          child: pw.Container(height: 1, color: _lineColor),
        ),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: pw.BoxDecoration(
            color: _brandNeutralSoft,
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
            border: pw.Border.all(color: _brandBlueStrong),
          ),
          child: pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text(
                  'Total general',
                  style: pw.TextStyle(
                    color: _brandDark,
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.Text(
                money.format(cotizacion.total),
                style: pw.TextStyle(
                  color: _brandBlue,
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
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
      'cotizacion_${dateFmt.format(cotizacion.createdAt)}_${_buildFileToken(cotizacion.id, length: 6, fallback: 'manual')}.pdf';
  await Printing.sharePdf(bytes: bytes, filename: filename);
}

Future<pw.MemoryImage?> _resolveCompanyLogo(CompanySettings? company) async {
  final rawLogo = _clean(company?.logoBase64);
  if (rawLogo.isNotEmpty) {
    try {
      return pw.MemoryImage(base64Decode(rawLogo));
    } catch (_) {}
  }

  try {
    final asset = await rootBundle.load('assets/image/logo.png');
    return pw.MemoryImage(asset.buffer.asUint8List());
  } catch (_) {
    return null;
  }
}

String _buildQuoteCode(String id) {
  final token = _buildFileToken(id, length: 8, fallback: 'MANUAL');
  return 'COT-$token';
}

String _buildFileToken(
  String id, {
  required int length,
  required String fallback,
}) {
  final normalized = id.replaceAll('-', '').trim();
  if (normalized.isEmpty) return fallback;
  return normalized.length > length
      ? normalized.substring(0, length).toUpperCase()
      : normalized.toUpperCase();
}

String _fallback(String? value, {required String fallback}) {
  final cleaned = _clean(value);
  return cleaned.isEmpty ? fallback : cleaned;
}

String _clean(String? value) => (value ?? '').trim();

pw.Widget _card({required pw.Widget child}) {
  return pw.Container(
    padding: const pw.EdgeInsets.all(14),
    decoration: pw.BoxDecoration(
      color: _cardBackground,
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
      border: pw.Border.all(color: _lineColor, width: 0.45),
    ),
    child: child,
  );
}

pw.Widget _sectionTitle(String text) {
  return pw.Text(
    text,
    style: pw.TextStyle(
      fontSize: 11.5,
      color: _brandDark,
      fontWeight: pw.FontWeight.bold,
      letterSpacing: 0.2,
    ),
  );
}

pw.Widget _metaPanel({
  required String title,
  required List<String> lines,
  bool alignRight = false,
}) {
  final visibleLines = lines
      .where((line) => line.trim().isNotEmpty)
      .toList(growable: false);

  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: pw.BoxDecoration(
      color: _brandNeutralSoft,
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(9)),
      border: pw.Border.all(color: _lineColor, width: 0.4),
    ),
    child: pw.Column(
      crossAxisAlignment: alignRight
          ? pw.CrossAxisAlignment.end
          : pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          title.toUpperCase(),
          textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
          style: pw.TextStyle(
            fontSize: 7.8,
            color: _textMuted,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 5),
        for (var index = 0; index < visibleLines.length; index++)
          pw.Padding(
            padding: pw.EdgeInsets.only(
              bottom: index == visibleLines.length - 1 ? 0 : 6,
            ),
            child: _paragraphLine(visibleLines[index], alignRight: alignRight),
          ),
      ],
    ),
  );
}

pw.Widget _paragraphLine(String text, {bool alignRight = false}) {
  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 7),
    decoration: pw.BoxDecoration(
      color: PdfColors.white,
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(7)),
      border: pw.Border.all(color: _lineColor, width: 0.4),
    ),
    child: pw.Text(
      text,
      textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
      style: pw.TextStyle(fontSize: 9.3, color: _textPrimary),
    ),
  );
}

pw.Widget _headerCell(String text, {pw.TextAlign align = pw.TextAlign.left}) {
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: _tableBorderColor, width: 0.45),
    ),
    child: pw.Text(
      text,
      textAlign: align,
      style: pw.TextStyle(
        fontSize: 8.8,
        color: PdfColors.white,
        fontWeight: pw.FontWeight.bold,
      ),
    ),
  );
}

pw.Widget _bodyCell(
  String text, {
  pw.TextAlign align = pw.TextAlign.left,
  bool bold = false,
}) {
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: _tableBorderColor, width: 0.35),
    ),
    child: pw.Text(
      text,
      textAlign: align,
      style: pw.TextStyle(
        fontSize: 9.2,
        color: _textPrimary,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      ),
    ),
  );
}

pw.Widget _totalLine(String label, String value, {PdfColor? valueColor}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 3),
    child: pw.Row(
      children: [
        pw.Expanded(
          child: pw.Text(
            label,
            style: pw.TextStyle(fontSize: 9.2, color: _textPrimary),
          ),
        ),
        pw.Text(
          value,
          style: pw.TextStyle(fontSize: 9.2, color: valueColor ?? _textPrimary),
        ),
      ],
    ),
  );
}
