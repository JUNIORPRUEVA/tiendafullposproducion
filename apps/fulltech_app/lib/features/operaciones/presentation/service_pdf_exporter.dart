import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/company/company_settings_model.dart';
import '../../../modules/cotizaciones/cotizacion_models.dart';
import '../operations_models.dart';

class ServicePdfExporter {
  static bool get isSupported {
    if (kIsWeb) return false;

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return true;
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return false;
    }
  }

  static Future<void> share(BuildContext context, ServiceModel service) async {
    if (!isSupported) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Exportar PDF no está disponible en esta plataforma.'),
        ),
      );
      return;
    }

    final bytes = await _buildPdfBytes(service);

    await Printing.sharePdf(
      bytes: bytes,
      filename: 'FULLTECH-${service.id}.pdf',
    );
  }

  static Future<Uint8List> buildServiceDetailPdfBytes(ServiceModel service) {
    return _buildPdfBytes(service);
  }

  static Future<Uint8List> buildInvoicePdfBytes(
    ServiceModel service, {
    CotizacionModel? cotizacion,
    CompanySettings? company,
    Uint8List? clientSignaturePngBytes,
    String? clientSignatureFileId,
    String? clientSignatureFileUrl,
    DateTime? clientSignedAt,
  }) {
    return _buildInvoicePdfBytes(
      service,
      cotizacion: cotizacion,
      company: company,
      clientSignaturePngBytes: clientSignaturePngBytes,
      clientSignatureFileId: clientSignatureFileId,
      clientSignatureFileUrl: clientSignatureFileUrl,
      clientSignedAt: clientSignedAt,
    );
  }

  static Future<Uint8List> buildWarrantyLetterBytes(
    ServiceModel service, {
    CotizacionModel? cotizacion,
    CompanySettings? company,
    Uint8List? clientSignaturePngBytes,
    String? clientSignatureFileId,
    String? clientSignatureFileUrl,
    DateTime? clientSignedAt,
  }) async {
    final companyName = (company?.companyName ?? 'FULLTECH, SRL').trim();
    final companyRnc = (company?.rnc ?? '133080206').trim();
    final companyPhone = (company?.phone ?? '829-534-4286').trim();

    final customer = service.customerName.trim().isEmpty
        ? 'Cliente'
        : service.customerName.trim();
    final phone = service.customerPhone.trim();
    final address = service.customerAddress.trim();

    final techs = service.assignments
        .map((a) => a.userName.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final serviceDate =
        service.completedAt ?? service.scheduledStart ?? DateTime.now();
    final dfDate = DateFormat('dd/MM/yyyy', 'es');

    final items = cotizacion?.items ?? const <CotizacionItem>[];

    pw.MemoryImage? signatureImage;
    if (clientSignaturePngBytes != null && clientSignaturePngBytes.isNotEmpty) {
      try {
        signatureImage = pw.MemoryImage(clientSignaturePngBytes);
      } catch (_) {
        signatureImage = null;
      }
    }

    final signedAtText = clientSignedAt == null
        ? ''
        : DateFormat('dd/MM/yyyy HH:mm', 'es').format(clientSignedAt);
    final signatureRef = (clientSignatureFileId ?? '').trim().isNotEmpty
        ? (clientSignatureFileId ?? '').trim()
        : (clientSignatureFileUrl ?? '').trim();

    pw.Widget heading(String text) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(top: 12, bottom: 6),
        child: pw.Text(
          text,
          style: pw.TextStyle(
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      );
    }

    pw.Widget bodyText(String text) {
      return pw.Text(
        text,
        style: const pw.TextStyle(fontSize: 10.5, lineSpacing: 2.2),
      );
    }

    pw.Widget bodyLine(String text) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 2),
        child: pw.Text(
          text,
          style: const pw.TextStyle(fontSize: 10.5),
        ),
      );
    }

    pw.Widget spacer([double h = 8]) => pw.SizedBox(height: h);

    final doc = pw.Document(
      title: 'Carta de Garantía de Instalación y Equipos',
      author: companyName,
    );

    final category = service.category.trim().toLowerCase();
    final isCamerasCategory =
        category == 'cameras' || category.contains('camera') || category.contains('camara');

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 40, 36, 44),
        build: (context) {
          return [
            pw.Text(
              'FULLTECH, SRL',
              style: pw.TextStyle(
                fontSize: 16,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            spacer(6),
            bodyLine('Empresa: $companyName'),
            bodyLine('RNC: $companyRnc'),
            bodyLine('Teléfono: $companyPhone'),
            spacer(12),
            pw.Text(
              'CARTA DE GARANTÍA DE INSTALACIÓN Y EQUIPOS',
              style: pw.TextStyle(
                fontSize: 13,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            spacer(10),
            bodyText(
              'Por medio de la presente, FULLTECH, SRL certifica que los equipos y servicios instalados al cliente mencionado a continuación cuentan con garantía bajo las condiciones especificadas en este documento.',
            ),
            heading('INFORMACIÓN DEL CLIENTE'),
            bodyLine('Nombre del cliente: $customer'),
            bodyLine('Teléfono: ${phone.isEmpty ? '—' : phone}'),
            bodyLine('Dirección: ${address.isEmpty ? '—' : address}'),
            spacer(8),
            bodyLine('Número de orden: ${service.orderLabel}'),
            bodyLine('Fecha del servicio: ${dfDate.format(serviceDate)}'),
            heading('EQUIPOS Y PRODUCTOS INSTALADOS'),
            if (items.isEmpty)
              bodyLine('—')
            else
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: items
                    .map(
                      (i) => bodyLine(
                        '${i.qty.toStringAsFixed(i.qty % 1 == 0 ? 0 : 2)} x ${i.nombre}',
                      ),
                    )
                    .toList(growable: false),
              ),
            spacer(6),
            bodyText(
              '(Los productos instalados corresponden a los indicados en la cotización y orden de servicio.)',
            ),
            heading('CONDICIONES DE GARANTÍA'),
            if (isCamerasCategory) ...[
              bodyLine('Sistemas de cámaras de seguridad'),
              spacer(4),
              bodyLine('Cámaras de seguridad: 1 año de garantía'),
              spacer(2),
              bodyLine('DVR / NVR: 1 año de garantía'),
              spacer(2),
              bodyLine('Disco duro: 15 días de garantía'),
              spacer(2),
              bodyLine('Servicio de instalación: 3 meses de garantía'),
            ] else ...[
              bodyLine('Motores de portones y otros servicios'),
              spacer(4),
              bodyLine(
                'Motores para portones eléctricos y otros servicios tecnológicos: 6 meses de garantía',
              ),
            ],
            heading('ALCANCE DE LA GARANTÍA'),
            bodyText('La garantía ofrecida por FULLTECH, SRL cubre exclusivamente:'),
            spacer(6),
            bodyLine('Defectos de fábrica en los equipos instalados'),
            bodyLine(
              'Fallos ocasionados directamente por la instalación realizada por técnicos autorizados de la empresa',
            ),
            heading('LA GARANTÍA NO CUBRE'),
            bodyText('La garantía no será válida en los siguientes casos:'),
            spacer(6),
            bodyLine('Daños ocasionados por alto voltaje o variaciones eléctricas'),
            bodyLine('Daños causados por mal uso o manipulación indebida del equipo'),
            bodyLine('Daños por golpes, humedad, agua, fuego o accidentes'),
            bodyLine('Daños ocasionados por instalaciones eléctricas defectuosas del lugar'),
            bodyLine(
              'Manipulación o desmontaje del sistema por personas o técnicos externos a FULLTECH, SRL',
            ),
            spacer(6),
            bodyText(
              'Si el sistema instalado es modificado, manipulado o desmontado por terceros, la garantía quedará automáticamente anulada.',
            ),
            heading('PROCESO DE GARANTÍA'),
            bodyText('Para solicitar garantía el cliente deberá:'),
            spacer(6),
            bodyLine('Presentar el reporte o comprobante del servicio realizado'),
            bodyLine('Permitir la evaluación técnica del equipo o instalación'),
            spacer(6),
            bodyText(
              'Una vez evaluado el caso por el departamento técnico, se procederá a determinar la solución correspondiente.',
            ),
            heading('TIEMPO DE RESPUESTA'),
            bodyText('El proceso de evaluación y solución de garantía tendrá un plazo estimado de:'),
            spacer(6),
            bodyLine('0 a 7 días laborables, dependiendo de la distancia y disponibilidad del personal técnico.'),
            heading('ACEPTACIÓN DEL SERVICIO'),
            bodyText('Con su firma, el cliente confirma que:'),
            spacer(6),
            bodyLine('El servicio fue realizado correctamente'),
            bodyLine('Los equipos fueron entregados e instalados'),
            bodyLine('Recibió la información sobre las condiciones de garantía'),
            spacer(10),
            bodyLine('Firma del cliente:'),
            spacer(6),
            if (signatureImage != null)
              pw.Container(
                height: 90,
                width: double.infinity,
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                padding: const pw.EdgeInsets.all(6),
                child: pw.Image(signatureImage, fit: pw.BoxFit.contain),
              )
            else
              pw.Container(height: 1, color: PdfColors.grey600),
            spacer(8),
            bodyLine('Nombre del cliente:'),
            bodyLine(customer),
            spacer(6),
            bodyLine('Fecha:'),
            bodyLine(dfDate.format(serviceDate)),
            if (signedAtText.isNotEmpty) ...[
              spacer(4),
              pw.Text(
                'Firmado: $signedAtText',
                style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
              ),
            ],
            if (signatureRef.isNotEmpty)
              pw.Text(
                'Ref firma: $signatureRef',
                style: pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
              ),
            spacer(8),
            bodyLine('Técnico responsable:'),
            bodyLine(techs.isEmpty ? '—' : techs.join(', ')),
            spacer(12),
            pw.Text(
              'FULLTECH, SRL',
              style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold),
            ),
          ];
        },
      ),
    );

    return doc.save();
  }

  static String _money(double? v) {
    if (v == null) return '—';
    final safe = v.isNaN ? 0.0 : v;
    return 'RD\$${safe.toStringAsFixed(2)}';
  }

  static pw.Widget _companyHeader(CompanySettings? company) {
    final hasLogo = (company?.logoBase64 ?? '').trim().isNotEmpty;
    pw.MemoryImage? logoImage;

    if (hasLogo) {
      try {
        // base64Decode from dart:convert; but keep exporter minimal: pdf provides it via printing? no.
        // We'll decode using a safe helper below.
        logoImage = pw.MemoryImage(
          _safeBase64Decode(company!.logoBase64!.trim()),
        );
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
                  name.isEmpty ? 'FULLTECH' : name,
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

  static Uint8List _safeBase64Decode(String raw) {
    return Uint8List.fromList(const Base64Decoder().convert(raw));
  }

  static Future<Uint8List> _buildInvoicePdfBytes(
    ServiceModel service, {
    required CotizacionModel? cotizacion,
    required CompanySettings? company,
    Uint8List? clientSignaturePngBytes,
    String? clientSignatureFileId,
    String? clientSignatureFileUrl,
    DateTime? clientSignedAt,
  }) async {
    final money = NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$');
    final dateFmt = DateFormat('dd/MM/yyyy HH:mm', 'es');
    final dateOnlyFmt = DateFormat('dd/MM/yyyy', 'es');

    final now = DateTime.now();
    final doc = pw.Document(
      title: 'Factura',
      author: (company?.companyName ?? 'FULLTECH').trim(),
    );

    final serviceCustomer = service.customerName.trim().isEmpty
      ? 'Cliente'
      : service.customerName.trim();
    final servicePhone = service.customerPhone.trim();
    final address = service.customerAddress.trim();

    final quoteCustomer = (cotizacion?.customerName ?? '').trim();
    final quotePhone = (cotizacion?.customerPhone ?? '').trim();
    final customer = quoteCustomer.isNotEmpty ? quoteCustomer : serviceCustomer;
    final phone = quotePhone.isNotEmpty ? quotePhone : servicePhone;

    final titleType = _serviceTypeLabel(service.serviceType);
    final category = _categoryLabel(service.category);

    final items = cotizacion?.items ?? const <CotizacionItem>[];
    final hasItems = items.isNotEmpty;

    pw.MemoryImage? signatureImage;
    if (clientSignaturePngBytes != null && clientSignaturePngBytes.isNotEmpty) {
      try {
        signatureImage = pw.MemoryImage(clientSignaturePngBytes);
      } catch (_) {
        signatureImage = null;
      }
    }

    final signedAtText = clientSignedAt == null
        ? ''
        : dateFmt.format(clientSignedAt);
    final signatureRef = (clientSignatureFileId ?? '').trim().isNotEmpty
        ? (clientSignatureFileId ?? '').trim()
        : (clientSignatureFileUrl ?? '').trim();

    final includeItbis = cotizacion?.includeItbis ?? false;
    final itbisRate = cotizacion?.itbisRate ?? 0.18;
    final subtotal = cotizacion?.subtotal ?? (service.quotedAmount ?? 0);
    final itbisAmount = cotizacion != null
      ? cotizacion.itbisAmount
      : (includeItbis ? subtotal * itbisRate : 0);
    final total = cotizacion?.total ?? (subtotal + itbisAmount);

    final serviceDate = service.completedAt ?? service.scheduledStart;

    pw.Widget kv(String k, String v) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 90,
              child: pw.Text(
                k,
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 10,
                ),
              ),
            ),
            pw.Expanded(
              child: pw.Text(
                v.trim().isEmpty ? '—' : v.trim(),
                style: const pw.TextStyle(fontSize: 10),
              ),
            ),
          ],
        ),
      );
    }

    pw.Widget sectionTitle(String text) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 6),
        child: pw.Text(
          text,
          style: pw.TextStyle(
            fontWeight: pw.FontWeight.bold,
            fontSize: 10.5,
          ),
        ),
      );
    }

    pw.Widget infoBox({
      required String title,
      required List<pw.Widget> children,
    }) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
          border: pw.Border.all(color: PdfColors.grey400),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            sectionTitle(title),
            ...children,
          ],
        ),
      );
    }

    pw.Widget totalsBox() {
      final rawDeposit = service.depositAmount ?? 0.0;
      final deposit = rawDeposit.isNaN ? 0.0 : rawDeposit;
      final balance = (total - deposit) < 0 ? 0.0 : (total - deposit);
      final hasDeposit = deposit > 0;

      return pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Container(
          width: 280,
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            border: pw.Border.all(color: PdfColors.grey400),
            color: PdfColors.grey100,
          ),
          child: pw.Column(
            children: [
              _line('Subtotal', money.format(subtotal)),
              _line(
                'ITBIS (${(itbisRate * 100).toStringAsFixed(0)}%)',
                includeItbis ? money.format(itbisAmount) : 'No aplicado',
              ),
              pw.Divider(height: 12),
              _line(
                'Total',
                money.format(total),
                highlight: !hasDeposit,
              ),

              if (hasDeposit) ...[
                _line('Abono', money.format(deposit)),
                pw.Divider(height: 12),
                _line('Balance', money.format(balance), highlight: true),
              ],
            ],
          ),
        ),
      );
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        footer: (context) {
          final companyName = (company?.companyName ?? 'FULLTECH, SRL').trim();
          final phone = (company?.phone ?? '').trim();
          final rnc = (company?.rnc ?? '').trim();
          final pieces = <String>[
            companyName,
            if (rnc.isNotEmpty) 'RNC: $rnc',
            if (phone.isNotEmpty) 'Tel: $phone',
            'Página ${context.pageNumber} de ${context.pagesCount}',
          ];
          return pw.Padding(
            padding: const pw.EdgeInsets.only(top: 14),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Expanded(
                  child: pw.Text(
                    pieces.take(3).join(' · '),
                    style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                    maxLines: 1,
                    overflow: pw.TextOverflow.clip,
                  ),
                ),
                pw.SizedBox(width: 8),
                pw.Text(
                  'Página ${context.pageNumber}/${context.pagesCount}',
                  style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                ),
              ],
            ),
          );
        },
        build: (_) => [
          _companyHeader(company),
          pw.SizedBox(height: 10),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Factura',
                style: pw.TextStyle(
                  fontSize: 22,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.black,
                ),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'No.: ${service.orderLabel}',
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                  pw.Text(
                    'Fecha: ${dateFmt.format(now)}',
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                  if (serviceDate != null)
                    pw.Text(
                      'Servicio: ${dateOnlyFmt.format(serviceDate)}',
                      style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                    ),
                  if (cotizacion != null)
                    pw.Text(
                      'Cotización: ${cotizacion.id}',
                      style: pw.TextStyle(
                        fontSize: 9,
                        color: PdfColors.grey700,
                      ),
                    ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: infoBox(
                  title: 'Facturar a',
                  children: [
                    kv('Cliente', customer),
                    kv('Teléfono', phone.isEmpty ? '—' : phone),
                    kv('Dirección', address.isEmpty ? '—' : address),
                  ],
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: infoBox(
                  title: 'Servicio',
                  children: [
                    kv('Tipo', titleType),
                    kv('Categoría', category.trim().isEmpty ? '—' : category),
                    kv('Orden', service.orderLabel),
                    kv('ID', service.id),
                  ],
                ),
              ),
            ],
          ),
          if (cotizacion != null) ...[
            pw.SizedBox(height: 10),
            infoBox(
              title: 'Datos de la cotización',
              children: [
                kv('ID', cotizacion.id),
                kv('Fecha', dateFmt.format(cotizacion.createdAt)),
                kv('Cliente', cotizacion.customerName.trim().isEmpty ? customer : cotizacion.customerName.trim()),
                kv('Teléfono', (cotizacion.customerPhone ?? '').trim().isEmpty ? (phone.isEmpty ? '—' : phone) : (cotizacion.customerPhone ?? '').trim()),
                kv('Incluye ITBIS', cotizacion.includeItbis ? 'Sí' : 'No'),
                kv('Tasa ITBIS', '${(cotizacion.itbisRate * 100).toStringAsFixed(0)}%'),
                if (cotizacion.note.trim().isNotEmpty) kv('Nota', cotizacion.note.trim()),
              ],
            ),
          ],
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.6),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
            cellStyle: const pw.TextStyle(fontSize: 10),
            headers: const ['#', 'Descripción', 'Cant.', 'Precio', 'Total'],
            data: hasItems
                ? items
                      .asMap()
                      .entries
                      .map(
                        (e) => [
                          '${e.key + 1}',
                          e.value.nombre,
                          e.value.qty.toStringAsFixed(
                            e.value.qty % 1 == 0 ? 0 : 2,
                          ),
                          money.format(e.value.unitPrice),
                          money.format(e.value.total),
                        ],
                      )
                      .toList(growable: false)
                : [
                    [
                      '1',
                      service.title.trim().isEmpty
                          ? 'Servicio'
                          : service.title.trim(),
                      '1',
                      money.format(subtotal),
                      money.format(subtotal),
                    ],
                  ],
            cellAlignments: {
              0: pw.Alignment.center,
              2: pw.Alignment.center,
              3: pw.Alignment.centerRight,
              4: pw.Alignment.centerRight,
            },
            columnWidths: {
              0: const pw.FixedColumnWidth(18),
              2: const pw.FixedColumnWidth(42),
              3: const pw.FixedColumnWidth(70),
              4: const pw.FixedColumnWidth(70),
            },
          ),
          pw.SizedBox(height: 12),
          totalsBox(),
          pw.SizedBox(height: 14),
          pw.Text(
            'Gracias por su preferencia.',
            style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
          if (signatureImage != null) ...[
            pw.SizedBox(height: 14),
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                border: pw.Border.all(color: PdfColors.grey400),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Aceptación del cliente',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Text(
                    'Cliente: $customer',
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                  if (signedAtText.isNotEmpty)
                    pw.Text(
                      'Firmado: $signedAtText',
                      style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                    ),
                  if (signatureRef.isNotEmpty)
                    pw.Text(
                      'Ref firma: $signatureRef',
                      style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                    ),
                  pw.SizedBox(height: 8),
                  pw.Container(
                    height: 80,
                    width: double.infinity,
                    decoration: pw.BoxDecoration(
                      color: PdfColors.grey100,
                      borderRadius: const pw.BorderRadius.all(
                        pw.Radius.circular(6),
                      ),
                      border: pw.Border.all(color: PdfColors.grey300),
                    ),
                    padding: const pw.EdgeInsets.all(6),
                    child: pw.Image(signatureImage, fit: pw.BoxFit.contain),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Container(height: 1, color: PdfColors.grey600),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Firma del cliente (Orden ${service.orderLabel})',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );

    return doc.save();
  }

  static pw.Widget _line(String label, String value, {bool highlight = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text(
              label,
              style: pw.TextStyle(
                fontWeight: highlight
                    ? pw.FontWeight.bold
                    : pw.FontWeight.normal,
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

  static String _fileNameFromUrl(String raw) {
    final cleaned = raw.trim();
    if (cleaned.isEmpty) return '';
    final idx = cleaned.lastIndexOf('/');
    final name = idx >= 0 ? cleaned.substring(idx + 1) : cleaned;
    return name.isEmpty ? cleaned : name;
  }

  static String _serviceTypeLabel(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'installation':
        return 'Instalación';
      case 'maintenance':
        return 'Servicio técnico';
      case 'warranty':
        return 'Garantía';
      case 'pos_support':
        return 'Soporte POS';
      default:
        return raw.trim().isEmpty ? 'Servicio' : raw.trim();
    }
  }

  static String _categoryLabel(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'cameras':
        return 'Cámaras';
      case 'gate_motor':
        return 'Motores de puertones';
      case 'alarm':
        return 'Alarma';
      case 'electric_fence':
        return 'Cerco eléctrico';
      case 'intercom':
        return 'Intercom';
      case 'pos':
        return 'Punto de ventas';
      default:
        return raw.trim().isEmpty ? 'General' : raw.trim();
    }
  }

  static Future<Uint8List> _buildPdfBytes(ServiceModel service) async {
    final now = DateTime.now();
    final df = DateFormat('dd/MM/yyyy HH:mm', 'es');

    final titleType = _serviceTypeLabel(service.serviceType);
    final category = _categoryLabel(service.category);
    final title = category.isEmpty ? titleType : '$titleType · $category';

    final customer = service.customerName.trim().isEmpty
        ? 'Cliente'
        : service.customerName.trim();
    final phone = service.customerPhone.trim();
    final address = service.customerAddress.trim();

    final techs = service.assignments
        .map((a) => a.userName.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final total = service.quotedAmount ?? service.depositAmount;

    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 30),
        build: (context) {
          return [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'FULLTECH',
                      style: pw.TextStyle(
                        fontSize: 20,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'Detalle de servicio',
                      style: pw.TextStyle(
                        fontSize: 12,
                        color: PdfColors.grey700,
                      ),
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'ID: ${service.id}',
                      style: pw.TextStyle(
                        fontSize: 9,
                        color: PdfColors.grey700,
                      ),
                    ),
                    pw.Text(
                      df.format(now),
                      style: pw.TextStyle(
                        fontSize: 9,
                        color: PdfColors.grey700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 14),
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    title,
                    style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    phone.isEmpty ? customer : '$customer · $phone',
                    style: pw.TextStyle(color: PdfColors.grey800),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 12),
            _section('Resumen', [
              _kv(
                'Estado',
                service.orderState.isNotEmpty
                    ? service.orderState
                    : service.status,
              ),
              _kv('Prioridad', 'P${service.priority}'),
              _kv(
                'Inicio',
                service.scheduledStart == null
                    ? '—'
                    : df.format(service.scheduledStart!),
              ),
              _kv(
                'Fin',
                service.scheduledEnd == null
                    ? '—'
                    : df.format(service.scheduledEnd!),
              ),
              _kv('Técnicos', techs.isEmpty ? 'Sin asignar' : techs.join(', ')),
            ]),
            _section('Ubicación', [
              pw.Text(address.isEmpty ? 'Sin ubicación' : address),
            ]),
            _section('Finanzas', [
              _kv('Cotizado', _money(service.quotedAmount)),
              _kv('Abono', _money(service.depositAmount)),
              _kv('Total', _money(total)),
            ]),
            _section(
              'Checklist',
              service.steps.isEmpty
                  ? [pw.Text('Sin checklist')]
                  : service.steps
                        .map(
                          (s) => pw.Text(
                            '${s.isDone ? '[x]' : '[ ]'} ${s.stepLabel}',
                            style: pw.TextStyle(
                              color: s.isDone
                                  ? PdfColors.black
                                  : PdfColors.grey800,
                            ),
                          ),
                        )
                        .toList(),
            ),
            _section(
              'Evidencias',
              service.files.isEmpty
                  ? [pw.Text('Sin evidencias')]
                  : service.files
                        .map(
                          (f) => pw.Text(
                            '${f.fileType} · ${_fileNameFromUrl(f.fileUrl)}',
                            style: const pw.TextStyle(fontSize: 10),
                          ),
                        )
                        .toList(),
            ),
            _section(
              'Historial (resumen)',
              service.updates.isEmpty
                  ? [pw.Text('Sin movimientos')]
                  : service.updates
                        .take(10)
                        .map(
                          (u) => pw.Text(
                            '- ${u.message.isEmpty ? u.type : u.message} (${u.changedBy}${u.createdAt == null ? '' : ' · ${df.format(u.createdAt!)}'})',
                            style: const pw.TextStyle(fontSize: 10),
                          ),
                        )
                        .toList(),
            ),
          ];
        },
      ),
    );

    return doc.save();
  }

  static pw.Widget _section(String title, List<pw.Widget> children) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 10),
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.grey800,
            ),
          ),
          pw.SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  static pw.Widget _kv(String k, String v) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 70,
            child: pw.Text(
              k,
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey700,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Text(v, style: const pw.TextStyle(fontSize: 10)),
          ),
        ],
      ),
    );
  }
}
