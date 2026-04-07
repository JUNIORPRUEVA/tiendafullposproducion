import 'dart:convert';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/company/company_settings_model.dart';
import '../document_flow_models.dart';

final PdfColor _pageBackground = PdfColor.fromHex('#FFFFFF');
final PdfColor _cardBackground = PdfColor.fromHex('#FFFFFF');
final PdfColor _lineColor = PdfColor.fromHex('#E7ECF2');
final PdfColor _brandDark = PdfColor.fromHex('#243145');
final PdfColor _brandGold = PdfColor.fromHex('#B78A3D');
final PdfColor _brandNeutralSurface = PdfColor.fromHex('#F3F5F8');
final PdfColor _brandNeutralSoft = PdfColor.fromHex('#FAFBFE');
final PdfColor _textPrimary = PdfColor.fromHex('#1F2430');
final PdfColor _textMuted = PdfColor.fromHex('#687385');
final PdfColor _tableAlt = PdfColor.fromHex('#FAFBFD');

Future<Uint8List> buildDocumentFlowInvoicePdf({
  required OrderDocumentFlowModel flow,
  required String currency,
  required List<DocumentFlowInvoiceItem> items,
  required double tax,
  required double subtotal,
  required double total,
  required String notes,
  CompanySettings? company,
}) async {
  final symbol = _currencySymbol(currency);
  final money = NumberFormat.currency(locale: 'es_DO', symbol: symbol);
  final qtyFmt = NumberFormat('#,##0.##', 'es_DO');
  final dateFmt = DateFormat('dd/MM/yyyy h:mm a', 'es_DO');
  final invoiceNumber = _buildInvoiceNumber(flow.order.id);
  final logoImage = _decodeLogo(company?.logoBase64);
  final companyName = _fallback(company?.companyName, fallback: 'FULLTECH');
  final clientName = _fallback(
    flow.invoiceDraft.clientName,
    fallback: flow.order.client.nombre,
  );
  final clientPhone = _fallback(
    flow.invoiceDraft.clientPhone,
    fallback: flow.order.client.telefono,
  );
  final clientAddress = _firstNonEmpty([flow.order.client.direccion]);

  final doc = pw.Document(title: 'Factura de servicio', author: companyName);

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
      footer: (context) => pw.Row(
        children: [
          pw.Text(
            'Factura de servicio',
            style: pw.TextStyle(fontSize: 8, color: _textMuted),
          ),
          pw.Spacer(),
          pw.Text(
            'Pagina ${context.pageNumber} de ${context.pagesCount}',
            style: pw.TextStyle(fontSize: 8, color: _textMuted),
          ),
        ],
      ),
      build: (context) => [
        _header(
          flow: flow,
          company: company,
          companyName: companyName,
          logoImage: logoImage,
          invoiceNumber: invoiceNumber,
          clientName: clientName,
          clientPhone: clientPhone,
          clientAddress: clientAddress,
          currency: currency,
          dateFmt: dateFmt,
        ),
        pw.SizedBox(height: 12),
        _itemsCard(items, money, qtyFmt),
        pw.SizedBox(height: 12),
        _bottomSection(
          notes: notes,
          money: money,
          subtotal: subtotal,
          tax: tax,
          total: total,
        ),
      ],
    ),
  );

  return doc.save();
}

