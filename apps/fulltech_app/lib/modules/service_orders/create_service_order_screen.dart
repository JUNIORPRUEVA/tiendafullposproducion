import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:video_player/video_player.dart';

import '../../core/auth/app_role.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/routing/app_navigator.dart';
import '../../core/routing/routes.dart';
import '../../core/utils/app_feedback.dart';
import '../../core/utils/video_preview_controller.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/app_navigation.dart';
import '../clientes/cliente_model.dart';
import '../cotizaciones/cotizacion_models.dart';
import 'application/create_service_order_controller.dart';
import 'service_order_models.dart';

class CreateServiceOrderScreen extends ConsumerStatefulWidget {
  const CreateServiceOrderScreen({super.key, this.args});

  final ServiceOrderCreateArgs? args;

  @override
  ConsumerState<CreateServiceOrderScreen> createState() =>
      _CreateServiceOrderScreenState();
}

class _CreateServiceOrderScreenState
    extends ConsumerState<CreateServiceOrderScreen> {
  late final TextEditingController _technicalNoteController;
  late final TextEditingController _extraRequirementsController;

  @override
  void initState() {
    super.initState();
    _technicalNoteController = TextEditingController(
      text: widget.args?.cloneSource?.technicalNote ?? '',
    );
    _extraRequirementsController = TextEditingController(
      text: widget.args?.cloneSource?.extraRequirements ?? '',
    );
  }

  @override
  void dispose() {
    _technicalNoteController.dispose();
    _extraRequirementsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = createServiceOrderControllerProvider(widget.args);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final user = ref.watch(authStateProvider).user;
    final isTechnician = user?.appRole.isTechnician ?? false;
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= kDesktopShellBreakpoint;
    final shellFallback = widget.args?.isCloneMode == true
        ? Routes.serviceOrderById(widget.args!.cloneSource!.id)
        : Routes.serviceOrders;

    return Scaffold(
      drawer: isDesktop ? null : buildAdaptiveDrawer(context, currentUser: user),
      appBar: AppBar(
        leading: AppNavigator.maybeBackButton(
          context,
          fallbackRoute: shellFallback,
        ),
        title: Text(state.isCloneMode ? 'Clonar orden' : 'Crear orden'),
        actions: [
          TextButton.icon(
            onPressed: () => context.go(Routes.serviceOrders),
            icon: const Icon(Icons.list_alt_rounded),
            label: const Text('Órdenes'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: isDesktop
          ? null
          : FloatingActionButton.extended(
            onPressed: state.submitting || state.uploadingEvidence || !isTechnician
                  ? null
                  : () => _showEvidenceActions(context, controller),
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('Evidencia'),
            ),
      body: SafeArea(
        child: state.loading && !state.initialized
            ? const Center(child: CircularProgressIndicator())
            : LayoutBuilder(
                builder: (context, constraints) {
                  final desktop = constraints.maxWidth >= kDesktopShellBreakpoint;
                  final form = _buildFormColumn(
                    context,
                    desktop: desktop,
                    state: state,
                    controller: controller,
                    isTechnician: isTechnician,
                  );
                  final evidencePanel = _EvidencePreviewPanel(
                    evidences: state.evidences,
                    canManageEvidence: isTechnician,
                    uploadLabel: state.uploadLabel,
                    uploadProgress: state.uploadProgress,
                    uploading: state.uploadingEvidence,
                    onRemove: isTechnician ? controller.removeEvidence : null,
                    onAddNote: isTechnician
                      ? () => _addNoteEvidence(context, controller)
                      : null,
                    onAddImage: isTechnician
                      ? () => _addImageEvidence(context, controller)
                      : null,
                    onAddVideo: isTechnician
                      ? () => _addVideoEvidence(context, controller)
                      : null,
                    onRecordVideo: isTechnician && _supportsVideoRecording
                      ? () => _recordVideoEvidence(context, controller)
                      : null,
                  );

                  if (!desktop) {
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                      children: [form, const SizedBox(height: 16), evidencePanel],
                    );
                  }

                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 7, child: SingleChildScrollView(child: form)),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 5,
                          child: SingleChildScrollView(child: evidencePanel),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: FilledButton.icon(
          onPressed: state.submitting || state.uploadingEvidence
              ? null
              : () async {
                  try {
                    final result = await controller.submit(
                      technicalNote: _technicalNoteController.text,
                      extraRequirements: _extraRequirementsController.text,
                    );
                    if (!context.mounted) return;
                    await AppFeedback.showInfo(
                      context,
                      result.warningMessage ??
                          (state.isCloneMode
                              ? 'Orden clonada correctamente'
                              : 'Orden creada correctamente'),
                    );
                    if (!context.mounted) return;
                    context.go(Routes.serviceOrderById(result.order.id));
                  } catch (_) {
                    if (!context.mounted) return;
                    final message = ref
                            .read(provider)
                            .actionError ??
                        'No se pudo guardar la orden';
                    await AppFeedback.showError(context, message);
                  }
                },
          icon: state.submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: Text(state.isCloneMode ? 'Crear nueva orden' : 'Guardar orden'),
        ),
      ),
    );
  }

  Widget _buildFormColumn(
    BuildContext context, {
    required bool desktop,
    required CreateServiceOrderState state,
    required CreateServiceOrderController controller,
    required bool isTechnician,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HeroCard(
          isCloneMode: state.isCloneMode,
          onViewOrders: () => context.go(Routes.serviceOrders),
          evidenceCount: state.evidences.length,
        ),
        if (state.isCloneMode) ...[
          const SizedBox(height: 16),
          _CloneBanner(source: state.cloneSource!),
        ],
        if (state.error != null) ...[
          const SizedBox(height: 16),
          _ErrorCard(message: state.error!),
        ],
        if (state.actionError != null) ...[
          const SizedBox(height: 16),
          _InfoCard(
            message: state.actionError!,
            color: Theme.of(context).colorScheme.errorContainer,
          ),
        ],
        if (state.uploadingEvidence) ...[
          const SizedBox(height: 16),
          _UploadProgressCard(
            label: state.uploadLabel ?? 'Subiendo archivo',
            progress: state.uploadProgress,
          ),
        ],
        const SizedBox(height: 16),
        _SectionCard(
          title: 'Cliente y cotización',
          subtitle:
              'Selecciona el cliente y usa su cotización vinculada antes de crear la orden.',
          child: Column(
            children: [
              _SelectionTile(
                label: 'Cliente',
                value: state.selectedClient?.nombre ?? 'Buscar cliente',
                hint: state.selectedClient?.telefono,
                enabled: !state.isCloneMode,
                icon: Icons.search_rounded,
                onTap: state.isCloneMode
                    ? null
                    : () => _pickClient(context, state, controller),
              ),
              const SizedBox(height: 12),
              if (state.loading)
                const LinearProgressIndicator(minHeight: 3)
              else if ((state.quotationMessage ?? '').trim().isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      state.quotationMessage!,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ),
              if (state.quotations.length > 1) ...[
                DropdownButtonFormField<String>(
                  initialValue: state.selectedQuotation?.id,
                  decoration: const InputDecoration(
                    labelText: 'Cotización',
                    border: OutlineInputBorder(),
                  ),
                  items: state.quotations
                      .map(
                        (quotation) => DropdownMenuItem<String>(
                          value: quotation.id,
                          child: Text(
                            '${quotation.customerName} · ${quotation.items.length} items',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: state.isCloneMode
                      ? null
                      : (value) {
                          final selected = state.quotations
                              .where((item) => item.id == value)
                              .cast<CotizacionModel?>()
                              .firstWhere((item) => item != null, orElse: () => null);
                          controller.selectQuotation(selected);
                        },
                ),
                const SizedBox(height: 12),
              ],
              if (state.selectedQuotation != null)
                _QuotationSummaryCard(quotation: state.selectedQuotation!),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: 'Configuración de servicio',
          subtitle: 'Define la categoría, el tipo de servicio y el técnico responsable.',
          child: Column(
            children: [
              DropdownButtonFormField<ServiceOrderCategory>(
                initialValue: state.category,
                decoration: const InputDecoration(
                  labelText: 'Categoría',
                  border: OutlineInputBorder(),
                ),
                items: ServiceOrderCategory.values
                    .map(
                      (category) => DropdownMenuItem(
                        value: category,
                        child: Text(category.label),
                      ),
                    )
                    .toList(growable: false),
                onChanged: state.isCloneMode
                    ? null
                    : (value) {
                        if (value != null) controller.setCategory(value);
                      },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<ServiceOrderType>(
                initialValue: state.serviceType,
                decoration: const InputDecoration(
                  labelText: 'Tipo de servicio',
                  border: OutlineInputBorder(),
                ),
                items: ServiceOrderType.values
                    .map(
                      (type) => DropdownMenuItem(
                        value: type,
                        child: Text(type.label),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) => controller.setServiceType(value),
              ),
              if (isTechnician) ...[
                const SizedBox(height: 12),
                _SelectionTile(
                  label: 'Técnico',
                  value: state.selectedTechnician?.nombreCompleto ?? 'Seleccionar técnico',
                  hint: state.selectedTechnician?.telefono,
                  icon: Icons.engineering_outlined,
                  onTap: () => _pickTechnician(context, state, controller),
                ),
              ],
            ],
          ),
        ),
        if (!desktop) ...[
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Evidencias',
            subtitle: isTechnician
                ? 'Agrega notas, imágenes o videos antes de guardar la orden.'
                : 'Vista de evidencias. Solo el técnico puede agregar o eliminar archivos.',
            trailing: isTechnician
                ? OutlinedButton.icon(
                    onPressed: state.uploadingEvidence
                        ? null
                        : () => _showEvidenceActions(context, controller),
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text('Agregar'),
                  )
                : null,
            child: _EvidenceChatList(
              evidences: state.evidences,
              onRemove: isTechnician ? controller.removeEvidence : null,
              compact: true,
            ),
          ),
        ],
        if (isTechnician) ...[
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Notas',
            subtitle: 'Información operativa y requisitos adicionales para el equipo.',
            child: Column(
              children: [
                TextField(
                  controller: _technicalNoteController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Nota técnica',
                    hintText: 'Describe el trabajo a realizar',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _extraRequirementsController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Requisitos extra',
                    hintText: 'Accesos, materiales o instrucciones adicionales',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  bool get _supportsVideoRecording {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  Future<void> _pickClient(
    BuildContext context,
    CreateServiceOrderState state,
    CreateServiceOrderController controller,
  ) async {
    final selected = await _showEntityPicker<ClienteModel>(
      context,
      title: 'Seleccionar cliente',
      items: state.clients,
      itemTitle: (client) => client.nombre,
      itemSubtitle: (client) => client.telefono,
    );
    if (selected == null || !mounted) return;
    await controller.selectClient(selected);
  }

  Future<void> _pickTechnician(
    BuildContext context,
    CreateServiceOrderState state,
    CreateServiceOrderController controller,
  ) async {
    final selected = await _showEntityPicker(
      context,
      title: 'Seleccionar técnico',
      items: state.technicians,
      itemTitle: (user) => user.nombreCompleto,
      itemSubtitle: (user) => user.telefono,
      allowEmpty: true,
      emptyLabel: 'Sin asignar',
    );
    if (!mounted) return;
    controller.selectTechnician(selected);
  }

  Future<T?> _showEntityPicker<T>(
    BuildContext context, {
    required String title,
    required List<T> items,
    required String Function(T item) itemTitle,
    String? Function(T item)? itemSubtitle,
    bool allowEmpty = false,
    String emptyLabel = '',
  }) async {
    final queryController = TextEditingController();
    final isDesktop = MediaQuery.sizeOf(context).width >= kDesktopShellBreakpoint;

    Future<T?> showPicker(Widget Function(StateSetter setState) builder) {
      if (isDesktop) {
        return showDialog<T?>(
          context: context,
          builder: (dialogContext) => StatefulBuilder(
            builder: (context, setState) => Dialog(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 540, maxHeight: 640),
                child: builder(setState),
              ),
            ),
          ),
        );
      }

      return showModalBottomSheet<T?>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: StatefulBuilder(
            builder: (context, setState) => SizedBox(
              height: MediaQuery.sizeOf(sheetContext).height * 0.82,
              child: builder(setState),
            ),
          ),
        ),
      );
    }

    return showPicker((setState) {
      final query = queryController.text.trim().toLowerCase();
      final filtered = items.where((item) {
        final text = itemTitle(item).toLowerCase();
        final subtitle = (itemSubtitle?.call(item) ?? '').toLowerCase();
        return query.isEmpty || text.contains(query) || subtitle.contains(query);
      }).toList(growable: false);

      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title, style: Theme.of(context).textTheme.titleLarge),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: queryController,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Buscar...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            if (allowEmpty)
              ListTile(
                leading: const Icon(Icons.remove_circle_outline),
                title: Text(emptyLabel),
                onTap: () => Navigator.of(context).pop(null),
              ),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(child: Text('No hay resultados'))
                  : ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = filtered[index];
                        return ListTile(
                          title: Text(itemTitle(item)),
                          subtitle: itemSubtitle == null
                              ? null
                              : Text(itemSubtitle(item) ?? ''),
                          onTap: () => Navigator.of(context).pop(item),
                        );
                      },
                    ),
            ),
          ],
        ),
      );
    });
  }

  Future<void> _showEvidenceActions(
    BuildContext context,
    CreateServiceOrderController controller,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.notes_outlined),
                title: const Text('Agregar nota'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _addNoteEvidence(context, controller);
                },
              ),
              ListTile(
                leading: const Icon(Icons.image_outlined),
                title: const Text('Subir imagen'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _addImageEvidence(context, controller);
                },
              ),
              ListTile(
                leading: const Icon(Icons.videocam_outlined),
                title: const Text('Subir video'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _addVideoEvidence(context, controller);
                },
              ),
              if (_supportsVideoRecording)
                ListTile(
                  leading: const Icon(Icons.fiber_manual_record_outlined),
                  title: const Text('Grabar video'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _recordVideoEvidence(context, controller);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _addNoteEvidence(
    BuildContext context,
    CreateServiceOrderController controller,
  ) async {
    final value = await _promptMultilineInput(
      context,
      title: 'Agregar nota',
      label: 'Escribe la evidencia en texto',
    );
    if ((value ?? '').trim().isEmpty) return;
    controller.addTextEvidence(value!.trim());
  }

  Future<void> _addVideoEvidence(
    BuildContext context,
    CreateServiceOrderController controller,
  ) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp4', 'mov', 'webm', 'mkv'],
      withData: kIsWeb,
    );
    final file = result?.files.single;
    if (file == null) return;
    try {
      await controller.addVideoEvidence(
        fileName: file.name,
        bytes: file.bytes,
        path: file.path,
        sizeBytes: file.size,
      );
    } catch (_) {
      if (!context.mounted) return;
      await AppFeedback.showError(
        context,
        ref.read(createServiceOrderControllerProvider(widget.args)).actionError ??
            'No se pudo subir el video',
      );
    }
  }

  Future<void> _addImageEvidence(
    BuildContext context,
    CreateServiceOrderController controller,
  ) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = result?.files.single;
    final bytes = file?.bytes;
    if (file == null) return;
    try {
      await controller.addImageEvidence(
        bytes: bytes,
        path: file.path,
        fileName: file.name,
        sizeBytes: file.size,
      );
    } catch (_) {
      if (!context.mounted) return;
      await AppFeedback.showError(
        context,
        ref.read(createServiceOrderControllerProvider(widget.args)).actionError ??
            'No se pudo subir la imagen',
      );
    }
  }

  Future<void> _recordVideoEvidence(
    BuildContext context,
    CreateServiceOrderController controller,
  ) async {
    try {
      final picker = ImagePicker();
      final file = await picker.pickVideo(source: ImageSource.camera);
      if (file == null) return;
      await controller.addVideoEvidence(
        fileName: file.name.isEmpty ? path.basename(file.path) : file.name,
        path: file.path,
      );
    } catch (_) {
      if (!context.mounted) return;
      await AppFeedback.showError(
        context,
        ref.read(createServiceOrderControllerProvider(widget.args)).actionError ??
            'No se pudo grabar o subir el video',
      );
    }
  }

  Future<String?> _promptMultilineInput(
    BuildContext context, {
    required String title,
    required String label,
  }) {
    final textController = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: textController,
            maxLines: 5,
            decoration: InputDecoration(labelText: label),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, textController.text),
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.isCloneMode,
    required this.onViewOrders,
    required this.evidenceCount,
  });

  final bool isCloneMode;
  final VoidCallback onViewOrders;
  final int evidenceCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF12344D), Color(0xFF1F6E6C)],
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isCloneMode ? 'Nueva orden desde historial' : 'Centro de creación de órdenes',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Formulario rápido, validación clara y evidencias listas antes de crear.',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: Colors.white.withValues(alpha: 0.84),
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: onViewOrders,
                icon: const Icon(Icons.list_alt_rounded),
                label: const Text('Ver órdenes'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _HeroStat(label: 'Estado', value: isCloneMode ? 'Clonación' : 'Nueva orden'),
              _HeroStat(label: 'Evidencias', value: '$evidenceCount preparadas'),
              _HeroStat(label: 'Flujo', value: 'Cliente → orden → detalle'),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _CloneBanner extends StatelessWidget {
  const _CloneBanner({required this.source});

  final ServiceOrderModel source;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF16324F),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Clonando orden finalizada',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 6),
          Text(
            '${source.category.label} · ${source.serviceType.label}',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return _InfoCard(
      message: message,
      color: Theme.of(context).colorScheme.errorContainer,
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.message, required this.color});

  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(message),
    );
  }
}

