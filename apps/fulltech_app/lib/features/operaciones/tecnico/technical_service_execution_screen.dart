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
import '../../../core/routing/routes.dart';
import '../../../modules/cotizaciones/cotizacion_models.dart';
import '../../../modules/cotizaciones/data/cotizaciones_repository.dart';
import '../operations_models.dart';
import '../presentation/operations_permissions.dart';
import '../presentation/service_location_helpers.dart';
import '../presentation/service_pdf_exporter.dart';
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

  static const _checklistItems = <({String key, String label})>[
    (key: 'cableado_revisado', label: 'Cableado revisado'),
    (key: 'equipo_encendido', label: 'Equipo encendido'),
    (key: 'prueba_realizada', label: 'Prueba realizada'),
    (key: 'cliente_instruido', label: 'Cliente instruido'),
  ];

  static const _techProgressOptions = <({
    String key,
    String label,
    IconData icon,
  })>[
    (
      key: 'tecnico_en_camino',
      label: 'Técnico en camino',
      icon: Icons.directions_car_filled_outlined,
    ),
    (
      key: 'tecnico_en_el_lugar',
      label: 'Técnico en el lugar',
      icon: Icons.place_outlined,
    ),
    (
      key: 'instalacion_iniciada',
      label: 'Instalación iniciada',
      icon: Icons.play_circle_outline,
    ),
    (
      key: 'instalacion_finalizada',
      label: 'Instalación finalizada',
      icon: Icons.check_circle_outline,
    ),
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

  Widget _kvRow(String k, String v) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 92,
          child: Text(
            k,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
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
    context.push(Routes.operacionesTecnicoOrder(service.id));
  }

  Future<void> _callClient(ServiceModel service) async {
    final phone = service.customerPhone.trim();
    if (phone.isEmpty) return;
    final uri = Uri.tryParse('tel:$phone');
    if (uri == null) return;
    await launchUrl(uri);
  }

  Future<void> _openLocation(ServiceModel service) async {
    final info = buildServiceLocationInfo(addressOrText: service.customerAddress);
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
    final futureQuote = phone.isEmpty ? Future.value(null) : _loadLatestQuote(phone);

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
                                      style: theme.textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  if (snap.connectionState != ConnectionState.done)
                                    const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
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
                                    padding: const EdgeInsets.symmetric(vertical: 4),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            item.nombre.trim().isEmpty
                                                ? 'Item'
                                                : item.nombre.trim(),
                                            style: theme.textTheme.bodyMedium?.copyWith(
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Text(
                                          'x${item.qty.toStringAsFixed(0)}',
                                          style: theme.textTheme.bodySmall?.copyWith(
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
    final messenger = ScaffoldMessenger.maybeOf(context);

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
    messenger?.showSnackBar(SnackBar(content: Text('$label guardado')));
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
    final messenger = ScaffoldMessenger.maybeOf(context);

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
      messenger?.showSnackBar(SnackBar(content: Text('No se pudo subir contenido: $e')));
    }
  }

  Future<void> _uploadImage(
    TechnicalExecutionController ctrl, {
    required String source,
  }) async {
    final messenger = ScaffoldMessenger.maybeOf(context);

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
      final file = result?.files.isNotEmpty == true ? result!.files.first : null;
      if (file == null) return;
      await ctrl.uploadEvidence(file: file, caption: 'Evidencia');
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text('No se pudo subir imagen: $e')));
    }
  }

  Future<void> _uploadVideo(
    TechnicalExecutionController ctrl, {
    required String source,
  }) async {
    final messenger = ScaffoldMessenger.maybeOf(context);

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
      final file = result?.files.isNotEmpty == true ? result!.files.first : null;
      if (file == null) return;
      await ctrl.uploadEvidence(file: file, caption: null);
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text('No se pudo subir video: $e')));
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

  Future<void> _openPdfBytesPreview({
    required String fileName,
    required Future<Uint8List> Function() loadBytes,
  }) async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ServiceReportPdfScreen(
          fileName: fileName,
          loadBytes: loadBytes,
        ),
      ),
    );
  }

  Future<void> _onInvoicePressed(ServiceModel service) async {
    final invoiceFile = _findClosingFile(service, service.closing?.invoiceFinalFileId);
    if (invoiceFile != null && invoiceFile.fileUrl.trim().isNotEmpty) {
      await _openPdfBytesPreview(
        fileName: 'Factura-${service.orderLabel}.pdf',
        loadBytes: () => _downloadBytes(invoiceFile.fileUrl.trim()),
      );
      return;
    }

    await _openPdfBytesPreview(
      fileName: 'Factura-${service.orderLabel}.pdf',
      loadBytes: () => ServicePdfExporter.buildServiceDetailPdfBytes(service),
    );
  }

  Future<void> _onWarrantyPressed(ServiceModel service) async {
    final warrantyFile = _findClosingFile(service, service.closing?.warrantyFinalFileId);
    if (warrantyFile != null && warrantyFile.fileUrl.trim().isNotEmpty) {
      await _openPdfBytesPreview(
        fileName: 'Carta-Garantia-${service.orderLabel}.pdf',
        loadBytes: () => _downloadBytes(warrantyFile.fileUrl.trim()),
      );
      return;
    }

    await _openPdfBytesPreview(
      fileName: 'Carta-Garantia-${service.orderLabel}.pdf',
      loadBytes: () => ServicePdfExporter.buildWarrantyLetterBytes(service),
    );
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(technicalExecutionControllerProvider(widget.serviceId));
    final ctrl =
        ref.read(technicalExecutionControllerProvider(widget.serviceId).notifier);

    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (st.loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final service = st.service;
    if (service == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Gestión Técnica')),
        body: Center(
          child: Text(
            st.error?.trim().isNotEmpty == true ? st.error!.trim() : 'Servicio no disponible',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ),
      );
    }

    final user = ref.watch(authStateProvider).user;
    final readOnly = _isReadOnly(service: service, user: user);

    final currentKey = (st.phaseSpecificData['techProgress'] ?? '').toString().trim();
    final selectedKey = _techProgressOptions.any((o) => o.key == currentKey)
        ? currentKey
        : _techProgressOptions.first.key;

    return Scaffold(
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
                icon: Icons.playlist_add_check_circle_outlined,
                title: 'ESTADO',
                child: Builder(
                  builder: (context) {
                    final messenger = ScaffoldMessenger.maybeOf(context);
                    return DropdownButtonFormField<String>(
                      key: ValueKey(selectedKey),
                      initialValue: selectedKey,
                      decoration: const InputDecoration(
                        labelText: 'Estado del servicio',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final opt in _techProgressOptions)
                          DropdownMenuItem(
                            value: opt.key,
                            child: Row(
                              children: [
                                Icon(opt.icon, size: 18, color: cs.onSurfaceVariant),
                                const SizedBox(width: 10),
                                Expanded(child: Text(opt.label)),
                              ],
                            ),
                          ),
                      ],
                      onChanged: readOnly
                          ? null
                          : (v) async {
                              final next = (v ?? '').trim();
                              if (next.isEmpty) return;
                              await ctrl.setTechProgress(next);
                              if (!context.mounted) return;
                              final label =
                                  _techProgressOptions.firstWhere((o) => o.key == next).label;
                              messenger?.showSnackBar(
                                SnackBar(content: Text('Estado actualizado: $label')),
                              );
                            },
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
                      child: FilledButton.tonalIcon(
                        onPressed: () => _onInvoicePressed(service),
                        icon: const Icon(Icons.receipt_long_outlined),
                        label: const Text('Factura'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: () => _onWarrantyPressed(service),
                        icon: const Icon(Icons.verified_outlined),
                        label: const Text('Garantía'),
                      ),
                    ),
                  ],
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
                                    setState(() {});
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
                                    final messenger = ScaffoldMessenger.maybeOf(context);
                                    final bytes = await _signatureCtrl.toPngBytes();
                                    if (!mounted) return;
                                    if (bytes == null || bytes.isEmpty) {
                                      messenger?.showSnackBar(
                                        const SnackBar(content: Text('Firma vacía')),
                                      );
                                      return;
                                    }
                                    await ctrl.uploadClientSignaturePng(pngBytes: bytes);
                                    if (!mounted) return;
                                    messenger?.showSnackBar(
                                      const SnackBar(content: Text('Firma guardada')),
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
                        onPressed: readOnly ? null : () => ctrl.toggleClientApproved(true),
                        icon: Icon(
                          st.clientApproved ? Icons.check_circle : Icons.check_circle_outline,
                        ),
                        label: const Text('SI'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: readOnly ? null : () => ctrl.toggleClientApproved(false),
                        icon: Icon(
                          !st.clientApproved ? Icons.cancel : Icons.cancel_outlined,
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
