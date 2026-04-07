import 'dart:convert';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/company/company_settings_model.dart';
import '../document_flow_models.dart';

final PdfColor _pageBackground = PdfColor.fromHex('#FFFFFF');
final PdfColor _cardBackground = PdfColor.fromHex('#FFFFFF');
final PdfColor _lineColor = PdfColor.fromHex('#E5EAF1');
final PdfColor _brandDark = PdfColor.fromHex('#243145');
final PdfColor _brandGold = PdfColor.fromHex('#B78A3D');
final PdfColor _textPrimary = PdfColor.fromHex('#1F2430');
final PdfColor _textMuted = PdfColor.fromHex('#6B7484');
final PdfColor _tableAlt = PdfColor.fromHex('#FAFBFD');

class DocumentFlowWarrantyPdfItem {
  final String product;
  final String duration;

  const DocumentFlowWarrantyPdfItem({
    required this.product,
    required this.duration,
  });
}

Future<Uint8List> buildDocumentFlowWarrantyPdf({
  required OrderDocumentFlowModel flow,
  required String title,
  required String serviceType,
  required String serviceWarrantyDuration,
  required String productWarrantyDuration,
  required List<DocumentFlowWarrantyPdfItem> items,
  required String coverage,
  required List<String> policyLines,
  CompanySettings? company,
}) async {
  final pdfTheme = pw.ThemeData.withFont(
    base: pw.Font.helvetica(),
    bold: pw.Font.helveticaBold(),
    italic: pw.Font.helveticaOblique(),
    boldItalic: pw.Font.helveticaBoldOblique(),
  );
  final dateFmt = DateFormat('dd/MM/yyyy', 'es_DO');
  final companyName = _fallback(company?.companyName, fallback: 'FULLTECH');
  final logoImage = _decodeLogo(company?.logoBase64);
  final issueDate = _resolveIssueDate(flow, dateFmt);
  final clientName = _fallback(
    flow.warrantyDraft.clientName,
    fallback: flow.order.client.nombre,
  );
  final clientPhone = _clean(flow.order.client.telefono);
  final clientAddress = _clean(flow.order.client.direccion);
  final orderCode = _shortCode(flow.order.id);
  final quotationCode = _shortCodeOrEmpty(flow.order.quotationId ?? '');
  final category = _clean(flow.order.category);
  final visiblePolicies = policyLines
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
  final standardClauses = visiblePolicies
      .where((item) => !_looksLikeExclusion(item))
      .toList(growable: false);
  final exclusionClauses = visiblePolicies
      .where(_looksLikeExclusion)
      .map(_stripExclusionPrefix)
      .toList(growable: false);
  final claimRequirements = <String>[
    'Presentar esta carta de garantia junto con la factura, cotizacion u otro comprobante comercial emitido por $companyName.',
    'Permitir la evaluacion tecnica del equipo, instalacion o servicio antes de exigir reparacion, sustitucion o ajuste.',
    'Notificar la incidencia dentro del periodo de vigencia indicado en este documento y facilitar informacion real sobre la falla reportada.',
    'No intervenir, desmontar ni permitir reparaciones por terceros antes de la revision autorizada por $companyName.',
  ];
  final processSteps = <String>[
    'La reclamacion sera recibida y registrada con los datos del cliente, numero de orden y descripcion de la incidencia.',
    'El personal tecnico verificara si la falla corresponde a defectos de instalacion, mano de obra o elementos cubiertos por esta carta.',
    'Si procede la garantia, $companyName definira la medida correctiva aplicable: reparacion, ajuste, reemplazo parcial o una solucion tecnica equivalente.',
    'Si la falla no esta cubierta, se entregara al cliente un diagnostico con la causa detectada y, de ser necesario, una propuesta de servicio adicional.',
  ];
  final legalNotice =
      'Esta carta se emite como constancia contractual y comercial de la garantia convenida entre $companyName y $clientName, vinculada a la orden y a los documentos comerciales del servicio. Su aplicacion debe interpretarse junto con la factura, la cotizacion aprobada y la verificacion tecnica correspondiente, sin perjuicio de los derechos y obligaciones previstos por la normativa vigente de la Republica Dominicana.';
  final introduction =
      'Por medio de la presente, $companyName certifica que el servicio de $serviceType y los productos descritos a continuacion fueron entregados al cliente $clientName con la cobertura y vigencia detalladas en esta carta de garantia. Este documento establece las condiciones de reclamacion, las exclusiones aplicables y las obligaciones minimas de ambas partes para la atencion de cualquier incidencia dentro del plazo otorgado.';

  final rows = <pw.TableRow>[
    pw.TableRow(
      decoration: pw.BoxDecoration(color: _brandDark),
      children: [
        _headerCell('Elemento'),
        _headerCell('Cobertura', align: pw.TextAlign.center),
        _headerCell('Tiempo de garantia', align: pw.TextAlign.right),
      ],
    ),
    pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.white),
      children: [
        _bodyCell('Servicio realizado'),
        _bodyCell(serviceType, align: pw.TextAlign.center),
        _bodyCell(
          serviceWarrantyDuration,
          align: pw.TextAlign.right,
          bold: true,
        ),
      ],
    ),
  ];

  for (var index = 0; index < items.length; index++) {
    final item = items[index];
    rows.add(
      pw.TableRow(
        decoration: pw.BoxDecoration(
          color: index.isEven ? _tableAlt : PdfColors.white,
        ),
        children: [
          _bodyCell(item.product),
          _bodyCell('Producto', align: pw.TextAlign.center),
          _bodyCell(item.duration, align: pw.TextAlign.right, bold: true),
        ],
      ),
    );
  }

  final doc = pw.Document(title: title, author: companyName);

  doc.addPage(
    pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        theme: pdfTheme,
        margin: const pw.EdgeInsets.fromLTRB(22, 20, 22, 18),
        buildBackground: (context) => pw.FullPage(
          ignoreMargins: true,
          child: pw.Container(color: _pageBackground),
        ),
      ),
      build: (context) => [
        pw.Container(
          padding: const pw.EdgeInsets.all(14),
          decoration: pw.BoxDecoration(
            color: _cardBackground,
            border: pw.Border.all(color: _lineColor),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _headerRow(
                companyName: companyName,
                logoImage: logoImage,
                rnc: _clean(company?.rnc),
                phone: _clean(company?.phone),
                address: _clean(company?.address),
                title: title,
                issueDate: issueDate,
              ),
              pw.SizedBox(height: 10),
              pw.Container(height: 1, color: _lineColor),
              pw.SizedBox(height: 10),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: _factsBlock(
                      rows: [
                        _FactRow('Cliente', clientName),
                        _FactRow('Telefono', clientPhone),
                        _FactRow('Direccion', clientAddress),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 10),
                  pw.Expanded(
                    child: _factsBlock(
                      rows: [
                        _FactRow('Orden', orderCode),
                        _FactRow('Cotizacion', quotationCode),
                        _FactRow('Servicio', serviceType),
                        _FactRow('Categoria', category),
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 12),
              _sectionCard(
                title: 'Declaracion contractual de garantia',
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _paragraph(introduction),
                    pw.SizedBox(height: 6),
                    _paragraph(legalNotice),
                  ],
                ),
              ),
              pw.SizedBox(height: 12),
              _sectionCard(
                title: 'Alcance y vigencia de la cobertura',
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _paragraph(
                      coverage.trim().isEmpty
                          ? 'El alcance de esta garantia se detalla en la tabla inferior. En dicha tabla se especifica cada producto o servicio cubierto y el tiempo de garantia aplicable a cada uno.'
                          : coverage.trim(),
                    ),
                    pw.SizedBox(height: 6),
                    _bulletList([
                      'La garantia del servicio tiene una vigencia de $serviceWarrantyDuration, contada a partir de la entrega o cierre operativo de la orden.',
                      'La garantia general de productos instalados tiene una vigencia de $productWarrantyDuration, salvo que en la tabla siguiente se indique un periodo distinto para un producto especifico.',
                      'El detalle vinculante de cobertura se muestra abajo, donde se identifica cada producto o servicio amparado y su tiempo de garantia.',
                      ...standardClauses,
                    ]),
                  ],
                ),
              ),
              pw.SizedBox(height: 12),
              _sectionCard(
                title: 'Productos amparados y tiempo de garantia',
                child: pw.Table(
                  border: pw.TableBorder(
                    horizontalInside: pw.BorderSide(
                      color: _lineColor,
                      width: 0.3,
                    ),
                    top: pw.BorderSide(color: _lineColor, width: 0.3),
                    bottom: pw.BorderSide(color: _lineColor, width: 0.3),
                  ),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(4.8),
                    1: const pw.FlexColumnWidth(1.6),
                    2: const pw.FlexColumnWidth(2.0),
                  },
                  children: rows,
                ),
              ),
              pw.SizedBox(height: 12),
              _sectionCard(
                title: 'Requisitos para reclamar la garantia',
                child: _bulletList(claimRequirements),
              ),
              pw.SizedBox(height: 12),
              _sectionCard(
                title: 'Exclusiones y causas de perdida de cobertura',
                child: _bulletList(
                  exclusionClauses.isEmpty
                      ? <String>[
                          'La garantia no cubre danos derivados de alto voltaje, bajo voltaje, picos electricos, cortocircuitos, descargas atmosfericas o inestabilidad del suministro electrico.',
                          'La garantia no cubre golpes, caidas, humedad, inundaciones, incendio, corrosion, agentes quimicos, suciedad extrema o exposicion a condiciones ambientales inadecuadas.',
                          'La garantia no cubre maltrato, uso indebido, uso contrario a las recomendaciones tecnicas, sobrecarga, negligencia, manipulacion o mantenimiento incorrecto.',
                          'La garantia no cubre aperturas, reparaciones, modificaciones o intervenciones realizadas por terceros no autorizados por la empresa.',
                          'La garantia no cubre piezas consumibles, configuraciones adicionales, accesorios no facturados, software ajeno, ni ampliaciones posteriores al servicio originalmente contratado.',
                          'La garantia no cubre danos ocasionados por accidentes, robo, vandalismo, transporte incorrecto, fuerza mayor o hechos atribuibles exclusivamente al cliente o a terceros.',
                        ]
                      : exclusionClauses,
                ),
              ),
              pw.SizedBox(height: 12),
              _sectionCard(
                title: 'Procedimiento de evaluacion y respuesta',
                child: _bulletList(processSteps),
              ),
              pw.SizedBox(height: 12),
              _sectionCard(
                title: 'Aceptacion y presentacion obligatoria del documento',
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _paragraph(
                      'El cliente reconoce que ha recibido esta carta, que conoce su contenido y que debera presentarla al momento de reclamar la garantia. La falta de presentacion de este documento o de la factura asociada puede retrasar la validacion hasta que se confirme la titularidad y trazabilidad del servicio o producto reclamado.',
                    ),
                    pw.SizedBox(height: 6),
                    _paragraph(
                      'Esta carta forma parte del expediente comercial de la operacion y sirve como soporte documental de las condiciones de garantia ofrecidas por la empresa para la orden identificada en el presente documento.',
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 18),
              pw.Row(
                children: [
                  pw.Expanded(
                    child: _signatureBlock(
                      'Recibido y aceptado por el cliente',
                      clientName,
                    ),
                  ),
                  pw.SizedBox(width: 24),
                  pw.Expanded(
                    child: _signatureBlock(
                      'Firma autorizada de la empresa',
                      companyName,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );

  return doc.save();
}

pw.Widget _headerRow({
  required String companyName,
  required pw.MemoryImage? logoImage,
  required String rnc,
  required String phone,
  required String address,
  required String title,
  required String issueDate,
}) {
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.center,
    children: [
      pw.Expanded(
        flex: 6,
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Container(
              width: 44,
              height: 44,
              padding: const pw.EdgeInsets.all(5),
              decoration: pw.BoxDecoration(
                color: _cardBackground,
                border: pw.Border.all(color: _lineColor),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
              ),
              child: logoImage != null
                  ? pw.Image(logoImage, fit: pw.BoxFit.contain)
                  : pw.Center(
                      child: pw.Text(
                        companyName.substring(0, 1).toUpperCase(),
                        style: pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold,
                          color: _brandDark,
                        ),
                      ),
                    ),
            ),
            pw.SizedBox(width: 10),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    companyName,
                    style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                      color: _brandDark,
                    ),
                  ),
                  if (rnc.isNotEmpty)
                    pw.Text(
                      'RNC: $rnc',
                      style: pw.TextStyle(fontSize: 8, color: _textMuted),
                    ),
                  if (phone.isNotEmpty)
                    pw.Text(
                      'Tel: $phone',
                      style: pw.TextStyle(fontSize: 8, color: _textMuted),
                    ),
                  if (address.isNotEmpty)
                    pw.Text(
                      address,
                      style: pw.TextStyle(fontSize: 7.8, color: _textMuted),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      pw.SizedBox(width: 10),
      pw.Expanded(
        flex: 5,
        child: pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: pw.BoxDecoration(
            color: _cardBackground,
            border: pw.Border.all(color: _lineColor),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                title,
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  color: _brandDark,
                ),
              ),
              pw.SizedBox(height: 5),
              _inlineFactRow('Fecha', issueDate),
            ],
          ),
        ),
      ),
    ],
  );
}