class _UploadProgressCard extends StatelessWidget {
  const _UploadProgressCard({required this.label, required this.progress});

  final String label;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final percent = (progress * 100).clamp(0, 100).toStringAsFixed(0);
    return Card(
      elevation: 0,
      color: const Color(0xFFE9F5F1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 10),
            LinearProgressIndicator(value: progress <= 0 ? null : progress),
            const SizedBox(height: 8),
            Text('$percent% completado'),
          ],
        ),
      ),
    );
  }
}

class _SelectionTile extends StatelessWidget {
  const _SelectionTile({
    required this.label,
    required this.value,
    required this.icon,
    this.hint,
    this.enabled = true,
    this.onTap,
  });

  final String label;
  final String value;
  final String? hint;
  final IconData icon;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          children: [
            Icon(icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 4),
                  Text(value, style: Theme.of(context).textTheme.titleSmall),
                  if ((hint ?? '').trim().isNotEmpty)
                    Text(hint!, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}

class _QuotationSummaryCard extends StatelessWidget {
  const _QuotationSummaryCard({required this.quotation});

  final CotizacionModel quotation;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7FB),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Resumen de cotización',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _SummaryChip(label: 'Total', value: money.format(quotation.total)),
              _SummaryChip(label: 'Items', value: '${quotation.items.length}'),
              _SummaryChip(
                label: 'Creada',
                value: DateFormat('dd/MM/yyyy').format(quotation.createdAt),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.titleSmall),
        ],
      ),
    );
  }
}

