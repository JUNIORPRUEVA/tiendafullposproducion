import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/auth/app_role.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/routing/app_navigator.dart';
import '../../core/routing/routes.dart';
import '../../core/utils/app_feedback.dart';
import '../../core/utils/video_preview_controller.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/app_navigation.dart';
import '../clientes/cliente_form_screen.dart';
import '../clientes/cliente_model.dart';
import '../cotizaciones/cotizacion_models.dart';
import '../cotizaciones/cotizaciones_screen.dart';
import 'application/create_service_order_controller.dart';
import 'service_order_models.dart';
import 'widgets/client_location_card.dart';
import 'widgets/evidence_item_widget.dart';

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
  bool _inlineFlowBusy = false;

  @override
  void initState() {
    super.initState();
    final seedOrder = widget.args?.editSource ?? widget.args?.cloneSource;
    _technicalNoteController = TextEditingController(
      text: seedOrder?.technicalNote ?? '',
    );
    _extraRequirementsController = TextEditingController(
      text: seedOrder?.extraRequirements ?? '',
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
    final isCreatorEditingOrder =
      widget.args?.isEditMode == true &&
      widget.args?.editSource?.createdById == user?.id;
    final canManageOperationalFields =
      user?.appRole.isTechnician == true ||
      user?.appRole.isAdmin == true ||
      isCreatorEditingOrder;
    final canAssignTechnician =
      user?.appRole.isAdmin == true || isCreatorEditingOrder;
    final canCreateClients =
        user?.appRole == AppRole.admin ||
        user?.appRole == AppRole.asistente ||
        user?.appRole == AppRole.vendedor ||
        user?.appRole == AppRole.tecnico;
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= kDesktopShellBreakpoint;
    final shellFallback = widget.args?.isEditMode == true
        ? Routes.serviceOrderById(widget.args!.editSource!.id)
        : widget.args?.isCloneMode == true
        ? Routes.serviceOrderById(widget.args!.cloneSource!.id)
        : Routes.serviceOrders;
    final backButton = AppNavigator.maybeBackButton(
      context,
      fallbackRoute: shellFallback,
    );

    return Scaffold(
      drawer: isDesktop
          ? null
          : buildAdaptiveDrawer(context, currentUser: user),
      backgroundColor: const Color(0xFFF4F7FB),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'service-order-reference-fab',
        onPressed: state.submitting || state.uploadingEvidence
            ? null
            : () => _showReferenceActions(context, controller),
        elevation: 8,
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        icon: const Icon(Icons.add_photo_alternate_rounded),
        label: const Text('Referencia'),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: state.loading && !state.initialized
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                final desktop = constraints.maxWidth >= kDesktopShellBreakpoint;
                final form = _buildFormColumn(
                  context,
                  desktop: desktop,
                  state: state,
                  controller: controller,
                  canManageOperationalFields: canManageOperationalFields,
                  canAssignTechnician: canAssignTechnician,
                  canCreateClients: canCreateClients,
                );
                final horizontalPadding = desktop ? 20.0 : 16.0;
                final floatingTop = MediaQuery.paddingOf(context).top + 10;

                return Stack(
                  children: [
                    Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: ListView(
                          padding: EdgeInsets.fromLTRB(
                            horizontalPadding,
                            10,
                            horizontalPadding,
                            120,
                          ),
                          children: [form],
                        ),
                      ),
                    ),
                    if (backButton != null)
                      Positioned(
                        top: floatingTop,
                        left: horizontalPadding,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: 0.34),
                                blurRadius: 18,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Theme(
                            data: Theme.of(context).copyWith(
                              iconButtonTheme: const IconButtonThemeData(
                                style: ButtonStyle(
                                  foregroundColor:
                                      WidgetStatePropertyAll<Color>(
                                        Colors.white,
                                      ),
                                ),
                              ),
                            ),
                            child: backButton,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.18),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
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
                            (state.isEditMode
                                ? 'Orden actualizada correctamente'
                                : state.isCloneMode
                                ? 'Orden clonada correctamente'
                                : 'Orden creada correctamente'),
                      );
                      if (!context.mounted) return;
                      if (state.isEditMode) {
                        context.pop(true);
                      } else {
                        context.go(Routes.serviceOrderById(result.order.id));
                      }
                    } catch (_) {
                      if (!context.mounted) return;
                      final message =
                          ref.read(provider).actionError ??
                          'No se pudo guardar la orden';
                      await AppFeedback.showError(context, message);
                    }
                  },
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
            ),
            icon: state.submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(
              state.isEditMode
                  ? 'Guardar cambios'
                  : state.isCloneMode
                  ? 'Crear nueva orden'
                  : 'Guardar orden',
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFormColumn(
    BuildContext context, {
    required bool desktop,
    required CreateServiceOrderState state,
    required CreateServiceOrderController controller,
    required bool canManageOperationalFields,
    required bool canAssignTechnician,
    required bool canCreateClients,
  }) {
    final inputDecoration = _inputDecoration(context);
    final money = NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$');
    final existingReferences = (state.editSource?.referenceItems ?? const [])
        .map(
          (reference) => ServiceOrderDraftReference(
            id: reference.id,
            type: reference.type,
            content: reference.content,
            createdAt: reference.createdAt,
            uploadedUrl: reference.type.isText ? null : reference.content,
            previewBytes: reference.previewBytes,
            localPath: reference.localPath,
            fileName: reference.fileName,
          ),
        )
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (state.isCloneMode) ...[
          const SizedBox(height: 4),
          _CloneBanner(source: state.cloneSource!),
        ],
        if (state.error != null) ...[
          const SizedBox(height: 12),
          _ErrorCard(message: state.error!),
        ],
        if (state.actionError != null) ...[
          const SizedBox(height: 12),
          _InfoCard(
            message: state.actionError!,
            color: Theme.of(context).colorScheme.errorContainer,
          ),
        ],
        if (state.uploadingEvidence) ...[
          const SizedBox(height: 12),
          _UploadProgressCard(
            label: state.uploadLabel ?? 'Subiendo archivo',
            progress: state.uploadProgress,
          ),
        ],
        if (_inlineFlowBusy) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(minHeight: 3),
        ],
        const SizedBox(height: 12),
        SectionCard(
          title: 'Cliente',
          child: Column(
            children: [
              InputSelector(
                label: 'Cliente',
                value: state.selectedClient?.nombre ?? 'Buscar cliente',
                hint: state.selectedClient?.telefono,
                enabled: !state.isCloneMode && !_inlineFlowBusy,
                icon: Icons.search_rounded,
                onTap: state.isCloneMode
                    ? null
                    : () => _pickClient(context, state, controller),
              ),
              if (!state.isCloneMode && canCreateClients) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _InlineCreateAction(
                    icon: Icons.person_add_alt_1_rounded,
                    label: 'Nuevo cliente',
                    onTap: _inlineFlowBusy
                        ? null
                        : () => _createClientInline(context, controller),
                  ),
                ),
              ],
              if (state.selectedClient != null) ...[
                const SizedBox(height: 12),
                ClientLocationCard(
                  client: state.selectedClient,
                  title: 'Ubicación',
                  compact: true,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: 'Cotización',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (state.loading)
                const LinearProgressIndicator(minHeight: 3)
              else if ((state.quotationMessage ?? '').trim().isNotEmpty) ...[
                _InlineStatus(message: state.quotationMessage!),
                const SizedBox(height: 12),
              ],
              if (state.selectedClient == null)
                const _EmptyInlineState(
                  icon: Icons.person_search_outlined,
                  label: 'Selecciona un cliente para ver sus cotizaciones',
                )
              else if (state.quotations.isEmpty) ...[
                const _EmptyInlineState(
                  icon: Icons.request_quote_outlined,
                  label: 'Este cliente no tiene cotizaciones',
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _InlineCreateAction(
                    icon: Icons.add_circle_outline_rounded,
                    label: 'Crear cotización',
                    onTap: _inlineFlowBusy || state.loading
                        ? null
                        : () => _createQuotationInline(
                            context,
                            state,
                            controller,
                          ),
                  ),
                ),
              ] else ...[
                InputSelector(
                  label: 'Cotización',
                  value: state.selectedQuotation == null
                      ? 'Seleccionar cotización'
                      : 'Cotización ${state.selectedQuotation!.id.substring(0, state.selectedQuotation!.id.length >= 6 ? 6 : state.selectedQuotation!.id.length).toUpperCase()}',
                  hint: state.selectedQuotation == null
                      ? '${state.quotations.length} disponibles'
                      : '${state.selectedQuotation!.items.length} items · ${money.format(state.selectedQuotation!.total)}',
                  enabled: !state.isCloneMode && !_inlineFlowBusy,
                  icon: Icons.request_quote_outlined,
                  onTap: state.isCloneMode
                      ? null
                      : () => _pickQuotation(context, state, controller),
                ),
                const SizedBox(height: 12),
                if (state.selectedQuotation != null)
                  _QuotationSummaryCard(quotation: state.selectedQuotation!)
                else
                  const _EmptyInlineState(
                    icon: Icons.request_quote_outlined,
                    label: 'Sin cotización seleccionada',
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: 'Configuración',
          child: Column(
            children: [
              DropdownButtonFormField<ServiceOrderCategory>(
                initialValue: state.category,
                decoration: inputDecoration.copyWith(labelText: 'Categoría'),
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
                decoration: inputDecoration.copyWith(
                  labelText: 'Tipo de servicio',
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
              if (canAssignTechnician) ...[
                const SizedBox(height: 12),
                InputSelector(
                  label: 'Técnico',
                  value:
                      state.selectedTechnician?.nombreCompleto ??
                      'Seleccionar técnico',
                  hint: state.selectedTechnician?.telefono,
                  icon: Icons.engineering_outlined,
                  onTap: () => _pickTechnician(context, state, controller),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: 'Referencia',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (existingReferences.isNotEmpty) ...[
                Text(
                  'Referencias actuales',
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                ReferenceGallery(references: existingReferences),
              ],
              if (existingReferences.isNotEmpty && state.references.isNotEmpty)
                const SizedBox(height: 14),
              if (state.references.isNotEmpty) ...[
                if (existingReferences.isNotEmpty)
                  Text(
                    'Nuevas referencias',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                if (existingReferences.isNotEmpty) const SizedBox(height: 10),
                ReferenceGallery(
                  references: state.references,
                  onRemove: controller.removeReference,
                ),
              ],
              if (existingReferences.isEmpty && state.references.isEmpty)
                const _EmptyInlineState(
                  icon: Icons.add_photo_alternate_outlined,
                  label: 'Sin referencias',
                ),
            ],
          ),
        ),
        if (canManageOperationalFields) ...[
          const SizedBox(height: 14),
          SectionCard(
            title: 'Notas',
            child: Column(
              children: [
                TextField(
                  controller: _technicalNoteController,
                  maxLines: 4,
                  decoration: inputDecoration.copyWith(
                    labelText: 'Nota técnica',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _extraRequirementsController,
                  maxLines: 3,
                  decoration: inputDecoration.copyWith(
                    labelText: 'Requisitos extra',
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
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

  Future<void> _pickQuotation(
    BuildContext context,
    CreateServiceOrderState state,
    CreateServiceOrderController controller,
  ) async {
    final selected = await _showEntityPicker<CotizacionModel>(
      context,
      title: 'Seleccionar cotización',
      items: state.quotations,
      itemTitle: (quotation) =>
          'Cotización ${quotation.id.substring(0, quotation.id.length >= 6 ? 6 : quotation.id.length).toUpperCase()}',
      itemSubtitle: (quotation) =>
          '${quotation.items.length} items · ${NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$').format(quotation.total)}',
    );
    if (!mounted) return;
    controller.selectQuotation(selected);
  }

  Future<void> _createClientInline(
    BuildContext context,
    CreateServiceOrderController controller,
  ) async {
    final newClient = await Navigator.of(context).push<ClienteModel>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const ClienteFormScreen(returnSavedClient: true),
      ),
    );
    if (newClient == null || !mounted) return;
    await _runInlineFlow(() => controller.applyCreatedClient(newClient));
  }

  Future<void> _createQuotationInline(
    BuildContext context,
    CreateServiceOrderState state,
    CreateServiceOrderController controller,
  ) async {
    final client = state.selectedClient;
    if (client == null) return;

    final quotation = await Navigator.of(context).push<CotizacionModel>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CotizacionesScreen(
          initialClient: client,
          returnSavedQuotation: true,
        ),
      ),
    );
    if (quotation == null || !mounted) return;
    await _runInlineFlow(() async {
      controller.applyCreatedQuotation(quotation);
    });
  }

  Future<void> _runInlineFlow(Future<void> Function() action) async {
    if (_inlineFlowBusy) return;
    setState(() => _inlineFlowBusy = true);
    try {
      await action();
    } finally {
      if (mounted) {
        setState(() => _inlineFlowBusy = false);
      }
    }
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
    final isDesktop =
        MediaQuery.sizeOf(context).width >= kDesktopShellBreakpoint;

    Future<T?> showPicker(Widget Function(StateSetter setState) builder) {
      if (isDesktop) {
        return showDialog<T?>(
          context: context,
          builder: (dialogContext) => StatefulBuilder(
            builder: (context, setState) => Dialog(
              elevation: 0,
              insetPadding: const EdgeInsets.all(24),
              backgroundColor: Colors.transparent,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 540,
                  maxHeight: 640,
                ),
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
      final theme = Theme.of(context);
      final colorScheme = theme.colorScheme;
      final query = queryController.text.trim().toLowerCase();
      final filtered = items
          .where((item) {
            final text = itemTitle(item).toLowerCase();
            final subtitle = (itemSubtitle?.call(item) ?? '').toLowerCase();
            return query.isEmpty ||
                text.contains(query) ||
                subtitle.contains(query);
          })
          .toList(growable: false);

      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(isDesktop ? 24 : 20),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.10),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: colorScheme.surfaceContainerHighest,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: queryController,
                onChanged: (_) => setState(() {}),
                decoration: _inputDecoration(context).copyWith(
                  hintText: 'Buscar',
                  prefixIcon: const Icon(Icons.search_rounded),
                ),
              ),
              const SizedBox(height: 14),
              if (allowEmpty) ...[
                _PickerListTile(
                  icon: Icons.remove_circle_outline,
                  title: emptyLabel,
                  onTap: () => Navigator.of(context).pop(null),
                ),
                const SizedBox(height: 8),
              ],
              Expanded(
                child: filtered.isEmpty
                    ? const _EmptyInlineState(
                        icon: Icons.search_off_rounded,
                        label: 'No hay resultados',
                      )
                    : ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final item = filtered[index];
                          return _PickerListTile(
                            title: itemTitle(item),
                            subtitle: itemSubtitle?.call(item),
                            onTap: () => Navigator.of(context).pop(item),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      );
    });
  }

  InputDecoration _inputDecoration(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: colorScheme.outlineVariant),
    );

    return InputDecoration(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(color: colorScheme.primary, width: 1.4),
      ),
      disabledBorder: border,
      labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
    );
  }

  Future<void> _showReferenceActions(
    BuildContext context,
    CreateServiceOrderController controller,
  ) async {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 28,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Agregar referencia',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      icon: const Icon(Icons.close_rounded),
                      style: IconButton.styleFrom(
                        backgroundColor: colorScheme.surfaceContainerHighest,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _ReferenceSheetOption(
                  icon: Icons.notes_rounded,
                  title: 'Agregar texto',
                  onTap: () {
                    Navigator.of(dialogContext).pop();
                    _addNoteReference(context, controller);
                  },
                ),
                const SizedBox(height: 10),
                _ReferenceSheetOption(
                  icon: Icons.image_outlined,
                  title: 'Subir imagen',
                  onTap: () {
                    Navigator.of(dialogContext).pop();
                    _addImageReference(context, controller);
                  },
                ),
                const SizedBox(height: 10),
                _ReferenceSheetOption(
                  icon: Icons.videocam_outlined,
                  title: 'Subir video',
                  onTap: () {
                    Navigator.of(dialogContext).pop();
                    _addVideoReference(context, controller);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _addNoteReference(
    BuildContext context,
    CreateServiceOrderController controller,
  ) async {
    final value = await _promptMultilineInput(
      context,
      title: 'Agregar referencia',
      label: 'Escribe la referencia en texto',
    );
    if ((value ?? '').trim().isEmpty) return;
    controller.addTextReference(value!.trim());
  }

  Future<void> _addVideoReference(
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
      await controller.addVideoReference(
        fileName: file.name,
        bytes: file.bytes,
        path: file.path,
        sizeBytes: file.size,
      );
    } catch (_) {
      if (!context.mounted) return;
      await AppFeedback.showError(
        context,
        ref
                .read(createServiceOrderControllerProvider(widget.args))
                .actionError ??
            'No se pudo subir el video',
      );
    }
  }

  Future<void> _addImageReference(
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
      await controller.addImageReference(
        bytes: bytes,
        path: file.path,
        fileName: file.name,
        sizeBytes: file.size,
      );
    } catch (_) {
      if (!context.mounted) return;
      await AppFeedback.showError(
        context,
        ref
                .read(createServiceOrderControllerProvider(widget.args))
                .actionError ??
            'No se pudo subir la imagen',
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
              onPressed: () =>
                  Navigator.pop(dialogContext, textController.text),
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );
  }
}

class _PickerListTile extends StatelessWidget {
  const _PickerListTile({
    required this.title,
    required this.onTap,
    this.subtitle,
    this.icon,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colorScheme.outlineVariant),
          color: Colors.white,
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon ?? Icons.person_outline_rounded,
                color: colorScheme.primary,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if ((subtitle ?? '').trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.65),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 12),
                  Flexible(child: trailing!),
                ],
              ],
            ),
            const SizedBox(height: 14),
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F1FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFC9DAFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Clonando orden finalizada',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            '${source.category.label} · ${source.serviceType.label}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
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
      child: Text(message, style: Theme.of(context).textTheme.bodyMedium),
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF7F4),
        borderRadius: BorderRadius.circular(16),
      ),
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
    );
  }
}

class InputSelector extends StatelessWidget {
  const InputSelector({
    super.key,
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
    final colorScheme = Theme.of(context).colorScheme;
    final selected =
        value.trim().isNotEmpty &&
        value.trim().toLowerCase() != 'buscar cliente' &&
        value.trim().toLowerCase() != 'seleccionar técnico';

    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFF7FAFF) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? colorScheme.primary.withValues(alpha: 0.28)
                : colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: colorScheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if ((hint ?? '').trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        hint!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: colorScheme.onSurfaceVariant,
            ),
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD7E4F4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Resumen',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _SummaryChip(
                label: 'Total',
                value: money.format(quotation.total),
              ),
              _SummaryChip(label: 'Items', value: '${quotation.items.length}'),
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
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
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

class ReferenceGallery extends StatelessWidget {
  const ReferenceGallery({super.key, required this.references, this.onRemove});

  final List<ServiceOrderDraftReference> references;
  final ValueChanged<String>? onRemove;

  @override
  Widget build(BuildContext context) {
    final textReferences = references
        .where((item) => item.isText)
        .toList(growable: false);
    final mediaReferences = references
        .where((item) => !item.isText)
        .toList(growable: false);

    if (references.isEmpty) {
      return const _EmptyInlineState(
        icon: Icons.add_photo_alternate_outlined,
        label: 'Sin referencias',
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: Column(
        key: ValueKey(references.length),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (textReferences.isNotEmpty)
            ...textReferences.map(
              (reference) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _TextReferenceCard(
                  reference: reference,
                  onRemove: onRemove == null
                      ? null
                      : () => onRemove!(reference.id),
                ),
              ),
            ),
          if (mediaReferences.isNotEmpty)
            SizedBox(
              height: 148,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: mediaReferences
                      .map(
                        (reference) => Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: MediaPreviewCard(
                            reference: reference,
                            width: 132,
                            onRemove: onRemove == null
                                ? null
                                : () => onRemove!(reference.id),
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class MediaPreviewCard extends StatelessWidget {
  const MediaPreviewCard({
    super.key,
    required this.reference,
    this.width = 132,
    this.onRemove,
  });

  final ServiceOrderDraftReference reference;
  final double width;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final source = reference.previewSource;

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.72),
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () => _showMediaViewer(context, reference),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: reference.isImage
                      ? _ImageThumbnail(reference: reference)
                      : _VideoThumbnail(reference: reference),
                ),
              ),
            ),
            Positioned(
              top: 6,
              left: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  reference.isImage ? 'Imagen' : 'Video',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            if (reference.isVideo)
              Positioned(
                bottom: 8,
                left: 8,
                child: _VideoDurationBadge(source: source),
              ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                onPressed: onRemove,
                icon: const Icon(Icons.close_rounded, size: 16),
                visualDensity: VisualDensity.compact,
                tooltip: 'Eliminar',
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.92),
                  foregroundColor: colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showMediaViewer(
    BuildContext context,
    ServiceOrderDraftReference reference,
  ) {
    double dragOffset = 0;

    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cerrar vista',
      barrierColor: Colors.black.withValues(alpha: 0.92),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return StatefulBuilder(
          builder: (context, setState) {
            return GestureDetector(
              onVerticalDragUpdate: (details) {
                setState(() {
                  dragOffset += details.delta.dy;
                });
              },
              onVerticalDragEnd: (details) {
                if (dragOffset.abs() > 80) {
                  Navigator.of(dialogContext).pop();
                  return;
                }
                setState(() {
                  dragOffset = 0;
                });
              },
              child: Material(
                color: Colors.transparent,
                child: Stack(
                  children: [
                    Center(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                        transform: Matrix4.translationValues(0, dragOffset, 0),
                        child: SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: reference.isImage
                                ? InteractiveViewer(
                                    child: reference.previewBytes != null
                                        ? Image.memory(
                                            reference.previewBytes!,
                                            fit: BoxFit.contain,
                                          )
                                        : Image.network(
                                            reference.previewSource,
                                            fit: BoxFit.contain,
                                          ),
                                  )
                                : Center(
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 720,
                                      ),
                                      child: AspectRatio(
                                        aspectRatio: 16 / 9,
                                        child: EvidenceItemWidget(
                                          type: reference.type,
                                          url: reference.content,
                                          text: null,
                                          createdAt: reference.createdAt,
                                          previewBytes: reference.previewBytes,
                                          localPath: reference.localPath,
                                          fileName: reference.fileName,
                                          compact: false,
                                          showHeader: false,
                                          showSurface: false,
                                        ),
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 18,
                      right: 18,
                      child: IconButton.filled(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(animation),
            child: child,
          ),
        );
      },
    );
  }
}

class _TextReferenceCard extends StatelessWidget {
  const _TextReferenceCard({required this.reference, this.onRemove});

  final ServiceOrderDraftReference reference;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.notes_rounded,
              color: colorScheme.primary,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Texto',
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  reference.content,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          if (onRemove != null)
            IconButton(
              onPressed: onRemove,
              icon: const Icon(Icons.close_rounded, size: 18),
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }
}

class _ImageThumbnail extends StatelessWidget {
  const _ImageThumbnail({required this.reference});

  final ServiceOrderDraftReference reference;

  @override
  Widget build(BuildContext context) {
    if (reference.previewBytes != null) {
      return Image.memory(
        reference.previewBytes!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
    }

    return Image.network(
      reference.previewSource,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return const Center(child: CircularProgressIndicator(strokeWidth: 2));
      },
      errorBuilder: (context, error, stackTrace) {
        return const _EmptyInlineState(
          icon: Icons.broken_image_outlined,
          label: 'Sin imagen',
        );
      },
    );
  }
}

class _VideoThumbnail extends StatelessWidget {
  const _VideoThumbnail({required this.reference});

  final ServiceOrderDraftReference reference;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFEEF2F8), Color(0xFFDCE3EF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const Center(
            child: CircleAvatar(
              radius: 24,
              backgroundColor: Color(0xFFD8DDFC),
              child: Icon(Icons.play_arrow_rounded, size: 28),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withValues(alpha: 0.02),
                    Colors.black.withValues(alpha: 0.18),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoDurationBadge extends StatefulWidget {
  const _VideoDurationBadge({required this.source});

  final String source;

  @override
  State<_VideoDurationBadge> createState() => _VideoDurationBadgeState();
}

class _VideoDurationBadgeState extends State<_VideoDurationBadge> {
  String? _durationLabel;

  @override
  void initState() {
    super.initState();
    _resolveDuration();
  }

  Future<void> _resolveDuration() async {
    final controller = createVideoPreviewController(
      path: widget.source,
      fileName: widget.source,
    );
    if (controller == null) return;
    try {
      await controller.initialize();
      if (!mounted) return;
      final duration = controller.value.duration;
      final minutes = duration.inMinutes
          .remainder(60)
          .toString()
          .padLeft(2, '0');
      final seconds = duration.inSeconds
          .remainder(60)
          .toString()
          .padLeft(2, '0');
      setState(() {
        _durationLabel = '$minutes:$seconds';
      });
    } catch (_) {
      // Keep placeholder hidden when duration cannot be resolved.
    } finally {
      await controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    if ((_durationLabel ?? '').isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _durationLabel!,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ReferenceSheetOption extends StatelessWidget {
  const _ReferenceSheetOption({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: colorScheme.primary.withValues(alpha: 0.06),
          border: Border.all(
            color: colorScheme.primary.withValues(alpha: 0.14),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: colorScheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineCreateAction extends StatelessWidget {
  const _InlineCreateAction({
    required this.icon,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: colorScheme.primary,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        backgroundColor: colorScheme.primary.withValues(alpha: 0.08),
      ),
    );
  }
}

class _InlineStatus extends StatelessWidget {
  const _InlineStatus({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _EmptyInlineState extends StatelessWidget {
  const _EmptyInlineState({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