pw.Widget _factsBlock({required List<_FactRow> rows}) {
  final visibleRows = rows
      .where((row) => row.value.trim().isNotEmpty)
      .toList(growable: false);
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: pw.BoxDecoration(
      color: _cardBackground,
      border: pw.Border.all(color: _lineColor),
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < visibleRows.length; index++) ...[
          if (index > 0) pw.SizedBox(height: 4),
          _inlineFactRow(visibleRows[index].label, visibleRows[index].value),
        ],
      ],
    ),
  );
}

pw.Widget _sectionCard({required String title, required pw.Widget child}) {
  return pw.Container(
    padding: const pw.EdgeInsets.all(10),
    decoration: pw.BoxDecoration(
      color: _cardBackground,
      border: pw.Border.all(color: _lineColor),
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(
            fontSize: 8.4,
            fontWeight: pw.FontWeight.bold,
            color: _brandGold,
            letterSpacing: 0.5,
          ),
        ),
        pw.SizedBox(height: 6),
        child,
      ],
    ),
  );
}

pw.Widget _paragraph(String text) {
  final value = text.trim();
  if (value.isEmpty) {
    return pw.SizedBox();
  }

  return pw.Text(
    value,
    style: pw.TextStyle(fontSize: 8.5, color: _textPrimary, lineSpacing: 1.5),
    textAlign: pw.TextAlign.justify,
  );
}