class _EvidencePreviewPanel extends StatelessWidget {
  const _EvidencePreviewPanel({
    required this.evidences,
    required this.canManageEvidence,
    required this.uploading,
    required this.uploadProgress,
    this.uploadLabel,
    this.onRemove,
    this.onAddNote,
    this.onAddImage,
    this.onAddVideo,
    this.onRecordVideo,
  });

  final List<ServiceOrderDraftEvidence> evidences;
  final bool canManageEvidence;
  final bool uploading;
  final double uploadProgress;
  final String? uploadLabel;
  final ValueChanged<String>? onRemove;
  final VoidCallback? onAddNote;
  final VoidCallback? onAddImage;
  final VoidCallback? onAddVideo;
  final VoidCallback? onRecordVideo;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Evidencias',
      subtitle: canManageEvidence
          ? 'Se guardan en storage primero y luego se vinculan a la orden.'
          : 'Solo el técnico puede cargar evidencias desde esta pantalla.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (canManageEvidence)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: uploading ? null : onAddNote,
                  icon: const Icon(Icons.notes_outlined),
                  label: const Text('Agregar nota'),
                ),
                OutlinedButton.icon(
                  onPressed: uploading ? null : onAddImage,
                  icon: const Icon(Icons.image_outlined),
                  label: const Text('Subir imagen'),
                ),
                OutlinedButton.icon(
                  onPressed: uploading ? null : onAddVideo,
                  icon: const Icon(Icons.videocam_outlined),
                  label: const Text('Subir video'),
                ),
                if (onRecordVideo != null)
                  OutlinedButton.icon(
                    onPressed: uploading ? null : onRecordVideo,
                    icon: const Icon(Icons.fiber_manual_record_outlined),
                    label: const Text('Grabar video'),
                  ),
              ],
            ),
          if (uploading) ...[
            const SizedBox(height: 14),
            _UploadProgressCard(
              label: uploadLabel ?? 'Subiendo archivo',
              progress: uploadProgress,
            ),
          ],
          const SizedBox(height: 16),
          _EvidenceChatList(
            evidences: evidences,
            onRemove: onRemove,
            compact: false,
          ),
        ],
      ),
    );
  }
}