pw.Widget _header({
  required OrderDocumentFlowModel flow,
  required CompanySettings? company,
  required String companyName,
  required pw.MemoryImage? logoImage,
  required String invoiceNumber,
  required String clientName,
  required String clientPhone,
  required String clientAddress,
  required String currency,
  required DateFormat dateFmt,
}) {
  final rnc = _clean(company?.rnc);
  final phone = _clean(company?.phone);
  final address = _clean(company?.address);
  final orderDate =
      flow.order.finalizedAt ?? flow.order.updatedAt ?? flow.order.createdAt;
  final orderCode = flow.order.id;
  final quotationCode = (flow.order.quotationId ?? '').trim();
  final category = _clean(flow.order.category);
  final serviceType = _clean(flow.order.serviceType);
  final orderStatus = _clean(flow.order.status);
  final issueDate = orderDate != null
      ? dateFmt.format(orderDate.toLocal())
      : '';

  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 18, vertical: 18),
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
                    width: 64,
                    height: 64,
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
                          'FACTURA DE SERVICIO',
                          style: pw.TextStyle(
                            fontSize: 8.4,
                            fontWeight: pw.FontWeight.bold,
                            color: _brandGold,
                            letterSpacing: 1.1,
                          ),
                        ),
                        pw.SizedBox(height: 6),
                        pw.Text(
                          companyName,
                          style: pw.TextStyle(
                            fontSize: 18.5,
                            fontWeight: pw.FontWeight.bold,
                            color: _brandDark,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        if (rnc.isNotEmpty)
                          pw.Text(
                            'RNC: $rnc',
                            style: pw.TextStyle(
                              fontSize: 8.8,
                              color: _textMuted,
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
              child: _heroMetaPanel(
                eyebrow: 'Factura final',
                title: invoiceNumber,
                accent: 'Documento oficial',
                rows: [
                  _InfoRow('Fecha de emision', issueDate),
                  _InfoRow('Moneda', currency),
                  _InfoRow('Estado', orderStatus),
                ],
              ),
            ),
          ],
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 14),
          child: pw.Container(height: 1, color: _lineColor),
        ),
        _infoGrid(
          panels: [
            _metaPanel(
              title: 'Cliente',
              rows: [
                _InfoRow('Nombre', clientName),
                _InfoRow('Telefono', clientPhone),
                _InfoRow('Direccion', clientAddress),
              ],
            ),
            _metaPanel(
              title: 'Referencia operativa',
              rows: [
                _InfoRow('Orden de servicio', _shortCode(orderCode)),
                _InfoRow('Cotizacion', _shortCodeOrEmpty(quotationCode)),
                _InfoRow('Categoria', category),
                _InfoRow('Servicio', serviceType),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 14),
        _executiveStrip(
          entries: [
            _StripEntry(
              'Documento',
              invoiceNumber,
              issueDate.isEmpty ? currency : issueDate,
            ),
            _StripEntry(
              'Cliente',
              clientName,
              _firstNonEmpty([clientPhone, clientAddress]),
            ),
            _StripEntry(
              'Orden',
              _shortCode(orderCode),
              _firstNonEmpty([serviceType, category]),
            ),
          ],
        ),
      ],
    ),
  );
}

