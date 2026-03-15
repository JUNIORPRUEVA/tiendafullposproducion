import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:chewie/chewie.dart';
import 'package:video_player/video_player.dart';
import 'package:signature/signature.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:dio/dio.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/routing/routes.dart';
import '../operations_models.dart';
import '../presentation/operations_permissions.dart';
import 'technical_service_execution_controller.dart';
import 'widgets/technical_execution_cards.dart';
import 'widgets/service_execution_form.dart';

class TechnicalServiceExecutionScreen extends ConsumerStatefulWidget {
  final String serviceId;

  const TechnicalServiceExecutionScreen({super.key, required this.serviceId});

  @override
  ConsumerState<TechnicalServiceExecutionScreen> createState() =>
      _TechnicalServiceExecutionScreenState();
}

class _TechnicalServiceExecutionScreenState
    extends ConsumerState<TechnicalServiceExecutionScreen> {
  late final TextEditingController _notesCtrl;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _notesCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  bool _isReadOnly({required ServiceModel service, required dynamic user}) {
    final perms = OperationsPermissions(user: user, service: service);
    if (!perms.canOperate) return true;
    if (perms.isAdminLike) return false;

    final status = parseStatus(service.status);
    return status == ServiceStatus.closed ||
        status == ServiceStatus.cancelled ||
        status == ServiceStatus.completed;
  }

  bool _isLikelyVideo(ServiceFileModel file) {
    final ft = (file.mimeType ?? file.fileType).trim().toLowerCase();
    final url = file.fileUrl.trim().toLowerCase();
    if (ft.contains('video')) return true;
    return url.endsWith('.mp4');
  }

  bool _isLikelyImage(ServiceFileModel file) {
    final ft = (file.mimeType ?? file.fileType).trim().toLowerCase();
    final url = file.fileUrl.trim().toLowerCase();
    if (ft.contains('image')) return true;
    return url.endsWith('.png') ||
        url.endsWith('.jpg') ||
        url.endsWith('.jpeg') ||
        url.endsWith('.webp');
  }

  bool _isLikelySignature(
    ServiceFileModel file,
    Map<String, dynamic> phaseData,
  ) {
    final caption = (file.caption ?? '').trim().toLowerCase();
    if (caption.contains('firma')) return true;

    final sig = phaseData['clientSignature'];
    if (sig is Map) {
      final fileId = (sig['fileId'] ?? '').toString().trim();
      if (fileId.isNotEmpty && file.id == fileId) return true;
      final fileUrl = (sig['fileUrl'] ?? '').toString().trim();
      if (fileUrl.isNotEmpty && file.fileUrl == fileUrl) return true;
    }

    return false;
  }

  List<ExecutionChecklistItem> _buildDynamicChecklist(ServiceModel service) {
    final haystack = [
      service.orderType,
      service.serviceType,
      service.category,
      service.title,
      service.description,
    ].join(' ').toLowerCase();

    bool has(String s) => haystack.contains(s);

    if (has('cam') || has('cctv') || has('cámara') || has('camera')) {
      return const [
        ExecutionChecklistItem(
          key: 'pre_check_power',
          label: 'Verificar energía y punto de instalación',
        ),
        ExecutionChecklistItem(
          key: 'pre_check_internet',
          label: 'Verificar internet / NVR / red',
        ),
        ExecutionChecklistItem(
          key: 'mounting_done',
          label: 'Instalación física y fijaciones completas',
        ),
        ExecutionChecklistItem(
          key: 'cable_management',
          label: 'Canalización y orden de cableado',
        ),
        ExecutionChecklistItem(
          key: 'view_angle',
          label: 'Ajustar ángulos y enfoque',
        ),
        ExecutionChecklistItem(
          key: 'recording_ok',
          label: 'Validar grabación / monitoreo (prueba)',
        ),
        ExecutionChecklistItem(
          key: 'client_training',
          label: 'Explicar uso al cliente',
        ),
      ];
    }

    if (has('mantenimiento') || has('preventivo') || has('correctivo')) {
      return const [
        ExecutionChecklistItem(
          key: 'diagnosis',
          label: 'Diagnóstico inicial documentado',
        ),
        ExecutionChecklistItem(
          key: 'cleaning',
          label: 'Limpieza y ajustes realizados',
        ),
        ExecutionChecklistItem(
          key: 'replace_parts',
          label: 'Repuestos/consumibles verificados (si aplica)',
          required: false,
        ),
        ExecutionChecklistItem(
          key: 'tests',
          label: 'Pruebas de funcionamiento completadas',
        ),
        ExecutionChecklistItem(
          key: 'recommendations',
          label: 'Recomendaciones registradas en notas',
        ),
      ];
    }

    if (has('motor') || has('portón') || has('porton') || has('gate')) {
      return const [
        ExecutionChecklistItem(
          key: 'safety',
          label: 'Validar seguridad (freno/sensores/obstrucción)',
        ),
        ExecutionChecklistItem(
          key: 'mechanics',
          label: 'Revisión mecánica (rieles/rodajes/engranes)',
        ),
        ExecutionChecklistItem(
          key: 'electrical',
          label: 'Revisión eléctrica / conexión',
        ),
        ExecutionChecklistItem(
          key: 'limits',
          label: 'Ajuste de límites / recorrido',
        ),
        ExecutionChecklistItem(
          key: 'remote_test',
          label: 'Prueba con controles/remotos',
        ),
      ];
    }

    if (has('garant') || has('warranty')) {
      return const [
        ExecutionChecklistItem(
          key: 'issue_reproduced',
          label: 'Reproducir falla reportada',
        ),
        ExecutionChecklistItem(key: 'root_cause', label: 'Causa identificada'),
        ExecutionChecklistItem(
          key: 'fix_applied',
          label: 'Corrección aplicada',
        ),
        ExecutionChecklistItem(
          key: 'final_test',
          label: 'Prueba final con cliente',
        ),
      ];
    }

    if (has('levant') || has('survey') || has('inspecci') || has('cotiz')) {
      return const [
        ExecutionChecklistItem(
          key: 'site_photos',
          label: 'Fotos del sitio y puntos clave (mínimo 5)',
        ),
        ExecutionChecklistItem(
          key: 'measurements',
          label: 'Mediciones registradas',
        ),
        ExecutionChecklistItem(
          key: 'constraints',
          label: 'Limitaciones/condiciones documentadas',
        ),
        ExecutionChecklistItem(
          key: 'client_needs',
          label: 'Requerimientos del cliente claros',
        ),
      ];
    }

    return const [
      ExecutionChecklistItem(
        key: 'scope_confirmed',
        label: 'Alcance confirmado con el cliente',
      ),
      ExecutionChecklistItem(
        key: 'work_done',
        label: 'Trabajo realizado según orden',
      ),
      ExecutionChecklistItem(
        key: 'tests',
        label: 'Pruebas de funcionamiento completadas',
      ),
      ExecutionChecklistItem(key: 'cleanup', label: 'Área limpia y ordenada'),
      ExecutionChecklistItem(
        key: 'notes_done',
        label: 'Notas y recomendaciones registradas',
      ),
    ];
  }

  Widget _billingManagementCard(ServiceModel service) {
    String invoiceStatus() {
      final c = service.closing;
      if (c == null) return 'No generada';
      if ((c.invoiceFinalFileId ?? '').isNotEmpty) return 'Final';
      if ((c.invoiceApprovedFileId ?? '').isNotEmpty) return 'Aprobada';
      if ((c.invoiceDraftFileId ?? '').isNotEmpty) {
        return 'Pendiente aprobación';
      }
      return 'En proceso';
    }

    String warrantyStatus() {
      final c = service.closing;
      if (c == null) return 'No generada';
      if ((c.warrantyFinalFileId ?? '').isNotEmpty) return 'Final';
      if ((c.warrantyApprovedFileId ?? '').isNotEmpty) return 'Aprobada';
      if ((c.warrantyDraftFileId ?? '').isNotEmpty) {
        return 'Pendiente aprobación';
      }
      return 'En proceso';
    }

    String approvalStatus() {
      final s = service.closing?.approvalStatus.toUpperCase().trim() ?? '';
      if (s == 'APPROVED') return 'Aprobada';
      if (s == 'REJECTED') return 'Rechazada';
      if (s == 'PENDING') return 'Pendiente';
      return s.isEmpty ? 'N/D' : s;
    }

    String signatureStatus() {
      final s = service.closing?.signatureStatus.toUpperCase().trim() ?? '';
      if (s == 'SIGNED') return 'Firmada';
      if (s == 'SKIPPED') return 'No firmada (opcional)';
      if (s == 'PENDING') return 'Pendiente';
      return s.isEmpty ? 'N/D' : s;
    }

    Widget row(String label, String value) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
            ),
            const SizedBox(width: 12),
            Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
    }

    return TechnicalSectionCard(
      icon: Icons.receipt_long_outlined,
      title: 'Gestión de facturación del servicio',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          row('Factura', invoiceStatus()),
          row('Garantía', warrantyStatus()),
          row('Aprobación', approvalStatus()),
          row('Firma cliente', signatureStatus()),
        ],
      ),
    );
  }

  Future<void> _showAddChangeDialog(
    BuildContext context,
    TechnicalExecutionController ctrl,
  ) async {
    final typeCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final qtyCtrl = TextEditingController();
    final extraCtrl = TextEditingController();
    final noteCtrl = TextEditingController();

    bool approved = false;

    double? parseNum(String v) {
      final t = v.trim();
      if (t.isEmpty) return null;
      return double.tryParse(t.replaceAll(',', '.'));
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setState) {
            return AlertDialog(
              title: const Text('Agregar novedad / producto'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: typeCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Tipo',
                        hintText: 'Ej: Producto adicional',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: descCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Descripción',
                        hintText: 'Ej: Cable UTP 10m',
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: qtyCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Cantidad',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: extraCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Costo extra',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: noteCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nota (opcional)',
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Aprobado por el cliente'),
                      value: approved,
                      onChanged: (v) => setState(() => approved = v),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () async {
                    final type = typeCtrl.text.trim();
                    final desc = descCtrl.text.trim();
                    if (type.isEmpty || desc.isEmpty) return;
                    Navigator.pop(dialogContext);
                    await ctrl.addChange(
                      type: type,
                      description: desc,
                      quantity: parseNum(qtyCtrl.text),
                      extraCost: parseNum(extraCtrl.text),
                      clientApproved: approved,
                      note: noteCtrl.text.trim().isEmpty
                          ? null
                          : noteCtrl.text.trim(),
                    );
                  },
                  child: const Text('Agregar'),
                ),
              ],
            );
          },
        );
      },
    );

    typeCtrl.dispose();
    descCtrl.dispose();
    qtyCtrl.dispose();
    extraCtrl.dispose();
    noteCtrl.dispose();
  }

  Future<void> _captureSignature(
    BuildContext context,
    TechnicalExecutionController ctrl,
  ) async {
    final sigCtrl = SignatureController(
      penStrokeWidth: 3,
      exportBackgroundColor: Colors.white,
    );

    final bytes = await showDialog<Uint8List?>(
      context: context,
      builder: (dialogContext) {
        final cs = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          title: const Text('Firma del cliente'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 220,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Signature(
                      controller: sigCtrl,
                      backgroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () => sigCtrl.clear(),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Limpiar'),
                    ),
                    const Spacer(),
                    Text(
                      'Firme dentro del recuadro',
                      style: Theme.of(dialogContext).textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                if (sigCtrl.isEmpty) return;
                final nav = Navigator.of(dialogContext);
                final png = await sigCtrl.toPngBytes();
                nav.pop(png);
              },
              child: const Text('Guardar firma'),
            ),
          ],
        );
      },
    );

    sigCtrl.dispose();

    if (bytes == null || bytes.isEmpty) return;
    if (!mounted) return;
    await ctrl.uploadClientSignaturePng(pngBytes: bytes);
  }

  Future<void> _finishWithValidation({
    required BuildContext context,
    required TechnicalExecutionState st,
    required TechnicalExecutionController ctrl,
    required List<ExecutionChecklistItem> checklist,
  }) async {
    final service = st.service;
    if (service == null) return;

    final photos = service.files
        .where(_isLikelyImage)
        .where((f) => !_isLikelySignature(f, st.phaseSpecificData))
        .length;
    final videos = service.files.where(_isLikelyVideo).length;

    final requiredChecklist = checklist.where((i) => i.required).toList();
    final checklistOk = requiredChecklist.every(
      (i) => ctrl.checklistValue(i.key),
    );

    final sig = st.phaseSpecificData['clientSignature'];
    final sigUrl = sig is Map ? (sig['fileUrl'] ?? '').toString().trim() : '';
    final hasSignature = sigUrl.isNotEmpty;

    final missing = <String>[];
    if (st.arrivedAt == null) missing.add('Registrar llegada');
    if (st.startedAt == null) missing.add('Registrar inicio');
    if (!checklistOk) missing.add('Completar checklist');
    if (photos < 5) missing.add('Mínimo 5 fotos ($photos/5)');
    if (videos < 1) missing.add('Mínimo 1 video');
    if (!st.clientApproved) missing.add('Aprobación del cliente');
    if (!hasSignature) missing.add('Firma del cliente');
    if (st.pendingEvidence.isNotEmpty) {
      missing.add('Esperar evidencias en subida');
    }

    if (missing.isNotEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('Faltan requisitos: ${missing.join(' · ')}')),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Finalizar servicio'),
          content: const Text(
            '¿Confirmas que deseas registrar la finalización?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Finalizar'),
            ),
          ],
        );
      },
    );
    if (ok != true) return;
    ctrl.markFinishedNow();
  }

  Future<Uint8List?> _tryDownloadBytes(String url) async {
    try {
      final res = await Dio().get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      final data = res.data;
      if (data == null || data.isEmpty) return null;
      return Uint8List.fromList(data);
    } catch (_) {
      return null;
    }
  }

  Future<void> _exportPdf({
    required BuildContext context,
    required TechnicalExecutionState st,
    required TechnicalExecutionController ctrl,
    required List<ExecutionChecklistItem> checklist,
  }) async {
    final service = st.service;
    if (service == null) return;

    final sig = st.phaseSpecificData['clientSignature'];
    final sigUrl = sig is Map ? (sig['fileUrl'] ?? '').toString().trim() : '';

    Uint8List? signatureBytes;
    if (sigUrl.isNotEmpty) {
      signatureBytes = await _tryDownloadBytes(sigUrl);
    }

    final arrivalGps = st.phaseSpecificData['arrivalGps'];
    final lat = arrivalGps is Map ? (arrivalGps['lat']?.toString() ?? '') : '';
    final lng = arrivalGps is Map ? (arrivalGps['lng']?.toString() ?? '') : '';
    final acc = arrivalGps is Map
        ? (arrivalGps['accuracy']?.toString() ?? '')
        : '';

    final doc = pw.Document();

    String fmtDt(DateTime? dt) {
      if (dt == null) return '—';
      final v = dt.toLocal();
      final d = v.day.toString().padLeft(2, '0');
      final m = v.month.toString().padLeft(2, '0');
      final y = v.year.toString();
      final h = v.hour.toString().padLeft(2, '0');
      final mi = v.minute.toString().padLeft(2, '0');
      return '$d/$m/$y $h:$mi';
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (ctx) {
          return [
            pw.Text(
              'Reporte de Servicio Técnico',
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 10),
            pw.Text('Cliente: ${service.customerName}'),
            pw.Text('Dirección: ${service.customerAddress}'),
            pw.Text(
              'Servicio: ${service.title.isNotEmpty ? service.title : service.description}',
            ),
            pw.Text(
              'Tipo: ${service.orderType} · ${service.serviceType} · ${service.category}',
            ),
            pw.SizedBox(height: 10),
            pw.Text(
              'Ejecución',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.Text('Llegada: ${fmtDt(st.arrivedAt)}'),
            pw.Text('Inicio: ${fmtDt(st.startedAt)}'),
            pw.Text('Finalización: ${fmtDt(st.finishedAt)}'),
            if (lat.isNotEmpty && lng.isNotEmpty)
              pw.Text('GPS llegada: $lat, $lng (±$acc m)'),
            pw.SizedBox(height: 10),
            pw.Text('Aprobación cliente: ${st.clientApproved ? 'Sí' : 'No'}'),
            pw.SizedBox(height: 10),
            pw.Text(
              'Checklist',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                for (final item in checklist)
                  pw.Text(
                    '- [${ctrl.checklistValue(item.key) ? 'X' : ' '}] ${item.label}',
                  ),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Text(
              'Notas',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(st.notes.trim().isEmpty ? '—' : st.notes.trim()),
            pw.SizedBox(height: 10),
            pw.Text(
              'Cambios / Productos',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            if (st.changes.isEmpty)
              pw.Text('—')
            else
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  for (final c in st.changes)
                    pw.Text(
                      '- ${c.type.isNotEmpty ? '${c.type}: ' : ''}${c.description}',
                    ),
                ],
              ),
            pw.SizedBox(height: 10),
            pw.Text(
              'Firma del cliente',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            if (signatureBytes != null)
              pw.Container(
                height: 120,
                width: 300,
                decoration: pw.BoxDecoration(border: pw.Border.all()),
                padding: const pw.EdgeInsets.all(6),
                child: pw.Image(
                  pw.MemoryImage(signatureBytes),
                  fit: pw.BoxFit.contain,
                ),
              )
            else
              pw.Text(
                sigUrl.isNotEmpty
                    ? 'Firma registrada (no se pudo cargar imagen)'
                    : '—',
              ),
          ];
        },
      ),
    );

    final bytes = await doc.save();
    if (!context.mounted) return;
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: 'reporte_servicio_${service.id}.pdf',
    );
  }

  Future<String?> _askEvidenceNote(
    BuildContext context, {
    required String title,
    required String hintText,
    required bool required,
  }) async {
    final theme = Theme.of(context);
    final ctrl = TextEditingController();
    String? error;

    final res = await showDialog<String?>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setState) {
            return AlertDialog(
              title: Text(title),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    required ? 'Nota (requerida)' : 'Nota (opcional)',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: ctrl,
                    autofocus: true,
                    maxLength: 140,
                    decoration: InputDecoration(
                      hintText: hintText,
                      errorText: error,
                    ),
                    onChanged: (_) {
                      if (error != null) {
                        setState(() => error = null);
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () {
                    final v = ctrl.text.trim();
                    if (required && v.isEmpty) {
                      setState(() => error = 'Requerido');
                      return;
                    }
                    Navigator.pop(dialogContext, v);
                  },
                  child: const Text('Continuar'),
                ),
              ],
            );
          },
        );
      },
    );

    ctrl.dispose();
    if (res == null) return null;
    final trimmed = res.trim();
    if (required) {
      return trimmed.isEmpty ? null : trimmed;
    }
    return trimmed.isEmpty ? '' : trimmed;
  }

  Future<void> _pickAndUploadImageEvidence(
    BuildContext context,
    TechnicalExecutionController ctrl,
  ) async {
    Future<void> uploadXFile(XFile xFile) async {
      if (!context.mounted) return;
      await Future<void>.delayed(Duration.zero);
      if (!context.mounted) return;

      final caption = await _askEvidenceNote(
        context,
        title: 'Agregar nota',
        hintText: 'Ej: Evidencia después de instalación',
        required: true,
      );
      if (caption == null || caption.trim().isEmpty) return;
      if (!context.mounted) return;
      await ctrl.uploadEvidenceXFile(file: xFile, caption: caption);
    }

    try {
      final xFile = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 88,
      );
      if (xFile != null) {
        await uploadXFile(xFile);
        return;
      }
    } catch (_) {
      // fallback below
    }

    // Fallback (desktop/web): file picker
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
      withReadStream: !kIsWeb,
      withData: kIsWeb,
      dialogTitle: 'Selecciona una imagen',
    );

    final file = result?.files.isNotEmpty == true ? result!.files.first : null;
    if (file == null) return;

    if (!context.mounted) return;
    await Future<void>.delayed(Duration.zero);
    if (!context.mounted) return;

    final caption = await _askEvidenceNote(
      context,
      title: 'Agregar nota',
      hintText: 'Ej: Evidencia después de instalación',
      required: true,
    );
    if (caption == null || caption.trim().isEmpty) return;
    if (!context.mounted) return;
    await ctrl.uploadEvidence(file: file, caption: caption);
  }

  Future<void> _captureAndUploadImageEvidence(
    BuildContext context,
    TechnicalExecutionController ctrl,
  ) async {
    try {
      final xFile = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 88,
      );
      if (xFile == null) return;
      if (!context.mounted) return;

      await Future<void>.delayed(Duration.zero);
      if (!context.mounted) return;

      final caption = await _askEvidenceNote(
        context,
        title: 'Agregar nota',
        hintText: 'Ej: Evidencia después de instalación',
        required: true,
      );
      if (caption == null || caption.trim().isEmpty) return;
      if (!context.mounted) return;

      await ctrl.uploadEvidenceXFile(file: xFile, caption: caption);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Cámara no disponible: $e')));
    }
  }

  Future<void> _pickAndUploadVideoEvidence(
    BuildContext context,
    TechnicalExecutionController ctrl,
  ) async {
    Future<void> uploadXFile(XFile xFile) async {
      if (!context.mounted) return;
      await Future<void>.delayed(Duration.zero);
      if (!context.mounted) return;

      final note = await _askEvidenceNote(
        context,
        title: 'Agregar nota al video',
        hintText: 'Ej: Video de prueba (opcional)',
        required: false,
      );
      if (note == null) return;
      if (!context.mounted) return;

      await ctrl.uploadEvidenceXFile(
        file: xFile,
        caption: note.trim().isEmpty ? null : note,
      );
    }

    try {
      final xFile = await _picker.pickVideo(source: ImageSource.gallery);
      if (xFile != null) {
        await uploadXFile(xFile);
        return;
      }
    } catch (_) {
      // fallback below
    }

    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: const ['mp4'],
      withReadStream: !kIsWeb,
      withData: kIsWeb,
      dialogTitle: 'Selecciona un video',
    );

    final file = result?.files.isNotEmpty == true ? result!.files.first : null;
    if (file == null) return;

    if (!context.mounted) return;
    await Future<void>.delayed(Duration.zero);
    if (!context.mounted) return;

    final note = await _askEvidenceNote(
      context,
      title: 'Agregar nota al video',
      hintText: 'Ej: Video de prueba (opcional)',
      required: false,
    );
    if (note == null) return;
    if (!context.mounted) return;

    await ctrl.uploadEvidence(
      file: file,
      caption: note.trim().isEmpty ? null : note,
    );
  }

  Future<void> _captureAndUploadVideoEvidence(
    BuildContext context,
    TechnicalExecutionController ctrl,
  ) async {
    try {
      final xFile = await _picker.pickVideo(source: ImageSource.camera);
      if (xFile == null) return;

      if (!context.mounted) return;
      await Future<void>.delayed(Duration.zero);
      if (!context.mounted) return;

      final note = await _askEvidenceNote(
        context,
        title: 'Agregar nota al video',
        hintText: 'Ej: Video de prueba (opcional)',
        required: false,
      );
      if (note == null) return;
      if (!context.mounted) return;

      await ctrl.uploadEvidenceXFile(
        file: xFile,
        caption: note.trim().isEmpty ? null : note,
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Cámara no disponible: $e')));
    }
  }

  Future<void> _previewEvidence(
    BuildContext context,
    ServiceFileModel file,
  ) async {
    final url = file.fileUrl.trim();
    if (url.isEmpty) return Future.value();

    final ft = (file.mimeType ?? file.fileType).trim().toLowerCase();
    final isVideo = ft.contains('video') || url.toLowerCase().endsWith('.mp4');
    if (isVideo) {
      return showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return _VideoPreviewDialog(url: url);
        },
      );
    }

    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: 1,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: InteractiveViewer(
                      child: Image.network(
                        url,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stack) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                url,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IconButton(
                      tooltip: 'Cerrar',
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(
      technicalExecutionControllerProvider(widget.serviceId),
    );
    final ctrl = ref.read(
      technicalExecutionControllerProvider(widget.serviceId).notifier,
    );

    final auth = ref.watch(authStateProvider);

    final service = st.service;
    if (_notesCtrl.text != st.notes) {
      _notesCtrl.text = st.notes;
      _notesCtrl.selection = TextSelection.fromPosition(
        TextPosition(offset: _notesCtrl.text.length),
      );
    }

    final title = service == null
        ? 'Servicio'
        : (service.customerName.trim().isEmpty
              ? 'Servicio'
              : service.customerName.trim());

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: IconButton(
          onPressed: () {
            if (context.canPop()) {
              context.pop();
              return;
            }
            context.go(Routes.operacionesTecnico);
          },
          icon: const Icon(Icons.arrow_back),
        ),
        actions: [
          if (st.saving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              tooltip: 'Guardar',
              onPressed: () => ctrl.saveNow(),
              icon: const Icon(Icons.save_outlined),
            ),
        ],
      ),
      body: st.loading
          ? const Center(child: CircularProgressIndicator())
          : service == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(st.error ?? 'No se pudo cargar el servicio'),
              ),
            )
          : RefreshIndicator(
              onRefresh: () => ctrl.load(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
                children: [
                  if (st.error != null) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(st.error!),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  ServiceHeaderCard(service: service),
                  const SizedBox(height: 12),
                  _billingManagementCard(service),
                  const SizedBox(height: 12),
                  ExecutionTimelineCard(
                    arrivedAt: st.arrivedAt,
                    startedAt: st.startedAt,
                    finishedAt: st.finishedAt,
                    onArrived: () => ctrl.markArrivedNow(),
                    onStarted: () => ctrl.markStartedNow(),
                    onFinished: () {
                      final checklist = _buildDynamicChecklist(service);
                      unawaited(
                        _finishWithValidation(
                          context: context,
                          st: st,
                          ctrl: ctrl,
                          checklist: checklist,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  DynamicExecutionChecklistCard(
                    items: _buildDynamicChecklist(service),
                    checklistData: st.checklistData,
                    onChanged: (k, v) => ctrl.setChecklistItem(k, v),
                  ),
                  const SizedBox(height: 12),
                  ClientApprovalCard(
                    value: st.clientApproved,
                    onChanged: (v) => ctrl.toggleClientApproved(v),
                  ),
                  const SizedBox(height: 12),
                  TechnicalSectionCard(
                    icon: Icons.draw_outlined,
                    title: 'Firma del cliente',
                    trailing: FilledButton.tonalIcon(
                      onPressed: () => _captureSignature(context, ctrl),
                      icon: const Icon(Icons.edit),
                      label: const Text('Capturar'),
                    ),
                    child: Builder(
                      builder: (context) {
                        final cs = Theme.of(context).colorScheme;
                        final sig = st.phaseSpecificData['clientSignature'];
                        final sigUrl = sig is Map
                            ? (sig['fileUrl'] ?? '').toString().trim()
                            : '';

                        if (sigUrl.isEmpty) {
                          return Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.border_color_outlined,
                                  color: cs.onSurfaceVariant,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Firma pendiente',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: cs.onSurfaceVariant,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        return ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: AspectRatio(
                              aspectRatio: 16 / 7,
                              child: Image.network(
                                sigUrl,
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stack) {
                                  return Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Text(
                                        sigUrl,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  TechnicalNotesCard(
                    controller: _notesCtrl,
                    onChanged: ctrl.updateNotes,
                    readOnly: _isReadOnly(service: service, user: auth.user),
                  ),
                  const SizedBox(height: 12),
                  TechnicalSectionCard(
                    icon: Icons.tune_outlined,
                    title: 'Detalles por tipo de servicio',
                    child: ServiceExecutionForm(
                      service: service,
                      phaseSpecificData: st.phaseSpecificData,
                      readOnly: _isReadOnly(service: service, user: auth.user),
                      onChanged: (k, v) => ctrl.updatePhaseSpecificField(k, v),
                    ),
                  ),
                  const SizedBox(height: 12),
                  EvidenceGalleryCard(
                    title:
                        'Fotos del servicio (${service.files.where(_isLikelyImage).where((f) => !_isLikelySignature(f, st.phaseSpecificData)).length}/5)',
                    emptyLabel: 'Sin evidencias aún',
                    icon: Icons.photo_camera_outlined,
                    files: service.files
                        .where(_isLikelyImage)
                        .where(
                          (f) => !_isLikelySignature(f, st.phaseSpecificData),
                        )
                        .toList(),
                    pending: st.pendingEvidence
                        .where((p) => p.isImage)
                        .toList(),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton.filledTonal(
                          tooltip: 'Cámara',
                          onPressed: () =>
                              _captureAndUploadImageEvidence(context, ctrl),
                          icon: const Icon(Icons.photo_camera_outlined),
                        ),
                        const SizedBox(width: 6),
                        IconButton.filledTonal(
                          tooltip: 'Galería',
                          onPressed: () =>
                              _pickAndUploadImageEvidence(context, ctrl),
                          icon: const Icon(Icons.photo_library_outlined),
                        ),
                      ],
                    ),
                    onPreview: (f) => _previewEvidence(context, f),
                  ),
                  const SizedBox(height: 12),
                  EvidenceGalleryCard(
                    title:
                        'Videos del servicio (${service.files.where(_isLikelyVideo).length}/1)',
                    emptyLabel: 'Sin videos aún',
                    icon: Icons.videocam_outlined,
                    files: service.files.where(_isLikelyVideo).toList(),
                    pending: st.pendingEvidence
                        .where((p) => p.isVideo)
                        .toList(),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton.filledTonal(
                          tooltip: 'Cámara',
                          onPressed: () =>
                              _captureAndUploadVideoEvidence(context, ctrl),
                          icon: const Icon(Icons.videocam_outlined),
                        ),
                        const SizedBox(width: 6),
                        IconButton.filledTonal(
                          tooltip: 'Galería',
                          onPressed: () =>
                              _pickAndUploadVideoEvidence(context, ctrl),
                          icon: const Icon(Icons.video_library_outlined),
                        ),
                      ],
                    ),
                    onPreview: (f) => _previewEvidence(context, f),
                  ),
                  const SizedBox(height: 12),
                  ServiceChangesCard(
                    changes: st.changes,
                    onAdd: () => _showAddChangeDialog(context, ctrl),
                    canDelete: (c) {
                      final userId = (auth.user?.id ?? '').toString().trim();
                      if (userId.isNotEmpty && c.createdByUserId == userId) {
                        return true;
                      }
                      final perms = OperationsPermissions(
                        user: auth.user,
                        service: service,
                      );
                      return perms.isAdminLike;
                    },
                    onDelete: (c) => ctrl.deleteChange(c),
                  ),
                  const SizedBox(height: 12),
                  TechnicalSectionCard(
                    icon: Icons.fact_check_outlined,
                    title: 'Cierre del servicio',
                    child: Column(
                      children: [
                        OutlinedButton.icon(
                          onPressed: () {
                            final checklist = _buildDynamicChecklist(service);
                            unawaited(
                              _exportPdf(
                                context: context,
                                st: st,
                                ctrl: ctrl,
                                checklist: checklist,
                              ),
                            );
                          },
                          icon: const Icon(Icons.picture_as_pdf_outlined),
                          label: const Text('Exportar PDF'),
                        ),
                        const SizedBox(height: 10),
                        Builder(
                          builder: (context) {
                            final cs = Theme.of(context).colorScheme;
                            final photos = service.files
                                .where(_isLikelyImage)
                                .where(
                                  (f) => !_isLikelySignature(
                                    f,
                                    st.phaseSpecificData,
                                  ),
                                )
                                .length;
                            final videos = service.files
                                .where(_isLikelyVideo)
                                .length;
                            final sig = st.phaseSpecificData['clientSignature'];
                            final sigUrl = sig is Map
                                ? (sig['fileUrl'] ?? '').toString().trim()
                                : '';

                            final req = _buildDynamicChecklist(
                              service,
                            ).where((i) => i.required).toList();
                            final done = req
                                .where((i) => ctrl.checklistValue(i.key))
                                .length;

                            return Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Requisitos',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(fontWeight: FontWeight.w900),
                                  ),
                                  const SizedBox(height: 8),
                                  Text('Checklist: $done/${req.length}'),
                                  Text('Fotos: $photos/5'),
                                  Text('Videos: $videos/1'),
                                  Text(
                                    'Aprobación: ${st.clientApproved ? 'Sí' : 'No'}',
                                  ),
                                  Text(
                                    'Firma: ${sigUrl.isNotEmpty ? 'Sí' : 'No'}',
                                  ),
                                  if (st.pendingEvidence.isNotEmpty)
                                    Text(
                                      'Subidas pendientes: ${st.pendingEvidence.length}',
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _VideoPreviewDialog extends StatefulWidget {
  final String url;

  const _VideoPreviewDialog({required this.url});

  @override
  State<_VideoPreviewDialog> createState() => _VideoPreviewDialogState();
}

class _VideoPreviewDialogState extends State<_VideoPreviewDialog> {
  late final VideoPlayerController _controller;
  ChewieController? _chewie;
  late final Future<void> _init;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _init = _controller.initialize().then((_) {
      if (!mounted) return;

      final cs = Theme.of(context).colorScheme;
      _chewie = ChewieController(
        videoPlayerController: _controller,
        autoPlay: true,
        looping: false,
        allowFullScreen: true,
        allowMuting: true,
        showControls: true,
        materialProgressColors: ChewieProgressColors(
          playedColor: cs.primary,
          handleColor: cs.primary,
          bufferedColor: cs.primary.withValues(alpha: 0.25),
          backgroundColor: cs.onSurface.withValues(alpha: 0.20),
        ),
        errorBuilder: (context, errorMessage) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'No se pudo reproducir el video\n$errorMessage',
                textAlign: TextAlign.center,
              ),
            ),
          );
        },
      );
    });
  }

  @override
  void dispose() {
    _chewie?.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Dialog(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(
                color: cs.surface,
                child: FutureBuilder<void>(
                  future: _init,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (snap.hasError ||
                        !_controller.value.isInitialized ||
                        _chewie == null) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'No se pudo reproducir el video',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      );
                    }

                    final aspect = _controller.value.aspectRatio;
                    return Center(
                      child: AspectRatio(
                        aspectRatio: aspect > 0 ? aspect : 16 / 9,
                        child: Chewie(controller: _chewie!),
                      ),
                    );
                  },
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                tooltip: 'Cerrar',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
