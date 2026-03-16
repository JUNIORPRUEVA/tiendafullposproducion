import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:signature/signature.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/company/company_settings_model.dart';
import '../../../core/company/company_settings_repository.dart';
import '../../../core/routing/routes.dart';
import '../../../core/widgets/app_drawer.dart';
import '../../../modules/cotizaciones/cotizacion_models.dart';
import '../../../modules/cotizaciones/data/cotizaciones_repository.dart';
import '../operations_models.dart';
import '../presentation/operations_permissions.dart';
import '../presentation/status_picker_sheet.dart';
import '../presentation/service_location_helpers.dart';
import '../presentation/service_pdf_exporter.dart';
import '../presentation/service_documents_editor_screen.dart';
import 'technical_service_execution_controller.dart';
import 'widgets/service_report_pdf_screen.dart';
import 'widgets/technical_execution_cards.dart';

class TechnicalServiceExecutionScreen extends ConsumerStatefulWidget {
  final String serviceId;

  const TechnicalServiceExecutionScreen({super.key, required this.serviceId});

  @override
  ConsumerState<TechnicalServiceExecutionScreen> createState() =>
      _TechnicalServiceExecutionScreenState();
}

class _TechnicalServiceExecutionScreenState
    extends ConsumerState<TechnicalServiceExecutionScreen> {
  final ImagePicker _picker = ImagePicker();
  late final SignatureController _signatureCtrl;

  bool _isInvoicePaid(ServiceModel service) {
    Map<String, String> parseKv(String raw) {
      final tokens = raw.split(RegExp(r'\s+'));
      final out = <String, String>{};
      for (final token in tokens) {
        final i = token.indexOf('=');
        if (i <= 0) continue;
        final k = token.substring(0, i).trim().toLowerCase();
        final v = token.substring(i + 1).trim();
        if (k.isEmpty || v.isEmpty) continue;
        out[k] = v;
      }
      return out;
    }

    final updates = service.updates;
    for (var i = updates.length - 1; i >= 0; i--) {
      final msg = updates[i].message.trim();
      if (!msg.startsWith('[PAGO]')) continue;
      final rest = msg.substring('[PAGO]'.length).trim();
      final kv = parseKv(rest);
      final status = (kv['estado'] ?? kv['status'] ?? 'pendiente')
          .trim()
          .toLowerCase();
      return status == 'pagado';
    }
    return false;
  }

  static const _checklistItems = <({String key, String label})>[
    (key: 'cableado_revisado', label: 'Cableado revisado'),
    (key: 'equipo_encendido', label: 'Equipo encendido'),
    (key: 'prueba_realizada', label: 'Prueba realizada'),
    (key: 'cliente_instruido', label: 'Cliente instruido'),
  ];

  @override
  void initState() {
    super.initState();
    _signatureCtrl = SignatureController(
      penStrokeWidth: 3,
      exportBackgroundColor: Colors.white,
    );
  }

  @override
  void dispose() {
    _signatureCtrl.dispose();
    super.dispose();
  }

  String _fmtDate(DateTime? dt) {
    if (dt == null) return '—';
    final v = dt.toLocal();
    final d = v.day.toString().padLeft(2, '0');
    final m = v.month.toString().padLeft(2, '0');
    final y = v.year.toString();
    return '$d/$m/$y';
  }

  String _fmtDateTime(DateTime? dt) {
    if (dt == null) return '—';
    final v = dt.toLocal();
    final d = v.day.toString().padLeft(2, '0');
    final m = v.month.toString().padLeft(2, '0');
    final y = v.year.toString();
    final hh = v.hour.toString().padLeft(2, '0');
    final mm = v.minute.toString().padLeft(2, '0');
    return '$d/$m/$y $hh:$mm';
  }

  ({String kind, String text})? _parseTechInfoMessage(String raw) {
    final msg = raw.trim();
    if (msg.isEmpty) return null;

    final re = RegExp(r'kind=([^|]+)\|text=(.*)$', dotAll: true);
    final m = re.firstMatch(msg);
    if (m == null) return null;
    final kind = (m.group(1) ?? '').trim().toLowerCase();
    final text = (m.group(2) ?? '').trim();
    if (kind.isEmpty || text.isEmpty) return null;
    return (kind: kind, text: text);
  }

  String _kindLabel(String kind) {
    switch (kind.trim().toLowerCase()) {
      case 'novedad':
        return 'Novedad';
      case 'producto':
        return 'Producto';
      case 'nota':
        return 'Nota';
      default:
        return kind.trim().isEmpty ? 'Info' : kind.trim();
    }
  }

  IconData _kindIcon(String kind) {
    switch (kind.trim().toLowerCase()) {
      case 'novedad':
        return Icons.campaign_outlined;
      case 'producto':
        return Icons.inventory_2_outlined;
      case 'nota':
        return Icons.note_add_outlined;
      default:
        return Icons.info_outline;
    }
  }

  Future<void> _previewEvidence(ServiceFileModel file) async {
    if (!mounted) return;

    final urlRaw = file.fileUrl.trim();
    if (urlRaw.isEmpty) return;

    final lower = urlRaw.toLowerCase();
    final mime = (file.mimeType ?? file.fileType).trim().toLowerCase();
    final isImage =
        mime.contains('image') ||
        lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp');
    final isVideo = mime.contains('video') || lower.endsWith('.mp4');

    final uri = Uri.tryParse(urlRaw);
    if (uri == null) {
      _showSnackBarPostFrame(
        const SnackBar(content: Text('URL de archivo inválida')),
      );
      return;
    }

    if (isVideo || !isImage) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final cs = theme.colorScheme;
        final caption = (file.caption ?? '').trim();

        return Dialog(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  color: cs.surfaceContainerHighest,
                  padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          caption.isEmpty ? 'Evidencia' : caption,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Abrir externo',
                        onPressed: () async {
                          Navigator.pop(dialogContext);
                          await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          );
                        },
                        icon: const Icon(Icons.open_in_new),
                      ),
                      IconButton(
                        tooltip: 'Cerrar',
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 520),
                  child: InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 4,
                    child: Image.network(
                      urlRaw,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stack) {
                        return Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'No se pudo cargar la imagen',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _postFrame(VoidCallback action) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      action();
    });
  }

  void _showSnackBarPostFrame(SnackBar snackBar) {
    _postFrame(() {
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(snackBar);
    });
  }

  Widget _kvRow(String k, String v) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 92,
          child: Text(k, style: const TextStyle(fontWeight: FontWeight.w900)),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(v.trim().isEmpty ? '—' : v.trim())),
      ],
    );
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

  Future<void> _openOrderDetails(ServiceModel service) async {
    if (!mounted) return;
    final id = service.id.trim();
    if (id.isEmpty) return;
    _postFrame(() {
      if (!mounted) return;
      context.push(Routes.operacionesTecnicoOrder(id));
    });
  }

  Future<void> _callClient(ServiceModel service) async {
    final phone = service.customerPhone.trim();
    if (phone.isEmpty) return;
    final uri = Uri.tryParse('tel:$phone');
    if (uri == null) return;
    await launchUrl(uri);
  }

  Future<void> _openLocation(ServiceModel service) async {
    final info = buildServiceLocationInfo(
      addressOrText: service.customerAddress,
    );
    final uri = info.mapsUri;
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<CotizacionModel?> _loadLatestQuote(String phone) async {
    final repo = ref.read(cotizacionesRepositoryProvider);
    final items = await repo.list(customerPhone: phone, take: 40);
    if (items.isEmpty) return null;
    final sorted = [...items];
    sorted.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sorted.first;
  }

  Future<void> _showCotizacionDialog(ServiceModel service) async {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final phone = service.customerPhone.trim();
    final futureQuote = phone.isEmpty
        ? Future.value(null)
        : _loadLatestQuote(phone);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Cotización',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Cerrar',
                          onPressed: () => Navigator.pop(dialogContext),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    FutureBuilder<CotizacionModel?>(
                      future: futureQuote,
                      builder: (context, snap) {
                        final quote = snap.data;
                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Items',
                                      style: theme.textTheme.titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w900,
                                          ),
                                    ),
                                  ),
                                  if (snap.connectionState !=
                                      ConnectionState.done)
                                    const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              if (quote == null)
                                Text(
                                  phone.isEmpty
                                      ? 'Sin teléfono de cliente para buscar cotización.'
                                      : 'Sin cotizaciones registradas para este cliente.',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                )
                              else ...[
                                Text(
                                  'Última cotización • ${_fmtDate(quote.createdAt)}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                for (final item in quote.items)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 4,
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            item.nombre.trim().isEmpty
                                                ? 'Item'
                                                : item.nombre.trim(),
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w800,
                                                ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Text(
                                          'x${item.qty.toStringAsFixed(0)}',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                color: cs.onSurfaceVariant,
                                                fontWeight: FontWeight.w800,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showAddInfoDialog(TechnicalExecutionController ctrl) async {
    if (!mounted) return;

    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Agregar Información'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.campaign_outlined),
                title: const Text('Agregar Novedad'),
                onTap: () => Navigator.pop(dialogContext, 'novedad'),
              ),
              ListTile(
                leading: const Icon(Icons.inventory_2_outlined),
                title: const Text('Agregar Producto'),
                onTap: () => Navigator.pop(dialogContext, 'producto'),
              ),
              ListTile(
                leading: const Icon(Icons.note_add_outlined),
                title: const Text('Agregar Nota'),
                onTap: () => Navigator.pop(dialogContext, 'nota'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
          ],
        );
      },
    );

    if (selected == null || selected.trim().isEmpty) return;
    if (!mounted) return;

    final label = switch (selected) {
      'novedad' => 'Novedad',
      'producto' => 'Producto',
      _ => 'Nota',
    };

    final text = await _askMultilineText(
      title: 'Agregar $label',
      hintText: 'Escribe los detalles…',
    );
    if (text == null || text.trim().isEmpty) return;

    await ctrl.addInfoUpdate(kind: selected, text: text.trim());
    if (!mounted) return;
    _showSnackBarPostFrame(SnackBar(content: Text('$label guardado')));
  }

  Future<String?> _askMultilineText({
    required String title,
    required String hintText,
  }) async {
    final controller = TextEditingController();
    final res = await showDialog<String?>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            maxLines: 6,
            decoration: InputDecoration(hintText: hintText),
            textInputAction: TextInputAction.newline,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, controller.text),
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    return res;
  }

  Future<void> _showContentDialog(TechnicalExecutionController ctrl) async {
    if (!mounted) return;

    final kind = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('¿Qué deseas subir?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.image_outlined),
                title: const Text('Subir Imagen'),
                onTap: () => Navigator.pop(dialogContext, 'image'),
              ),
              ListTile(
                leading: const Icon(Icons.videocam_outlined),
                title: const Text('Subir Video'),
                onTap: () => Navigator.pop(dialogContext, 'video'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
          ],
        );
      },
    );
    if (kind == null) return;
    if (!mounted) return;

    final source = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Selecciona origen'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Cámara'),
                onTap: () => Navigator.pop(dialogContext, 'camera'),
              ),
              ListTile(
                leading: const Icon(Icons.folder_open_outlined),
                title: const Text('Archivos'),
                onTap: () => Navigator.pop(dialogContext, 'files'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
          ],
        );
      },
    );
    if (source == null) return;
    if (!mounted) return;

    try {
      if (kind == 'image') {
        await _uploadImage(ctrl, source: source);
      } else {
        await _uploadVideo(ctrl, source: source);
      }
    } catch (e) {
      _showSnackBarPostFrame(
        SnackBar(content: Text('No se pudo subir contenido: $e')),
      );
    }
  }

  Future<void> _uploadImage(
    TechnicalExecutionController ctrl, {
    required String source,
  }) async {
    try {
      if (source == 'camera') {
        final xFile = await _picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 88,
        );
        if (xFile == null) return;
        await ctrl.uploadEvidenceXFile(file: xFile, caption: 'Evidencia');
        return;
      }

      final xFile = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 88,
      );
      if (xFile != null) {
        await ctrl.uploadEvidenceXFile(file: xFile, caption: 'Evidencia');
        return;
      }

      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
        withReadStream: true,
      );
      final file = result?.files.isNotEmpty == true
          ? result!.files.first
          : null;
      if (file == null) return;
      await ctrl.uploadEvidence(file: file, caption: 'Evidencia');
    } catch (e) {
      _showSnackBarPostFrame(
        SnackBar(content: Text('No se pudo subir imagen: $e')),
      );
    }
  }

  Future<void> _uploadVideo(
    TechnicalExecutionController ctrl, {
    required String source,
  }) async {
    try {
      if (source == 'camera') {
        final xFile = await _picker.pickVideo(source: ImageSource.camera);
        if (xFile == null) return;
        await ctrl.uploadEvidenceXFile(file: xFile, caption: null);
        return;
      }

      final xFile = await _picker.pickVideo(source: ImageSource.gallery);
      if (xFile != null) {
        await ctrl.uploadEvidenceXFile(file: xFile, caption: null);
        return;
      }

      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        type: FileType.custom,
        allowedExtensions: const ['mp4'],
        withReadStream: true,
      );
      final file = result?.files.isNotEmpty == true
          ? result!.files.first
          : null;
      if (file == null) return;
      await ctrl.uploadEvidence(file: file, caption: null);
    } catch (e) {
      _showSnackBarPostFrame(
        SnackBar(content: Text('No se pudo subir video: $e')),
      );
    }
  }

  Future<Uint8List> _downloadBytes(String url) async {
    final dio = ref.read(dioProvider);
    final res = await dio.get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes),
    );
    final data = res.data;
    if (data == null) return Uint8List(0);
    return Uint8List.fromList(data);
  }

  ServiceFileModel? _findClosingFile(ServiceModel service, String? fileId) {
    final id = (fileId ?? '').trim();
    if (id.isEmpty) return null;
    try {
      return service.files.firstWhere((f) => f.id == id);
    } catch (_) {
      return null;
    }
  }

  ServiceFileModel? _findLatestFileByType(ServiceModel service, String type) {
    final t = type.trim().toLowerCase();
    final candidates = service.files
        .where((f) => f.fileType.trim().toLowerCase() == t)
        .toList(growable: false);
    if (candidates.isEmpty) return null;

    candidates.sort((a, b) {
      final ad = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bd = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bd.compareTo(ad);
    });

    return candidates.first;
  }

  Future<void> _openPdfBytesPreview({
    required String fileName,
    required Future<Uint8List> Function() loadBytes,
  }) async {
    if (!mounted) return;
    final future = Completer<void>();
    _postFrame(() async {
      try {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ServiceReportPdfScreen(
              fileName: fileName,
              loadBytes: loadBytes,
              currentUser: ref.read(authStateProvider).user,
            ),
          ),
        );
        if (!future.isCompleted) future.complete();
      } catch (e, st) {
        if (!future.isCompleted) future.completeError(e, st);
      }
    });
    await future.future;
  }

  Future<void> _onInvoicePressed(ServiceModel service) async {
    final custom = _findLatestFileByType(service, 'service_invoice_custom');
    if (custom != null && custom.fileUrl.trim().isNotEmpty) {
      await _openPdfBytesPreview(
        fileName: 'Factura-${service.orderLabel}.pdf',
        loadBytes: () => _downloadBytes(custom.fileUrl.trim()),
      );
      return;
    }

    final invoiceFile = _findClosingFile(
      service,
      service.closing?.invoiceFinalFileId,
    );
    if (invoiceFile != null && invoiceFile.fileUrl.trim().isNotEmpty) {
      await _openPdfBytesPreview(
        fileName: 'Factura-${service.orderLabel}.pdf',
        loadBytes: () => _downloadBytes(invoiceFile.fileUrl.trim()),
      );
      return;
    }

    CotizacionModel? quote;
    try {
      final phone = service.customerPhone.trim();
      quote = phone.isEmpty ? null : await _loadLatestQuote(phone);
    } catch (_) {
      quote = null;
    }

    CompanySettings? company;
    try {
      company = await ref.read(companySettingsProvider.future);
    } catch (_) {
      company = null;
    }

    Uint8List? signatureBytes;
    String? signatureFileId;
    String? signatureFileUrl;
    DateTime? signedAt;
    try {
      final st = ref.read(
        technicalExecutionControllerProvider(widget.serviceId),
      );
      final sig = _readClientSignatureMeta(service, st.phaseSpecificData);
      signatureFileId = sig.fileId;
      signatureFileUrl = sig.fileUrl;
      signedAt = sig.signedAt;
      if ((signatureFileUrl ?? '').trim().isNotEmpty) {
        signatureBytes = await _downloadBytes(signatureFileUrl!.trim());
      }
    } catch (_) {
      signatureBytes = null;
    }

    await _openPdfBytesPreview(
      fileName: 'Factura-${service.orderLabel}.pdf',
      loadBytes: () => ServicePdfExporter.buildInvoicePdfBytes(
        service,
        cotizacion: quote,
        company: company,
        clientSignaturePngBytes: signatureBytes,
        clientSignatureFileId: signatureFileId,
        clientSignatureFileUrl: signatureFileUrl,
        clientSignedAt: signedAt,
      ),
    );
  }

  Future<void> _onWarrantyPressed(ServiceModel service) async {
    final custom = _findLatestFileByType(service, 'service_warranty_custom');
    if (custom != null && custom.fileUrl.trim().isNotEmpty) {
      await _openPdfBytesPreview(
        fileName: 'Carta-Garantia-${service.orderLabel}.pdf',
        loadBytes: () => _downloadBytes(custom.fileUrl.trim()),
      );
      return;
    }

    final warrantyFile = _findClosingFile(
      service,
      service.closing?.warrantyFinalFileId,
    );
    if (warrantyFile != null && warrantyFile.fileUrl.trim().isNotEmpty) {
      await _openPdfBytesPreview(
        fileName: 'Carta-Garantia-${service.orderLabel}.pdf',
        loadBytes: () => _downloadBytes(warrantyFile.fileUrl.trim()),
      );
      return;
    }

    CotizacionModel? quote;
    try {
      final phone = service.customerPhone.trim();
      quote = phone.isEmpty ? null : await _loadLatestQuote(phone);
    } catch (_) {
      quote = null;
    }

    CompanySettings? company;
    try {
      company = await ref.read(companySettingsProvider.future);
    } catch (_) {
      company = null;
    }

    Uint8List? signatureBytes;
    String? signatureFileId;
    String? signatureFileUrl;
    DateTime? signedAt;
    try {
      final st = ref.read(
        technicalExecutionControllerProvider(widget.serviceId),
      );
      final sig = _readClientSignatureMeta(service, st.phaseSpecificData);
      signatureFileId = sig.fileId;
      signatureFileUrl = sig.fileUrl;
      signedAt = sig.signedAt;
      if ((signatureFileUrl ?? '').trim().isNotEmpty) {
        signatureBytes = await _downloadBytes(signatureFileUrl!.trim());
      }
    } catch (_) {
      signatureBytes = null;
    }

    await _openPdfBytesPreview(
      fileName: 'Carta-Garantia-${service.orderLabel}.pdf',
      loadBytes: () => ServicePdfExporter.buildWarrantyLetterBytes(
        service,
        cotizacion: quote,
        company: company,
        clientSignaturePngBytes: signatureBytes,
        clientSignatureFileId: signatureFileId,
        clientSignatureFileUrl: signatureFileUrl,
        clientSignedAt: signedAt,
      ),
    );
  }

  _ClientSignatureMeta _readClientSignatureMeta(
    ServiceModel service,
    Map<String, dynamic> phaseSpecificData,
  ) {
    String asString(dynamic raw) => (raw ?? '').toString();

    DateTime? parseDate(dynamic raw) {
      if (raw == null) return null;
      return DateTime.tryParse(raw.toString());
    }

    final raw = phaseSpecificData['clientSignature'];
    if (raw is Map) {
      final map = raw.cast<String, dynamic>();
      final fileId = asString(map['fileId']).trim();
      final fileUrl = asString(map['fileUrl']).trim();
      final signedAt = parseDate(map['signedAt']);
      if (fileUrl.isNotEmpty || fileId.isNotEmpty) {
        return _ClientSignatureMeta(
          fileId: fileId.isEmpty ? null : fileId,
          fileUrl: fileUrl.isEmpty ? null : fileUrl,
          signedAt: signedAt,
        );
      }
    }

    final candidates = service.files
        .where((f) => f.fileType.trim().toLowerCase() == 'client_signature')
        .toList(growable: false);
    if (candidates.isEmpty) {
      return const _ClientSignatureMeta();
    }

    candidates.sort((a, b) {
      final ad = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bd = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bd.compareTo(ad);
    });

    final latest = candidates.first;
    final url = latest.fileUrl.trim();
    if (url.isEmpty) return const _ClientSignatureMeta();
    return _ClientSignatureMeta(
      fileId: latest.id.trim().isEmpty ? null : latest.id.trim(),
      fileUrl: url,
      signedAt: latest.createdAt,
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
    final user = ref.watch(authStateProvider).user;

    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (st.loading) {
      return Scaffold(
        drawer: buildAdaptiveDrawer(context, currentUser: user),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final service = st.service;
    if (service == null) {
      return Scaffold(
        drawer: buildAdaptiveDrawer(context, currentUser: user),
        appBar: AppBar(title: const Text('Gestión Técnica')),
        body: Center(
          child: Text(
            st.error?.trim().isNotEmpty == true
                ? st.error!.trim()
                : 'Servicio no disponible',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ),
      );
    }

    final readOnly = _isReadOnly(service: service, user: user);
    final perms = OperationsPermissions(user: user, service: service);
    final canEditDocs = perms.canCritical;

    final techInfoUpdates = service.updates
        .where((u) => u.type.trim().toLowerCase() == 'tech_info')
        .toList(growable: false);
    final sortedTechInfo = [...techInfoUpdates];
    sortedTechInfo.sort((a, b) {
      final ad = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bd = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bd.compareTo(ad);
    });

    final evidenceFiles = service.files
        .where((f) {
          final kind = f.fileType.trim().toLowerCase();
          return kind == 'evidence_final' || kind == 'video_evidence';
        })
        .toList(growable: false);
    final sortedEvidenceFiles = [...evidenceFiles];
    sortedEvidenceFiles.sort((a, b) {
      final ad = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bd = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bd.compareTo(ad);
    });

    final pendingEvidence = st.pendingEvidence
        .where((p) => p.caption.trim().toLowerCase() != 'firma del cliente')
        .toList(growable: false);

    String effectiveState(ServiceModel s) {
      final admin = (s.adminStatus ?? '').toString().trim().toLowerCase();
      if (admin.isNotEmpty) return admin;
      final order = s.orderState.toString().trim().toLowerCase();
      if (order.isNotEmpty) return order;
      return s.status.toString().trim().toLowerCase();
    }

    String? mapOrderStateToTechProgress(String orderState) {
      switch (orderState) {
        case 'en_camino':
          return 'tecnico_en_camino';
        case 'en_proceso':
          return 'instalacion_iniciada';
        case 'finalizada':
          return 'instalacion_finalizada';
        default:
          return null;
      }
    }

    final currentState = effectiveState(service);
    const allowedStates = {'en_camino', 'en_proceso', 'finalizada'};

    return Scaffold(
      drawer: buildAdaptiveDrawer(context, currentUser: user),
      appBar: AppBar(title: const Text('Gestión Técnica')),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.extended(
            heroTag: 'ops-tech-add-info',
            onPressed: readOnly ? null : () => _showAddInfoDialog(ctrl),
            icon: const Icon(Icons.add),
            label: const Text('Agregar'),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'ops-tech-content',
            onPressed: readOnly ? null : () => _showContentDialog(ctrl),
            icon: const Icon(Icons.attach_file_outlined),
            label: const Text('Contenido'),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              if ((st.error ?? '').trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      st.error!.trim(),
                      style: TextStyle(
                        color: cs.onErrorContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              if (st.saving)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: LinearProgressIndicator(minHeight: 3),
                ),

              TechnicalSectionCard(
                icon: Icons.person_outline,
                title: 'CLIENTE',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _kvRow('Cliente', service.customerName),
                    const SizedBox(height: 8),
                    _kvRow('Teléfono', service.customerPhone),
                    const SizedBox(height: 8),
                    _kvRow('Dirección', service.customerAddress),
                    const SizedBox(height: 8),
                    _kvRow('Orden', service.orderLabel),
                    const SizedBox(height: 8),
                    _kvRow('Servicio', service.serviceType),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              TechnicalSectionCard(
                icon: Icons.flash_on_outlined,
                title: 'ACCIONES',
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: () => _callClient(service),
                            icon: const Icon(Icons.call_outlined),
                            label: const Text('Llamar'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: () => _openLocation(service),
                            icon: const Icon(Icons.near_me_outlined),
                            label: const Text('Ubicación'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: () => _openOrderDetails(service),
                            icon: const Icon(Icons.receipt_long_outlined),
                            label: const Text('Orden'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: () => _showCotizacionDialog(service),
                            icon: const Icon(Icons.request_quote_outlined),
                            label: const Text('Cotización'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              TechnicalSectionCard(
                icon: Icons.note_alt_outlined,
                title: 'INFORMACIÓN',
                child: sortedTechInfo.isEmpty
                    ? Builder(
                        builder: (context) {
                          final cs = Theme.of(context).colorScheme;
                          return Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'Sin novedades / productos / notas aún.',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: cs.onSurfaceVariant,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          );
                        },
                      )
                    : Column(
                        children: [
                          for (final u in sortedTechInfo.take(40))
                            Builder(
                              builder: (context) {
                                final parsed =
                                    _parseTechInfoMessage(u.message) ??
                                    (kind: 'info', text: u.message.trim());
                                final label = _kindLabel(parsed.kind);
                                final icon = _kindIcon(parsed.kind);
                                final theme = Theme.of(context);
                                final cs = theme.colorScheme;

                                return Padding(
                                  padding: EdgeInsets.only(
                                    bottom: u == sortedTechInfo.take(40).last
                                        ? 0
                                        : 10,
                                  ),
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: cs.surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: cs.outlineVariant.withValues(
                                          alpha: 0.60,
                                        ),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(
                                              icon,
                                              size: 18,
                                              color: cs.onSurfaceVariant,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                label,
                                                style: theme
                                                    .textTheme
                                                    .titleSmall
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w900,
                                                    ),
                                              ),
                                            ),
                                            Text(
                                              _fmtDateTime(u.createdAt),
                                              style: theme.textTheme.labelSmall
                                                  ?.copyWith(
                                                    color: cs.onSurfaceVariant,
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          parsed.text,
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Por: ${u.changedBy.trim().isEmpty ? 'Sistema' : u.changedBy.trim()}',
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                                color: cs.onSurfaceVariant,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
              ),
              const SizedBox(height: 12),

              EvidenceGalleryCard(
                title: 'CONTENIDO',
                emptyLabel: 'Sin fotos/video aún',
                uploadLabel: 'Subir',
                icon: Icons.photo_library_outlined,
                files: sortedEvidenceFiles,
                pending: pendingEvidence,
                onUpload: readOnly ? null : () => _showContentDialog(ctrl),
                onPreview: _previewEvidence,
              ),
              const SizedBox(height: 12),

              TechnicalSectionCard(
                icon: Icons.playlist_add_check_circle_outlined,
                title: 'ESTADO',
                child: Builder(
                  builder: (context) {
                    final label = currentState.isEmpty
                        ? '—'
                        : StatusPickerSheet.label(currentState);

                    return InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: readOnly
                          ? null
                          : () async {
                              final picked = await StatusPickerSheet.show(
                                context,
                                current: currentState,
                                allowedStates: allowedStates,
                              );
                              if (!context.mounted || picked == null) return;

                              final next = picked.trim().toLowerCase();
                              if (next.isEmpty || next == currentState) return;

                              final nextProgress = mapOrderStateToTechProgress(
                                next,
                              );
                              if (nextProgress != null) {
                                await ctrl.setTechProgress(nextProgress);
                              } else {
                                await ctrl.changeOrderState(
                                  orderState: next,
                                  message: 'Estado actualizado por técnico',
                                );
                              }
                              if (!context.mounted) return;
                              _showSnackBarPostFrame(
                                SnackBar(
                                  content: Text(
                                    'Estado actualizado: ${StatusPickerSheet.label(next)}',
                                  ),
                                ),
                              );
                            },
                      child: IgnorePointer(
                        child: InputDecorator(
                          decoration: InputDecoration(
                            labelText: 'Estado del servicio',
                            border: const OutlineInputBorder(),
                            suffixIcon: readOnly
                                ? null
                                : const Icon(Icons.expand_more_rounded),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                StatusPickerSheet.icon(currentState),
                                size: 18,
                                color: cs.onSurfaceVariant,
                              ),
                              const SizedBox(width: 10),
                              Expanded(child: Text(label)),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),

              TechnicalSectionCard(
                icon: Icons.checklist_outlined,
                title: 'CHECKLIST',
                child: Column(
                  children: [
                    for (final item in _checklistItems)
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: ctrl.checklistValue(item.key),
                        title: Text(item.label),
                        onChanged: readOnly
                            ? null
                            : (v) => ctrl.setChecklistItem(item.key, v == true),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              TechnicalSectionCard(
                icon: Icons.picture_as_pdf_outlined,
                title: 'DOCUMENTOS',
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: () => _onInvoicePressed(service),
                            icon: const Icon(Icons.receipt_long_outlined),
                            label: const Text('Factura'),
                          ),
                          if (canEditDocs) ...[
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: () async {
                                final ok = await Navigator.of(context).push<bool>(
                                  MaterialPageRoute(
                                    builder: (_) => ServiceDocumentsEditorScreen(
                                      service: service,
                                      type: ServiceDocumentType.invoice,
                                    ),
                                  ),
                                );
                                if (!mounted) return;
                                if (ok == true) {
                                  unawaited(
                                    ref
                                        .read(
                                          technicalExecutionControllerProvider(widget.serviceId)
                                              .notifier,
                                        )
                                        .load(),
                                  );
                                }
                              },
                              icon: const Icon(Icons.edit_outlined),
                              label: const Text('Editar'),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: () => _onWarrantyPressed(service),
                            icon: const Icon(Icons.verified_outlined),
                            label: const Text('Garantía'),
                          ),
                          if (canEditDocs) ...[
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: () async {
                                final ok = await Navigator.of(context).push<bool>(
                                  MaterialPageRoute(
                                    builder: (_) => ServiceDocumentsEditorScreen(
                                      service: service,
                                      type: ServiceDocumentType.warranty,
                                    ),
                                  ),
                                );
                                if (!mounted) return;
                                if (ok == true) {
                                  unawaited(
                                    ref
                                        .read(
                                          technicalExecutionControllerProvider(widget.serviceId)
                                              .notifier,
                                        )
                                        .load(),
                                  );
                                }
                              },
                              icon: const Icon(Icons.edit_outlined),
                              label: const Text('Editar'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              TechnicalSectionCard(
                icon: Icons.payments_outlined,
                title: 'PAGO',
                child: SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Factura pagada'),
                  value: _isInvoicePaid(service),
                  onChanged: (readOnly || st.saving)
                      ? null
                      : (v) async {
                          await ctrl.setInvoicePaid(v);
                          if (!context.mounted) return;
                          _showSnackBarPostFrame(
                            SnackBar(
                              content: Text(
                                v
                                    ? 'Factura marcada como pagada'
                                    : 'Factura marcada como pendiente',
                              ),
                            ),
                          );
                        },
                ),
              ),
              const SizedBox(height: 12),

              TechnicalSectionCard(
                icon: Icons.draw_outlined,
                title: 'FIRMA DEL CLIENTE',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 180,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: cs.outlineVariant),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Signature(
                          controller: _signatureCtrl,
                          backgroundColor: cs.surfaceContainerHighest,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: readOnly
                                ? null
                                : () {
                                    _signatureCtrl.clear();
                                  },
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Limpiar'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: readOnly
                                ? null
                                : () async {
                                    final bytes = await _signatureCtrl
                                        .toPngBytes();
                                    if (!mounted) return;
                                    if (bytes == null || bytes.isEmpty) {
                                      _showSnackBarPostFrame(
                                        const SnackBar(
                                          content: Text('Firma vacía'),
                                        ),
                                      );
                                      return;
                                    }
                                    await ctrl.uploadClientSignaturePng(
                                      pngBytes: bytes,
                                    );
                                    if (!mounted) return;
                                    _showSnackBarPostFrame(
                                      const SnackBar(
                                        content: Text('Firma guardada'),
                                      ),
                                    );
                                  },
                            icon: const Icon(Icons.cloud_upload_outlined),
                            label: const Text('Guardar'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              TechnicalSectionCard(
                icon: Icons.sentiment_satisfied_alt_outlined,
                title: 'CLIENTE SATISFECHO',
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: readOnly
                            ? null
                            : () => ctrl.toggleClientApproved(true),
                        icon: Icon(
                          st.clientApproved
                              ? Icons.check_circle
                              : Icons.check_circle_outline,
                        ),
                        label: const Text('SI'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: readOnly
                            ? null
                            : () => ctrl.toggleClientApproved(false),
                        icon: Icon(
                          !st.clientApproved
                              ? Icons.cancel
                              : Icons.cancel_outlined,
                        ),
                        label: const Text('NO'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClientSignatureMeta {
  final String? fileId;
  final String? fileUrl;
  final DateTime? signedAt;

  const _ClientSignatureMeta({this.fileId, this.fileUrl, this.signedAt});
}
