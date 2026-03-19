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
  static const PdfColor _brandBlue = PdfColors.blue800;
  static const PdfColor _brandBlueSoft = PdfColors.blue50;
  static const PdfColor _textMuted = PdfColors.grey700;
  static const PdfColor _lineColor = PdfColor.fromInt(0xFFD7E5F2);

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
    List<WarrantyProductConfigModel> warrantyConfigs = const [],
    Uint8List? clientSignaturePngBytes,
    String? clientSignatureFileId,
    String? clientSignatureFileUrl,
    DateTime? clientSignedAt,
  }) async {
    final companyName = (company?.companyName ?? 'FULLTECH, SRL').trim();
    final companyRnc = (company?.rnc ?? '').trim();
    final companyPhone = (company?.phone ?? '').trim();
    final customer = service.customerName.trim().isEmpty
        ? 'Cliente'
        : service.customerName.trim();
    final phone = service.customerPhone.trim();
    final address = service.customerAddress.trim();
    final techs = service.assignments
        .map((a) => a.userName.trim())
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
    final serviceDate =
        service.completedAt ?? service.scheduledStart ?? DateTime.now();
    final dfDate = DateFormat('dd/MM/yyyy', 'es');
    final dateTimeFmt = DateFormat('dd/MM/yyyy HH:mm', 'es');
    final items = cotizacion?.items ?? const <CotizacionItem>[];
    final resolvedWarranty = _resolveWarrantyConfig(
      service: service,
      cotizacion: cotizacion,
      configs: warrantyConfigs,
    );
    final categoryLabel = _categoryLabel(
      service.categoryName?.trim().isNotEmpty == true
          ? service.categoryName!
          : service.category,
    );
    final coverageLabel = resolvedWarranty?.scopeLabel.trim().isNotEmpty == true
        ? resolvedWarranty!.scopeLabel.trim()
        : categoryLabel;
    final durationText = _warrantyDurationText(resolvedWarranty);
    final summaryText =
        (resolvedWarranty?.warrantySummary ?? '').trim().isNotEmpty
        ? resolvedWarranty!.warrantySummary!.trim()
        : resolvedWarranty?.hasWarranty == false
        ? 'Este servicio queda registrado sin garantía comercial adicional. Cualquier incidencia debe revisarse mediante validación técnica.'
        : 'FULLTECH certifica la cobertura aplicable al servicio ejecutado, conforme a la configuración vigente y a las condiciones normales de operación del equipo instalado.';
    final coverageText =
        (resolvedWarranty?.coverageSummary ?? '').trim().isNotEmpty
        ? resolvedWarranty!.coverageSummary!.trim()
        : 'Incluye diagnóstico técnico, verificación del defecto reportado y corrección cuando la falla corresponda al alcance aprobado de instalación o producto.';
    final exclusionsText =
        (resolvedWarranty?.exclusionsSummary ?? '').trim().isNotEmpty
        ? resolvedWarranty!.exclusionsSummary!.trim()
        : 'No cubre daños por manipulación de terceros, golpes, humedad, variaciones eléctricas, uso indebido, vandalismo ni modificaciones ajenas a FULLTECH.';
    final serviceNotes = [
      if (items.isNotEmpty)
        items
            .map(
              (item) =>
                  '${item.qty.toStringAsFixed(item.qty % 1 == 0 ? 0 : 2)} x ${item.nombre.trim().isEmpty ? 'Producto' : item.nombre.trim()}',
            )
            .join(', '),
      if ((resolvedWarranty?.notes ?? '').trim().isNotEmpty)
        resolvedWarranty!.notes!.trim(),
    ].where((part) => part.trim().isNotEmpty).join('\n\n');

    pw.MemoryImage? signatureImage;
    if (clientSignaturePngBytes != null && clientSignaturePngBytes.isNotEmpty) {
      try {
        signatureImage = pw.MemoryImage(clientSignaturePngBytes);
      } catch (_) {
        signatureImage = null;
      }
    }

    pw.MemoryImage? logoImage;
    final logoBase64 = (company?.logoBase64 ?? '').trim();
    if (logoBase64.isNotEmpty) {
      try {
        logoImage = pw.MemoryImage(_safeBase64Decode(logoBase64));
      } catch (_) {
        logoImage = null;
      }
    }

    final signedAtText = clientSignedAt == null
        ? ''
        : dateTimeFmt.format(clientSignedAt);
    final signatureRef = (clientSignatureFileId ?? '').trim().isNotEmpty
        ? (clientSignatureFileId ?? '').trim()
        : (clientSignatureFileUrl ?? '').trim();

    pw.Widget buildField(String label, String value) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 10),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              label.toUpperCase(),
              style: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
                color: _textMuted,
                letterSpacing: 0.6,
              ),
            ),
            pw.SizedBox(height: 3),
            pw.Text(value, style: const pw.TextStyle(fontSize: 10.3)),
          ],
        ),
      );
    }

    pw.Widget buildInfoCard(
      String title,
      List<MapEntry<String, String>> fields,
    ) {
      final visibleFields = fields
          .where((entry) => entry.value.trim().isNotEmpty)
          .toList(growable: false);
      return pw.Container(
        padding: const pw.EdgeInsets.fromLTRB(16, 14, 16, 10),
        decoration: pw.BoxDecoration(
          color: PdfColors.white,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
          border: pw.Border.all(color: _lineColor, width: 0.9),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              title.toUpperCase(),
              style: pw.TextStyle(
                fontSize: 9.2,
                fontWeight: pw.FontWeight.bold,
                color: _brandBlue,
                letterSpacing: 0.8,
              ),
            ),
            pw.SizedBox(height: 10),
            ...visibleFields.map((entry) => buildField(entry.key, entry.value)),
          ],
        ),
      );
    }

    pw.Widget buildTextCard(String title, String text) {
      return pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 14),
        padding: const pw.EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: pw.BoxDecoration(
          color: PdfColors.white,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
          border: pw.Border.all(color: _lineColor, width: 0.9),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              title.toUpperCase(),
              style: pw.TextStyle(
                fontSize: 9.2,
                fontWeight: pw.FontWeight.bold,
                color: _brandBlue,
                letterSpacing: 0.8,
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Text(
              text,
              style: const pw.TextStyle(fontSize: 10.4, lineSpacing: 2.1),
            ),
          ],
        ),
      );
    }

    final doc = pw.Document(title: 'Carta de Garantía', author: companyName);
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 40, 36, 44),
        build: (context) {
          return [
            pw.Container(
              padding: const pw.EdgeInsets.fromLTRB(18, 18, 18, 18),
              decoration: pw.BoxDecoration(
                color: PdfColors.white,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(14)),
                border: pw.Border.all(color: _lineColor, width: 1),
              ),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        if (logoImage != null)
                          pw.Container(
                            width: 54,
                            height: 54,
                            margin: const pw.EdgeInsets.only(right: 12),
                            padding: const pw.EdgeInsets.all(6),
                            decoration: pw.BoxDecoration(
                              color: _brandBlueSoft,
                              borderRadius: const pw.BorderRadius.all(
                                pw.Radius.circular(12),
                              ),
                            ),
                            child: pw.Image(logoImage, fit: pw.BoxFit.contain),
                          )
                        else
                          pw.Container(
                            width: 54,
                            height: 54,
                            margin: const pw.EdgeInsets.only(right: 12),
                            decoration: pw.BoxDecoration(
                              color: _brandBlueSoft,
                              borderRadius: const pw.BorderRadius.all(
                                pw.Radius.circular(12),
                              ),
                            ),
                            alignment: pw.Alignment.center,
                            child: pw.Text(
                              'FT',
                              style: pw.TextStyle(
                                color: _brandBlue,
                                fontWeight: pw.FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                          ),
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                companyName.isEmpty
                                    ? 'FULLTECH, SRL'
                                    : companyName,
                                style: pw.TextStyle(
                                  fontSize: 17,
                                  fontWeight: pw.FontWeight.bold,
                                  color: _brandBlue,
                                ),
                              ),
                              pw.SizedBox(height: 5),
                              if (companyRnc.isNotEmpty)
                                pw.Text(
                                  'RNC: $companyRnc',
                                  style: pw.TextStyle(
                                    fontSize: 9.2,
                                    color: _textMuted,
                                  ),
                                ),
                              if (companyPhone.isNotEmpty)
                                pw.Text(
                                  'Tel: $companyPhone',
                                  style: pw.TextStyle(
                                    fontSize: 9.2,
                                    color: _textMuted,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 18),
                  pw.Container(
                    width: 190,
                    padding: const pw.EdgeInsets.fromLTRB(16, 14, 16, 14),
                    decoration: pw.BoxDecoration(
                      color: PdfColor.fromHex('#0D3558'),
                      borderRadius: const pw.BorderRadius.all(
                        pw.Radius.circular(14),
                      ),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                          'GARANTÍA',
                          style: pw.TextStyle(
                            fontSize: 21,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.white,
                            letterSpacing: 0.8,
                          ),
                        ),
                        pw.SizedBox(height: 12),
                        buildField(
                          'Número',
                          service.orderLabel.trim().isEmpty
                              ? service.id
                              : service.orderLabel.trim(),
                        ),
                        buildField('Fecha', dfDate.format(serviceDate)),
                        buildField('Cobertura', coverageLabel),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 16),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: buildInfoCard('Cliente y servicio', [
                    MapEntry('Cliente', customer),
                    if (phone.isNotEmpty) MapEntry('Teléfono', phone),
                    if (address.isNotEmpty) MapEntry('Dirección', address),
                    MapEntry(
                      'Servicio',
                      _serviceTypeLabel(service.serviceType),
                    ),
                  ]),
                ),
                pw.SizedBox(width: 14),
                pw.Expanded(
                  child: buildInfoCard('Cobertura aplicada', [
                    MapEntry('Ámbito', coverageLabel),
                    MapEntry('Categoría', categoryLabel),
                    MapEntry('Duración', durationText),
                    if (techs.isNotEmpty) MapEntry('Técnico', techs.join(', ')),
                  ]),
                ),
              ],
            ),
            pw.SizedBox(height: 14),
            buildTextCard('Resumen ejecutivo', summaryText),
            buildTextCard('Cobertura incluida', coverageText),
            buildTextCard('Exclusiones y límites', exclusionsText),
            if (serviceNotes.trim().isNotEmpty)
              buildTextCard('Notas del servicio', serviceNotes),
            pw.Container(
              padding: const pw.EdgeInsets.fromLTRB(16, 14, 16, 14),
              decoration: pw.BoxDecoration(
                color: PdfColors.white,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
                border: pw.Border.all(color: _lineColor, width: 0.9),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'ACEPTACIÓN DEL CLIENTE',
                    style: pw.TextStyle(
                      fontSize: 9.2,
                      fontWeight: pw.FontWeight.bold,
                      color: _brandBlue,
                      letterSpacing: 0.8,
                    ),
                  ),
                  pw.SizedBox(height: 10),
                  pw.Text(
                    'El cliente declara haber recibido la información de cobertura, límites y proceso de validación técnica.',
                    style: const pw.TextStyle(fontSize: 10.4, lineSpacing: 2.1),
                  ),
                  pw.SizedBox(height: 14),
                  if (signatureImage != null)
                    pw.Container(
                      height: 90,
                      width: double.infinity,
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: _lineColor, width: 0.9),
                        borderRadius: const pw.BorderRadius.all(
                          pw.Radius.circular(10),
                        ),
                      ),
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Image(signatureImage, fit: pw.BoxFit.contain),
                    )
                  else
                    pw.Container(height: 1, color: PdfColors.grey600),
                  pw.SizedBox(height: 10),
                  pw.Text(customer, style: const pw.TextStyle(fontSize: 10.4)),
                  pw.Text(
                    signedAtText.isEmpty
                        ? 'Fecha: ${dfDate.format(serviceDate)}'
                        : 'Firmado: $signedAtText',
                    style: pw.TextStyle(fontSize: 8.5, color: _textMuted),
                  ),
                  if (signatureRef.isNotEmpty)
                    pw.Text(
                      'Ref firma: $signatureRef',
                      style: pw.TextStyle(fontSize: 7.2, color: _textMuted),
                    ),
                ],
              ),
            ),
            pw.SizedBox(height: 14),
            pw.Text(
              'Documento emitido por ${companyName.isEmpty ? 'FULLTECH, SRL' : companyName} para seguimiento y atención post-servicio.',
              style: pw.TextStyle(fontSize: 8.2, color: _textMuted),
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

  static Uint8List _safeBase64Decode(String raw) {
    return Uint8List.fromList(const Base64Decoder().convert(raw));
  }

  static WarrantyProductConfigModel? _resolveWarrantyConfig({
    required ServiceModel service,
    required CotizacionModel? cotizacion,
    required List<WarrantyProductConfigModel> configs,
  }) {
    if (configs.isEmpty) return null;

    final productKeys = <String>{
      _normalizeWarrantyKey(service.title),
      ...?cotizacion?.items.map((item) => _normalizeWarrantyKey(item.nombre)),
    }..removeWhere((item) => item.isEmpty);

    for (final key in productKeys) {
      for (final config in configs) {
        if (_normalizeWarrantyKey(config.productName ?? '') == key) {
          return config;
        }
      }
    }

    final categoryKeys = <String>{
      _normalizeWarrantyKey(service.categoryId ?? ''),
      _normalizeWarrantyKey(service.categoryName ?? ''),
      _normalizeWarrantyKey(service.category),
    }..removeWhere((item) => item.isEmpty);

    for (final config in configs) {
      final configKeys = <String>{
        _normalizeWarrantyKey(config.categoryId ?? ''),
        _normalizeWarrantyKey(config.categoryCode ?? ''),
        _normalizeWarrantyKey(config.categoryName ?? ''),
      }..removeWhere((item) => item.isEmpty);
      if (configKeys.any(categoryKeys.contains)) return config;
    }

    return null;
  }

  static String _normalizeWarrantyKey(String raw) {
    return raw
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[áàäâ]'), 'a')
        .replaceAll(RegExp(r'[éèëê]'), 'e')
        .replaceAll(RegExp(r'[íìïî]'), 'i')
        .replaceAll(RegExp(r'[óòöô]'), 'o')
        .replaceAll(RegExp(r'[úùüû]'), 'u')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();
  }

  static String _warrantyDurationText(WarrantyProductConfigModel? config) {
    if (config == null) return 'Cobertura según configuración vigente';
    return config.durationLabel;
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

    final companyName = (company?.companyName ?? 'Fulltech SRL').trim().isEmpty
        ? 'Fulltech SRL'
        : (company?.companyName ?? 'Fulltech SRL').trim();
    final companyRnc = (company?.rnc ?? '').trim();
    final companyPhone = (company?.phone ?? '').trim();
    final companyAddress = (company?.address ?? '').trim();

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
    final documentType = titleType.toLowerCase().contains('venta')
        ? 'Venta'
        : 'Servicio';
    final invoiceNumber = service.orderLabel.trim().isEmpty
        ? service.id
        : service.orderLabel.trim();

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
        : dateFmt.format(clientSignedAt);
    final signatureRef = (clientSignatureFileId ?? '').trim().isNotEmpty
        ? (clientSignatureFileId ?? '').trim()
        : (clientSignatureFileUrl ?? '').trim();

    final includeItbis = cotizacion?.includeItbis ?? false;
    final double itbisRate = cotizacion?.itbisRate ?? 0.18;
    final double subtotal =
        cotizacion?.subtotal ?? (service.quotedAmount ?? 0.0);
    final double itbisAmount = cotizacion != null
        ? cotizacion.itbisAmount
        : (includeItbis ? subtotal * itbisRate : 0.0);
    final double total = cotizacion?.total ?? (subtotal + itbisAmount);

    final serviceDate = service.completedAt ?? service.scheduledStart;

    pw.MemoryImage? logoImage;
    final logoBase64 = (company?.logoBase64 ?? '').trim();
    if (logoBase64.isNotEmpty) {
      try {
        logoImage = pw.MemoryImage(_safeBase64Decode(logoBase64));
      } catch (_) {
        logoImage = null;
      }
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(24, 22, 24, 28),
        footer: (context) => _buildFooter(
          context,
          companyName: companyName,
          companyRnc: companyRnc,
          companyPhone: companyPhone,
        ),
        build: (_) => [
          _buildInvoiceHeader(
            logoImage: logoImage,
            companyName: companyName,
            companyRnc: companyRnc,
            companyPhone: companyPhone,
            companyAddress: companyAddress,
            invoiceNumber: invoiceNumber,
            invoiceDate: dateFmt.format(now),
            documentType: documentType,
            serviceType: titleType,
          ),
          pw.SizedBox(height: 10),
          _buildClientAndServiceRow(
            customerFields: [
              MapEntry('Nombre', customer),
              if (phone.isNotEmpty) MapEntry('Teléfono', phone),
              if (address.isNotEmpty) MapEntry('Dirección', address),
            ],
            serviceFields: [
              MapEntry('Tipo', titleType),
              if (category.trim().isNotEmpty) MapEntry('Categoría', category),
              if (serviceDate != null)
                MapEntry('Fecha servicio', dateOnlyFmt.format(serviceDate)),
              if (service.orderLabel.trim().isNotEmpty)
                MapEntry('Orden', service.orderLabel.trim()),
            ],
          ),
          pw.SizedBox(height: 12),
          _buildItemsTable(
            money: money,
            items: items,
            serviceTitle: service.title.trim(),
            fallbackSubtotal: subtotal,
          ),
          pw.SizedBox(height: 10),
          _buildTotalsSection(
            money: money,
            subtotal: subtotal,
            includeItbis: includeItbis,
            itbisRate: itbisRate,
            itbisAmount: itbisAmount,
            total: total,
            depositAmount: service.depositAmount,
          ),
          if (signatureImage != null) ...[
            pw.SizedBox(height: 14),
            _buildSignatureSection(
              customer: customer,
              signedAtText: signedAtText,
              signatureRef: signatureRef,
              signatureImage: signatureImage,
              invoiceNumber: invoiceNumber,
            ),
          ],
        ],
      ),
    );

    return doc.save();
  }

  static pw.Widget _buildInvoiceHeader({
    required pw.MemoryImage? logoImage,
    required String companyName,
    required String companyRnc,
    required String companyPhone,
    required String companyAddress,
    required String invoiceNumber,
    required String invoiceDate,
    required String documentType,
    required String serviceType,
  }) {
    final companyLines = <String>[
      if (companyRnc.isNotEmpty) 'RNC: $companyRnc',
      if (companyPhone.isNotEmpty) 'Tel: $companyPhone',
      if (companyAddress.isNotEmpty) companyAddress,
    ];

    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(16)),
        border: pw.Border.all(color: _lineColor, width: 0.9),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            flex: 6,
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _buildInvoiceLogo(logoImage),
                pw.SizedBox(width: 10),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        companyName,
                        style: pw.TextStyle(
                          fontSize: 15.5,
                          fontWeight: pw.FontWeight.bold,
                          color: _brandBlue,
                        ),
                      ),
                      if (companyLines.isNotEmpty) ...[
                        pw.SizedBox(height: 3),
                        ...companyLines.map(
                          (line) => pw.Padding(
                            padding: const pw.EdgeInsets.only(bottom: 2),
                            child: pw.Text(
                              line,
                              style: pw.TextStyle(
                                fontSize: 8.8,
                                color: _textMuted,
                                lineSpacing: 1.2,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(width: 12),
          pw.Container(
            width: 190,
            padding: const pw.EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#0D3558'),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(16)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  'FACTURA',
                  style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white,
                    letterSpacing: 0.8,
                  ),
                ),
                pw.SizedBox(height: 8),
                _invoiceMetaLine('No.', invoiceNumber, light: true),
                _invoiceMetaLine('Fecha', invoiceDate, light: true),
                _invoiceMetaLine('Doc.', documentType, light: true),
                if (serviceType.trim().isNotEmpty)
                  _invoiceMetaLine('Servicio', serviceType, light: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildClientAndServiceRow({
    required List<MapEntry<String, String>> customerFields,
    required List<MapEntry<String, String>> serviceFields,
  }) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(child: _buildCompactInfoBlock('Cliente', customerFields)),
        pw.SizedBox(width: 10),
        pw.Expanded(child: _buildCompactInfoBlock('Servicio', serviceFields)),
      ],
    );
  }

  static pw.Widget _buildItemsTable({
    required NumberFormat money,
    required List<CotizacionItem> items,
    required String serviceTitle,
    required double fallbackSubtotal,
  }) {
    final rows = items.isNotEmpty
        ? items
              .map(
                (item) => (
                  item.nombre.trim().isEmpty
                      ? 'Producto / servicio'
                      : item.nombre.trim(),
                  item.qty.toStringAsFixed(item.qty % 1 == 0 ? 0 : 2),
                  money.format(item.unitPrice),
                  money.format(item.total),
                ),
              )
              .toList(growable: false)
        : [
            (
              serviceTitle.isEmpty ? 'Servicio' : serviceTitle,
              '1',
              money.format(fallbackSubtotal),
              money.format(fallbackSubtotal),
            ),
          ];

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Detalle',
          style: pw.TextStyle(
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
            color: _brandBlue,
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Table(
          border: pw.TableBorder(
            horizontalInside: pw.BorderSide(
              color: PdfColor.fromHex('#E7EDF4'),
              width: 0.6,
            ),
            bottom: pw.BorderSide(
              color: PdfColor.fromHex('#E7EDF4'),
              width: 0.7,
            ),
          ),
          columnWidths: {
            0: const pw.FlexColumnWidth(5.4),
            1: const pw.FixedColumnWidth(48),
            2: const pw.FixedColumnWidth(76),
            3: const pw.FixedColumnWidth(82),
          },
          children: [
            pw.TableRow(
              decoration: pw.BoxDecoration(
                color: _brandBlue,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
              ),
              children: [
                _invoiceTableCell('Descripción', header: true),
                _invoiceTableCell(
                  'Cant.',
                  header: true,
                  align: pw.TextAlign.right,
                ),
                _invoiceTableCell(
                  'Precio',
                  header: true,
                  align: pw.TextAlign.right,
                ),
                _invoiceTableCell(
                  'Total',
                  header: true,
                  align: pw.TextAlign.right,
                ),
              ],
            ),
            ...rows.asMap().entries.map(
              (entry) => pw.TableRow(
                decoration: pw.BoxDecoration(
                  color: entry.key.isEven
                      ? PdfColors.white
                      : PdfColor.fromHex('#FAFCFE'),
                ),
                children: [
                  _invoiceTableCell(entry.value.$1),
                  _invoiceTableCell(entry.value.$2, align: pw.TextAlign.right),
                  _invoiceTableCell(entry.value.$3, align: pw.TextAlign.right),
                  _invoiceTableCell(entry.value.$4, align: pw.TextAlign.right),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildTotalsSection({
    required NumberFormat money,
    required double subtotal,
    required bool includeItbis,
    required double itbisRate,
    required double itbisAmount,
    required double total,
    required double? depositAmount,
  }) {
    final rawDeposit = depositAmount ?? 0.0;
    final safeDeposit = rawDeposit.isNaN ? 0.0 : rawDeposit;
    final balance = (total - safeDeposit) < 0 ? 0.0 : (total - safeDeposit);

    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Container(
        width: 220,
        padding: const pw.EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: pw.BoxDecoration(
          color: PdfColor.fromHex('#F6FAFD'),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(14)),
          border: pw.Border.all(color: _lineColor, width: 0.9),
        ),
        child: pw.Column(
          children: [
            _line('Subtotal', money.format(subtotal)),
            if (includeItbis)
              _line(
                'ITBIS ${(itbisRate * 100).toStringAsFixed(0)}%',
                money.format(itbisAmount),
              ),
            if (safeDeposit > 0) _line('Abono', money.format(safeDeposit)),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 6),
              child: pw.Container(
                height: 1,
                color: PdfColor.fromHex('#DDE7F0'),
              ),
            ),
            _line('TOTAL', money.format(total), highlight: true),
            if (safeDeposit > 0)
              _line('Balance', money.format(balance), highlight: true),
          ],
        ),
      ),
    );
  }

  static pw.Widget _buildSignatureSection({
    required String customer,
    required String signedAtText,
    required String signatureRef,
    required pw.MemoryImage signatureImage,
    required String invoiceNumber,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(14)),
        border: pw.Border.all(color: _lineColor, width: 0.9),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Aceptación del cliente',
            style: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              color: _brandBlue,
              fontSize: 10,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Cliente: $customer',
            style: const pw.TextStyle(fontSize: 9.6),
          ),
          if (signedAtText.isNotEmpty)
            pw.Text(
              'Firmado: $signedAtText',
              style: pw.TextStyle(fontSize: 8.6, color: _textMuted),
            ),
          if (signatureRef.isNotEmpty)
            pw.Text(
              'Ref: $signatureRef',
              style: pw.TextStyle(fontSize: 8, color: _textMuted),
            ),
          pw.SizedBox(height: 8),
          pw.Container(
            height: 72,
            width: double.infinity,
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#FBFDFF'),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
              border: pw.Border.all(color: PdfColor.fromHex('#E5ECF2')),
            ),
            padding: const pw.EdgeInsets.all(6),
            child: pw.Image(signatureImage, fit: pw.BoxFit.contain),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Firma del cliente (Orden $invoiceNumber)',
            style: pw.TextStyle(fontSize: 8.8, color: _textMuted),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildFooter(
    pw.Context context, {
    required String companyName,
    required String companyRnc,
    required String companyPhone,
  }) {
    final pieces = <String>[
      companyName,
      if (companyRnc.isNotEmpty) 'RNC: $companyRnc',
      if (companyPhone.isNotEmpty) 'Tel: $companyPhone',
    ];

    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 10),
      child: pw.Column(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Container(height: 1, color: PdfColor.fromHex('#E5ECF2')),
          pw.SizedBox(height: 6),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Expanded(
                child: pw.Text(
                  pieces.join(' · '),
                  style: pw.TextStyle(fontSize: 8, color: _textMuted),
                  maxLines: 1,
                  overflow: pw.TextOverflow.clip,
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Text(
                'Página ${context.pageNumber}/${context.pagesCount}',
                style: pw.TextStyle(fontSize: 8, color: _textMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildInvoiceLogo(pw.MemoryImage? logoImage) {
    return pw.Container(
      width: 44,
      height: 44,
      padding: const pw.EdgeInsets.all(5),
      decoration: pw.BoxDecoration(
        color: _brandBlueSoft,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
      ),
      child: logoImage != null
          ? pw.Image(logoImage, fit: pw.BoxFit.contain)
          : pw.Center(
              child: pw.Text(
                'FT',
                style: pw.TextStyle(
                  color: _brandBlue,
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
    );
  }

  static pw.Widget _buildCompactInfoBlock(
    String title,
    List<MapEntry<String, String>> fields,
  ) {
    final visibleFields = fields
        .where((entry) => entry.value.trim().isNotEmpty)
        .toList(growable: false);

    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(14)),
        border: pw.Border.all(color: _lineColor, width: 0.9),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title.toUpperCase(),
            style: pw.TextStyle(
              fontSize: 8.8,
              fontWeight: pw.FontWeight.bold,
              color: _brandBlue,
              letterSpacing: 0.8,
            ),
          ),
          pw.SizedBox(height: 7),
          ...visibleFields.map(
            (entry) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 5),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.SizedBox(
                    width: 54,
                    child: pw.Text(
                      entry.key,
                      style: pw.TextStyle(
                        fontSize: 8,
                        color: _textMuted,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 6),
                  pw.Expanded(
                    child: pw.Text(
                      entry.value.trim(),
                      style: const pw.TextStyle(fontSize: 9.4),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _invoiceMetaLine(
    String label,
    String value, {
    bool light = false,
  }) {
    final foreground = light ? PdfColors.white : PdfColors.black;
    final muted = light ? PdfColors.blue100 : _textMuted;

    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.end,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            '$label: ',
            style: pw.TextStyle(
              fontSize: 8.2,
              color: muted,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.Flexible(
            child: pw.Text(
              value,
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(
                fontSize: 8.8,
                color: foreground,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _invoiceTableCell(
    String text, {
    pw.TextAlign align = pw.TextAlign.left,
    bool header = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          fontSize: header ? 9 : 9.2,
          fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: header ? PdfColors.white : PdfColors.black,
        ),
      ),
    );
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
