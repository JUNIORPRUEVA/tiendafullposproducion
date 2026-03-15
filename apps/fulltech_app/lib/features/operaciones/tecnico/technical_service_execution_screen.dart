import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/routing/routes.dart';
import '../operations_models.dart';
import '../presentation/operations_permissions.dart';
import 'technical_service_execution_controller.dart';
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
  late final TextEditingController _notesCtrl;

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

  String _fmtDateTime(DateTime? dt) {
    if (dt == null) return '—';
    final v = dt.toLocal();
    final h = v.hour.toString().padLeft(2, '0');
    final m = v.minute.toString().padLeft(2, '0');
    return '${v.day}/${v.month}/${v.year} $h:$m';
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

  Future<String?> _askEvidenceCaption(BuildContext context) async {
    final ctrl = TextEditingController();
    String? error;

    final res = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Descripción de la evidencia'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Escribe un texto corto (ej: antes/después, serial, detalle).',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: ctrl,
                    autofocus: true,
                    maxLength: 140,
                    decoration: InputDecoration(
                      hintText: 'Ej: Evidencia después de instalación',
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
                    if (v.isEmpty) {
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
    return res?.trim().isEmpty == true ? null : res;
  }

  Future<void> _pickAndUploadEvidence(
    BuildContext context,
    TechnicalExecutionController ctrl,
  ) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'mp4'],
      withReadStream: !kIsWeb,
      withData: kIsWeb,
      dialogTitle: 'Selecciona una evidencia (imagen o video)',
    );

    final file = result?.files.isNotEmpty == true ? result!.files.first : null;
    if (file == null) return;

    if (!context.mounted) return;

    // Some platforms/plugins can briefly disturb the widget tree after the native picker.
    // Deferring the next dialog to the next cycle avoids using a context while routes/inherited
    // dependencies are still settling.
    await Future<void>.delayed(Duration.zero);

    if (!context.mounted) return;

    final caption = await _askEvidenceCaption(context);
    if (caption == null || caption.trim().isEmpty) return;

    if (!context.mounted) return;

    await ctrl.uploadEvidence(file: file, caption: caption);
  }

  Future<void> _previewEvidence(BuildContext context, ServiceFileModel file) {
    final url = file.fileUrl.trim();
    if (url.isEmpty) return Future.value();

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

  Future<void> _openAddChangeDialog(
    BuildContext context,
    TechnicalExecutionController ctrl,
  ) async {
    final typeCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final qtyCtrl = TextEditingController();
    final extraCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    bool clientApproved = false;

    double? parseNum(String raw) {
      final t = raw.trim();
      if (t.isEmpty) return null;
      return double.tryParse(t.replaceAll(',', '.'));
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Agregar cambio'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: typeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Tipo (ej: material, repuesto, visita)',
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(labelText: 'Descripción'),
                  minLines: 2,
                  maxLines: 4,
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
                  minLines: 1,
                  maxLines: 3,
                ),
                const SizedBox(height: 6),
                StatefulBuilder(
                  builder: (context, setState) {
                    return SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Aprobado por cliente'),
                      value: clientApproved,
                      onChanged: (v) => setState(() => clientApproved = v),
                    );
                  },
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
                await ctrl.addChange(
                  type: type,
                  description: desc,
                  quantity: parseNum(qtyCtrl.text),
                  extraCost: parseNum(extraCtrl.text),
                  clientApproved: clientApproved,
                  note: noteCtrl.text,
                );
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: const Text('Agregar'),
            ),
          ],
        );
      },
    );

    typeCtrl.dispose();
    descCtrl.dispose();
    qtyCtrl.dispose();
    extraCtrl.dispose();
    noteCtrl.dispose();
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
    final userId = (auth.user?.id ?? '').trim();

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
                  ExecutionTimelineCard(
                    arrivedAt: st.arrivedAt,
                    startedAt: st.startedAt,
                    finishedAt: st.finishedAt,
                    onArrived: () => ctrl.markArrivedNow(),
                    onStarted: () => ctrl.markStartedNow(),
                    onFinished: () => ctrl.markFinishedNow(),
                  ),
                  const SizedBox(height: 12),
                  ClientApprovalCard(
                    value: st.clientApproved,
                    onChanged: (v) => ctrl.toggleClientApproved(v),
                  ),
                  const SizedBox(height: 12),
                  TechnicalNotesCard(
                    controller: _notesCtrl,
                    onChanged: ctrl.updateNotes,
                    readOnly: _isReadOnly(service: service, user: auth.user),
                  ),
                  const SizedBox(height: 12),
                  ServiceChecklistCard(
                    steps: service.steps,
                    onToggle: ctrl.toggleStep,
                  ),
                  const SizedBox(height: 12),
                  EvidenceGalleryCard(
                    files: service.files,
                    pending: st.pendingEvidence,
                    onUpload: () => _pickAndUploadEvidence(context, ctrl),
                    onPreview: (f) => _previewEvidence(context, f),
                  ),
                  const SizedBox(height: 12),
                  ServiceChangesCard(
                    changes: st.changes,
                    onAdd: () => _openAddChangeDialog(context, ctrl),
                    canDelete: (c) {
                      final perms = OperationsPermissions(
                        user: auth.user,
                        service: service,
                      );
                      final canDeleteOwn =
                          userId.isNotEmpty && c.createdByUserId == userId;
                      return canDeleteOwn || perms.isAdminLike;
                    },
                    onDelete: (c) => ctrl.deleteChange(c),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Historial',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 6),
                          if (service.updates.isEmpty)
                            const Text('Sin historial')
                          else
                            ...service.updates
                                .take(20)
                                .map(
                                  (u) => ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(u.message),
                                    subtitle: Text(
                                      '${u.changedBy} • ${_fmtDateTime(u.createdAt)}',
                                    ),
                                  ),
                                ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
