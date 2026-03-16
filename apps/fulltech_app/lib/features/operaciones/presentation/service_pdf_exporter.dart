import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

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

  static Future<Uint8List> buildWarrantyLetterBytes(ServiceModel service) async {
    final now = DateTime.now();
    final df = DateFormat('dd/MM/yyyy', 'es');

    final customer = service.customerName.trim().isEmpty
        ? 'Cliente'
        : service.customerName.trim();
    final phone = service.customerPhone.trim();
    final address = service.customerAddress.trim();

    final techs = service.assignments
        .map((a) => a.userName.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final doc = pw.Document();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 40, 36, 44),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'FULLTECH',
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                'Carta de Garantía',
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'Fecha: ${df.format(now)}',
                style: const pw.TextStyle(fontSize: 10),
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
                      'Orden: ${service.orderLabel}',
                      style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 6),
                    pw.Text('Cliente: $customer'),
                    if (phone.isNotEmpty) pw.Text('Teléfono: $phone'),
                    if (address.isNotEmpty) pw.Text('Dirección: $address'),
                    if (techs.isNotEmpty)
                      pw.Text('Técnico(s): ${techs.join(', ')}'),
                    if (service.serviceType.trim().isNotEmpty)
                      pw.Text('Servicio: ${service.serviceType.trim()}'),
                  ],
                ),
              ),
              pw.SizedBox(height: 14),
              pw.Text(
                'Por medio de la presente se deja constancia de la prestación del servicio indicado y se emite esta carta de garantía conforme a las condiciones establecidas por FULLTECH.',
                style: const pw.TextStyle(fontSize: 11),
              ),
              pw.SizedBox(height: 12),
              pw.Text(
                'Observaciones:',
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Container(
                height: 120,
                width: double.infinity,
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
              ),
              pw.Spacer(),
              pw.Row(
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Container(
                          height: 1,
                          color: PdfColors.grey600,
                        ),
                        pw.SizedBox(height: 6),
                        pw.Text(
                          'Firma del cliente',
                          style: const pw.TextStyle(fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 26),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Container(
                          height: 1,
                          color: PdfColors.grey600,
                        ),
                        pw.SizedBox(height: 6),
                        pw.Text(
                          'Firma y sello',
                          style: const pw.TextStyle(fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          );
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