pw.Widget _bulletList(List<String> items) {
  final visibleItems = items
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      for (var index = 0; index < visibleItems.length; index++)
        pw.Padding(
          padding: pw.EdgeInsets.only(
            bottom: index == visibleItems.length - 1 ? 0 : 4,
          ),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                '* ',
                style: pw.TextStyle(
                  fontSize: 9,
                  color: _textPrimary,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Expanded(
                child: pw.Text(
                  visibleItems[index],
                  style: pw.TextStyle(
                    fontSize: 8.3,
                    color: _textPrimary,
                    lineSpacing: 1.4,
                  ),
                  textAlign: pw.TextAlign.justify,
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

pw.Widget _signatureBlock(String label, String value) {
  return pw.Column(
    children: [
      pw.Container(height: 1, color: _lineColor),
      pw.SizedBox(height: 6),
      pw.Text(
        label,
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight: pw.FontWeight.bold,
          color: _textMuted,
        ),
      ),
      pw.SizedBox(height: 4),
      pw.Text(
        value,
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(fontSize: 9, color: _textPrimary),
      ),
    ],
  );
}

pw.Widget _inlineFactRow(String label, String value) {
  final cleanValue = value.trim();
  if (cleanValue.isEmpty) {
    return pw.SizedBox();
  }

  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.SizedBox(
        width: 60,
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
          style: pw.TextStyle(fontSize: 8, color: _textPrimary),
        ),
      ),
    ],
  );
}

pw.Widget _headerCell(String text, {pw.TextAlign align = pw.TextAlign.left}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
    child: pw.Text(
      text,
      textAlign: align,
      style: pw.TextStyle(
        fontSize: 8,
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
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
    child: pw.Text(
      text,
      textAlign: align,
      style: pw.TextStyle(
        fontSize: 7.9,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        color: _textPrimary,
      ),
    ),
  );
}

String _resolveIssueDate(OrderDocumentFlowModel flow, DateFormat dateFmt) {
  final orderDate =
      flow.order.finalizedAt ?? flow.order.updatedAt ?? flow.order.createdAt;
  if (orderDate == null) {
    return '';
  }
  return dateFmt.format(orderDate.toLocal());
}

String _fallback(String? value, {required String fallback}) {
  final normalized = (value ?? '').trim();
  return normalized.isEmpty ? fallback : normalized;
}

String _clean(String? value) => (value ?? '').trim();

String _shortCode(String raw) {
  final normalized = raw.trim().replaceAll('-', '');
  if (normalized.isEmpty) return '';
  if (normalized.length <= 8) return normalized.toUpperCase();
  return normalized.substring(0, 8).toUpperCase();
}

String _shortCodeOrEmpty(String raw) {
  final normalized = raw.trim();
  if (normalized.isEmpty) return '';
  return _shortCode(normalized);
}

bool _looksLikeExclusion(String value) {
  final normalized = value.trim().toLowerCase();
  return normalized.startsWith('no cubre:') ||
      normalized.contains('exclusion') ||
      normalized.contains('no aplica');
}

String _stripExclusionPrefix(String value) {
  final normalized = value.trim();
  if (normalized.toLowerCase().startsWith('no cubre:')) {
    return normalized.substring('no cubre:'.length).trim();
  }
  return normalized;
}

class _FactRow {
  final String label;
  final String value;

  const _FactRow(this.label, this.value);
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