pw.Widget _itemsCard(
  List<DocumentFlowInvoiceItem> items,
  NumberFormat money,
  NumberFormat qtyFmt,
) {
  final rows = <pw.TableRow>[
    pw.TableRow(
      decoration: pw.BoxDecoration(color: _brandDark),
      children: [
        _headerCell('Descripcion'),
        _headerCell('Cant.', align: pw.TextAlign.center),
        _headerCell('Unitario', align: pw.TextAlign.right),
        _headerCell('Importe', align: pw.TextAlign.right),
      ],
    ),
  ];

  if (items.isEmpty) {
    rows.add(
      pw.TableRow(
        children: [
          _bodyCell('No hay conceptos registrados en esta factura.'),
          _bodyCell('-', align: pw.TextAlign.center),
          _bodyCell('-', align: pw.TextAlign.right),
          _bodyCell(money.format(0), align: pw.TextAlign.right),
        ],
      ),
    );
  } else {
    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      rows.add(
        pw.TableRow(
          decoration: pw.BoxDecoration(
            color: index.isEven ? PdfColors.white : _tableAlt,
          ),
          children: [
            _bodyCell(item.description.trim()),
            _bodyCell(qtyFmt.format(item.qty), align: pw.TextAlign.center),
            _bodyCell(money.format(item.unitPrice), align: pw.TextAlign.right),
            _bodyCell(
              money.format(item.lineTotal),
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
        _sectionTitle('Detalle facturado'),
        pw.SizedBox(height: 4),
        pw.Text(
          'Detalle economico de los conceptos aprobados para facturacion.',
          style: pw.TextStyle(fontSize: 8.8, color: _textMuted),
        ),
        pw.SizedBox(height: 10),
        pw.Table(
          border: pw.TableBorder(
            horizontalInside: pw.BorderSide(color: _lineColor, width: 0.35),
            top: pw.BorderSide(color: _lineColor, width: 0.35),
            bottom: pw.BorderSide(color: _lineColor, width: 0.35),
          ),
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

pw.Widget _bottomSection({
  required String notes,
  required NumberFormat money,
  required double subtotal,
  required double tax,
  required double total,
}) {
  final cleanNotes = notes.trim();
  final hasTax = tax.abs() > 0.0001;

  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        child: cleanNotes.isEmpty
            ? pw.SizedBox()
            : _notesCard(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _sectionTitle('Observaciones'),
                    pw.SizedBox(height: 6),
                    pw.Text(
                      cleanNotes,
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
      if (cleanNotes.isNotEmpty) pw.SizedBox(width: 12),
      pw.SizedBox(
        width: 220,
        child: _card(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _sectionTitle('Totales'),
              pw.SizedBox(height: 4),
              pw.Text(
                'Cierre economico del documento.',
                style: pw.TextStyle(fontSize: 8.8, color: _textMuted),
              ),
              pw.SizedBox(height: 10),
              _totalLine('Subtotal', money.format(subtotal)),
              if (hasTax) _totalLine('Impuesto', money.format(tax)),
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 8),
                child: pw.Container(height: 1, color: _lineColor),
              ),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
                decoration: pw.BoxDecoration(
                  color: _brandDark,
                  borderRadius: const pw.BorderRadius.all(
                    pw.Radius.circular(12),
                  ),
                  border: pw.Border.all(color: _brandDark),
                ),
                child: _totalLine(
                  'Total general',
                  money.format(total),
                  highlight: true,
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

pw.Widget _card({required pw.Widget child}) {
  return pw.Container(
    padding: const pw.EdgeInsets.all(14),
    decoration: pw.BoxDecoration(
      color: _cardBackground,
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(14)),
      border: pw.Border.all(color: _lineColor),
    ),
    child: child,
  );
}

pw.Widget _notesCard({required pw.Widget child}) {
  return pw.Container(
    padding: const pw.EdgeInsets.all(14),
    decoration: pw.BoxDecoration(
      color: _brandNeutralSoft,
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(14)),
      border: pw.Border.all(color: _lineColor),
    ),
    child: child,
  );
}

pw.Widget _sectionTitle(String title) {
  return pw.Text(
    title,
    style: pw.TextStyle(
      fontSize: 11.5,
      fontWeight: pw.FontWeight.bold,
      color: _brandDark,
    ),
  );
}

pw.Widget _metaPanel({required String title, required List<_InfoRow> rows}) {
  final visibleRows = rows
      .where((row) => row.value.trim().isNotEmpty)
      .toList(growable: false);

  if (visibleRows.isEmpty) {
    return pw.SizedBox();
  }

  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: pw.BoxDecoration(
      color: _brandNeutralSoft,
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
      border: pw.Border.all(color: _lineColor),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          title.toUpperCase(),
          style: pw.TextStyle(
            fontSize: 8,
            fontWeight: pw.FontWeight.bold,
            color: _textMuted,
          ),
        ),
        for (final row in visibleRows)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 7),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  row.label,
                  style: pw.TextStyle(fontSize: 7.8, color: _textMuted),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  row.value,
                  style: pw.TextStyle(
                    fontSize: 9.5,
                    fontWeight: pw.FontWeight.normal,
                    color: _textPrimary,
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

pw.Widget _heroMetaPanel({
  required String eyebrow,
  required String title,
  required String accent,
  required List<_InfoRow> rows,
}) {
  final visibleRows = rows
      .where((row) => row.value.trim().isNotEmpty)
      .toList(growable: false);

  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    decoration: pw.BoxDecoration(
      color: _cardBackground,
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(14)),
      border: pw.Border.all(color: _lineColor),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          children: [
            pw.Expanded(
              child: pw.Text(
                eyebrow.toUpperCase(),
                style: pw.TextStyle(
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                  color: _textMuted,
                ),
              ),
            ),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 4,
              ),
              decoration: pw.BoxDecoration(
                color: _brandNeutralSurface,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
                border: pw.Border.all(color: _lineColor),
              ),
              child: pw.Text(
                accent,
                style: pw.TextStyle(
                  fontSize: 7.5,
                  fontWeight: pw.FontWeight.bold,
                  color: _brandGold,
                ),
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Text(
          title,
          style: pw.TextStyle(
            fontSize: 14,
            fontWeight: pw.FontWeight.bold,
            color: _brandDark,
          ),
        ),
        if (visibleRows.isNotEmpty) ...[
          pw.SizedBox(height: 10),
          for (final row in visibleRows)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 4),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Text(
                      row.label,
                      style: pw.TextStyle(fontSize: 8, color: _textMuted),
                    ),
                  ),
                  pw.SizedBox(width: 8),
                  pw.Flexible(
                    child: pw.Text(
                      row.value,
                      textAlign: pw.TextAlign.right,
                      style: pw.TextStyle(
                        fontSize: 8.6,
                        fontWeight: pw.FontWeight.bold,
                        color: _brandDark,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    ),
  );
}

pw.Widget _infoGrid({required List<pw.Widget> panels}) {
  final visiblePanels = panels
      .where((panel) => panel is! pw.SizedBox)
      .toList(growable: false);
  if (visiblePanels.isEmpty) {
    return pw.SizedBox();
  }
  if (visiblePanels.length == 1) {
    return visiblePanels.first;
  }

  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(child: visiblePanels[0]),
      pw.SizedBox(width: 12),
      pw.Expanded(child: visiblePanels[1]),
    ],
  );
}

pw.Widget _executiveStrip({required List<_StripEntry> entries}) {
  final visibleEntries = entries
      .where(
        (entry) =>
            entry.value.trim().isNotEmpty || entry.detail.trim().isNotEmpty,
      )
      .toList(growable: false);
  if (visibleEntries.isEmpty) {
    return pw.SizedBox();
  }

  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: pw.BoxDecoration(
      color: _brandNeutralSoft,
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
      border: pw.Border.all(color: _lineColor),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < visibleEntries.length; index++) ...[
          if (index > 0)
            pw.Container(
              width: 1,
              height: 34,
              margin: const pw.EdgeInsets.symmetric(horizontal: 12),
              color: _lineColor,
            ),
          pw.Expanded(child: _executiveStripItem(visibleEntries[index])),
        ],
      ],
    ),
  );
}

pw.Widget _executiveStripItem(_StripEntry entry) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        entry.label.toUpperCase(),
        style: pw.TextStyle(
          fontSize: 7.6,
          fontWeight: pw.FontWeight.bold,
          color: _textMuted,
        ),
      ),
      if (entry.value.trim().isNotEmpty) ...[
        pw.SizedBox(height: 4),
        pw.Text(
          entry.value,
          style: pw.TextStyle(
            fontSize: 10.2,
            fontWeight: pw.FontWeight.bold,
            color: _brandDark,
          ),
        ),
      ],
      if (entry.detail.trim().isNotEmpty) ...[
        pw.SizedBox(height: 2),
        pw.Text(
          entry.detail,
          style: pw.TextStyle(fontSize: 8.3, color: _textMuted),
        ),
      ],
    ],
  );
}

pw.Widget _headerCell(String text, {pw.TextAlign align = pw.TextAlign.left}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
    child: pw.Text(
      text,
      textAlign: align,
      style: pw.TextStyle(
        fontSize: 9.2,
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.white,
      ),
    ),
  );
}

pw.Widget _bodyCell(
  String text, {
  pw.TextAlign align = pw.TextAlign.left,
  bool bold = false,
}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
    child: pw.Text(
      text,
      textAlign: align,
      style: pw.TextStyle(
        fontSize: 9,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        color: _textPrimary,
      ),
    ),
  );
}