class _EvidenceChatList extends StatelessWidget {
  const _EvidenceChatList({
    required this.evidences,
    this.onRemove,
    required this.compact,
  });

  final List<ServiceOrderDraftEvidence> evidences;
  final ValueChanged<String>? onRemove;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (evidences.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Text('Aún no hay evidencias preparadas'),
      );
    }

    return Column(
      children: evidences
          .asMap()
          .entries
          .map(
            (entry) => Align(
              alignment: entry.key.isEven
                  ? Alignment.centerLeft
                  : Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _EvidenceBubble(
                  evidence: entry.value,
                  compact: compact,
                  onRemove: onRemove == null
                      ? null
                      : () => onRemove!(entry.value.id),
                ),
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _EvidenceBubble extends StatelessWidget {
  const _EvidenceBubble({
    required this.evidence,
    required this.compact,
    this.onRemove,
  });

  final ServiceOrderDraftEvidence evidence;
  final bool compact;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final bubbleColor = evidence.isImage
        ? const Color(0xFFE5F3ED)
        : evidence.isVideo
        ? const Color(0xFFF8EDE1)
        : const Color(0xFFE8EEF8);

    return Container(
      constraints: BoxConstraints(maxWidth: compact ? 360 : 420),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                evidence.isImage
                    ? Icons.image_outlined
                    : evidence.isVideo
                    ? Icons.videocam_outlined
                    : Icons.notes_outlined,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  evidence.type.label,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              if (onRemove != null)
                IconButton(
                  onPressed: onRemove,
                  icon: const Icon(Icons.close, size: 18),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (evidence.isImage)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: evidence.previewBytes != null
                  ? Image.memory(
                      evidence.previewBytes!,
                      height: compact ? 140 : 180,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    )
                  : Image.network(
                      evidence.previewSource,
                      height: compact ? 140 : 180,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
            )
          else if (evidence.isVideo)
            _DraftVideoPreview(evidence: evidence, compact: compact)
          else
            Text(evidence.content),
        ],
      ),
    );
  }
}

class _DraftVideoPreview extends StatefulWidget {
  const _DraftVideoPreview({required this.evidence, required this.compact});

  final ServiceOrderDraftEvidence evidence;
  final bool compact;

  @override
  State<_DraftVideoPreview> createState() => _DraftVideoPreviewState();
}

class _DraftVideoPreviewState extends State<_DraftVideoPreview> {
  VideoPlayerController? _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _controller = createVideoPreviewController(
      path: widget.evidence.previewSource,
      bytes: widget.evidence.previewBytes,
      fileName: widget.evidence.fileName,
    );
    final controller = _controller;
    if (controller == null) return;
    controller.setVolume(0);
    controller.initialize().then((_) {
      if (!mounted) return;
      setState(() {
        _ready = true;
      });
    }).catchError((_) {
      if (!mounted) return;
      setState(() {
        _ready = false;
      });
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final height = widget.compact ? 140.0 : 180.0;
    final controller = _controller;
    if (controller == null || !_ready) {
      return Container(
        height: height,
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.play_circle_outline, color: Colors.white, size: 40),
            const SizedBox(height: 8),
            Text(
              widget.evidence.fileName ?? 'Video cargado',
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: controller.value.aspectRatio == 0
            ? 16 / 9
            : controller.value.aspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            VideoPlayer(controller),
            Container(
              color: Colors.black26,
              alignment: Alignment.center,
              child: const Icon(Icons.play_circle_fill, color: Colors.white, size: 42),
            ),
          ],
        ),
      ),
    );
  }
}