pw.Widget _totalLine(String label, String value, {bool highlight = false}) {
  return pw.Row(
    children: [
      pw.Expanded(
        child: pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: highlight ? 10.6 : 9.6,
            fontWeight: highlight ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: highlight ? _brandDark : _textPrimary,
          ),
        ),
      ),
      pw.Text(
        value,
        style: pw.TextStyle(
          fontSize: highlight ? 11 : 9.8,
          fontWeight: highlight ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: highlight ? PdfColors.white : _textPrimary,
        ),
      ),
    ],
  );
}

String _currencySymbol(String currency) {
  switch (currency.trim().toUpperCase()) {
    case 'DOP':
    case 'RD\$':
      return 'RD\$';
    case 'USD':
      return 'US\$';
    case 'EUR':
      return '€';
    default:
      return '${currency.trim()} ';
  }
}

String _buildInvoiceNumber(String orderId) {
  return 'FACT-${orderId.replaceAll('-', '').substring(0, 8).toUpperCase()}';
}

String _shortCode(String raw) {
  final normalized = raw.trim().replaceAll('-', '');
  if (normalized.length <= 8) return normalized.toUpperCase();
  return normalized.substring(0, 8).toUpperCase();
}

String _shortCodeOrEmpty(String raw) {
  final normalized = raw.trim();
  if (normalized.isEmpty) return '';
  return _shortCode(normalized);
}

String _fallback(String? value, {required String fallback}) {
  final normalized = (value ?? '').trim();
  return normalized.isEmpty ? fallback : normalized;
}

String _clean(String? value) => (value ?? '').trim();

String _firstNonEmpty(List<String?> values) {
  for (final value in values) {
    final clean = (value ?? '').trim();
    if (clean.isNotEmpty) {
      return clean;
    }
  }
  return '';
}

class _InfoRow {
  final String label;
  final String value;

  const _InfoRow(this.label, this.value);
}

class _StripEntry {
  final String label;
  final String value;
  final String detail;

  const _StripEntry(this.label, this.value, this.detail);
}

pw.MemoryImage? _decodeLogo(String? raw) {
  final normalized = (raw ?? '').trim();
  if (normalized.isEmpty) return null;
  final clean = normalized.contains(',')
      ? normalized.split(',').last
      : normalized;
  try {
    return pw.MemoryImage(base64Decode(clean));
  } catch (_) {
    return null;
  }
}
