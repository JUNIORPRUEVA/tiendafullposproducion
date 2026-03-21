import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/routing/routes.dart';
import '../../../core/widgets/app_drawer.dart';
import '../../../modules/cotizaciones/cotizacion_models.dart';
import '../../../modules/cotizaciones/data/cotizaciones_repository.dart';
import '../operations_models.dart';
import '../presentation/operations_back_button.dart';
import '../presentation/service_location_helpers.dart';
import 'technical_visit_controller.dart';
import 'widgets/file_upload_section.dart';
import 'widgets/notes_input.dart';
import 'widgets/replacement_list_widget.dart';
import 'widgets/service_order_detail_components.dart';
import 'widgets/signature_pad_widget.dart';
import 'widgets/signature_screen.dart';

enum TechnicalPhaseFormVariant { levantamiento, garantia }

final _latestQuoteProvider = FutureProvider.family<CotizacionModel?, String>((
  ref,
  phone,
) async {
  final cleanPhone = phone.trim();
  if (cleanPhone.isEmpty) return null;
  final repo = ref.read(cotizacionesRepositoryProvider);
  final quotes = await repo.list(customerPhone: cleanPhone, take: 12);
  if (quotes.isEmpty) return null;
  final sorted = [...quotes]
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return sorted.first;
});

class TechnicalPhaseFormScreen extends ConsumerStatefulWidget {
  final String serviceId;
  final TechnicalPhaseFormVariant variant;

  const TechnicalPhaseFormScreen({
    super.key,
    required this.serviceId,
    required this.variant,
  });

  @override
  ConsumerState<TechnicalPhaseFormScreen> createState() =>
      _TechnicalPhaseFormScreenState();
}

class _TechnicalPhaseFormScreenState
    extends ConsumerState<TechnicalPhaseFormScreen> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _notesCtrl = TextEditingController();

  bool _syncedNotes = false;
  bool _syncScheduled = false;

  bool get _isWarranty => widget.variant == TechnicalPhaseFormVariant.garantia;

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto({required ImageSource source}) async {
    final file = await _picker.pickImage(source: source, imageQuality: 85);
    if (file == null) return;
    await ref
        .read(technicalVisitControllerProvider(widget.serviceId).notifier)
        .uploadPhoto(file);
  }

  Future<void> _pickVideo({required ImageSource source}) async {
    final file = await _picker.pickVideo(source: source);
    if (file == null) return;
    await ref
        .read(technicalVisitControllerProvider(widget.serviceId).notifier)
        .uploadVideo(file);
  }

  Future<void> _captureSignature(TechnicalVisitController ctrl) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => SignatureScreen(
          onSave: (pngBytes) async {
            await ctrl.saveClientSignatureLocally(pngBytes: pngBytes);
          },
        ),
      ),
    );
  }

  Future<void> _save({required bool finalize}) async {
    final ctrl = ref.read(
      technicalVisitControllerProvider(widget.serviceId).notifier,
    );
    final current = ref.read(
      technicalVisitControllerProvider(widget.serviceId),
    );
    if (finalize && !current.hasClientSignature) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            _isWarranty
                ? 'Debes capturar la firma del cliente antes de finalizar la garantía.'
                : 'Debes capturar la firma del cliente antes de finalizar el levantamiento.',
          ),
        ),
      );
      return;
    }

    await ctrl.save();
    if (!mounted) return;

    final next = ref.read(technicalVisitControllerProvider(widget.serviceId));
    final message = (next.error ?? '').trim();
    final isBlockingError =
        message.isNotEmpty && !message.toLowerCase().contains('sincronizar');

    if (message.isNotEmpty) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(message)));
    } else {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            finalize
                ? (_isWarranty
                      ? 'Garantía registrada correctamente.'
                      : 'Levantamiento guardado correctamente.')
                : 'Cambios guardados correctamente.',
          ),
        ),
      );
    }

    if (finalize && !isBlockingError && mounted) {
      context.pop();
    }
  }

  String _money(double? value) {
    if (value == null || value <= 0) return '';
    return 'RD\$ ${value.toStringAsFixed(2)}';
  }

  String _fmtDate(DateTime? value) {
    if (value == null) return '—';
    final local = value.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$day/$month/$year • $hh:$mm';
  }

  Future<void> _openMaps(ServiceLocationInfo location) async {
    final uri = location.mapsUri;
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Widget _buildBanner(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _isWarranty
        ? const Color(0xFFB45309)
        : const Color(0xFF0B6BDE);
    final background = _isWarranty
        ? const Color(0xFFFFF7ED)
        : const Color(0xFFEAF3FF);
    final title = _isWarranty
        ? 'Servicio en garantía'
        : 'Levantamiento técnico';
    final message = _isWarranty
        ? 'Este servicio corresponde a una garantía. El cliente no debe pagar por el servicio, solo puede aplicarse cobro por combustible si corresponde.'
        : 'Esta pantalla es para realizar el levantamiento técnico. Registra toda la información posible (fotos, videos, notas) para una correcta evaluación del servicio.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              _isWarranty
                  ? Icons.verified_user_outlined
                  : Icons.assignment_turned_in_outlined,
              color: accent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF10233F),
                        ),
                      ),
                    ),
                    if (_isWarranty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFEDD5),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'Garantía',
                          style: TextStyle(
                            color: Color(0xFF9A3412),
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    height: 1.45,
                    color: const Color(0xFF334155),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).user;
    final state = ref.watch(technicalVisitControllerProvider(widget.serviceId));
    final ctrl = ref.read(
      technicalVisitControllerProvider(widget.serviceId).notifier,
    );
    final service = state.service;

    if (!_syncedNotes && !state.loading && !_syncScheduled) {
      _syncScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_syncedNotes) return;
        _notesCtrl.text = state.unifiedNotes;
        _syncedNotes = true;
        _syncScheduled = false;
      });
    }

    final location = buildServiceLocationInfo(
      addressOrText: service?.customerAddress ?? '',
    );
    final quoteAsync = ref.watch(
      _latestQuoteProvider(service?.customerPhone ?? ''),
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF7FBFE),
      drawer: buildAdaptiveDrawer(context, currentUser: user),
      appBar: AppBar(
        leading: const OperationsBackButton(
          fallbackRoute: Routes.operacionesTecnico,
        ),
        title: Text(_isWarranty ? 'Garantía' : 'Levantamiento'),
        actions: [
          if (state.saving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
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
              onPressed: () => _save(finalize: false),
              icon: const Icon(Icons.save_outlined),
            ),
        ],
      ),
      body: state.loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                _syncedNotes = false;
                await ctrl.load();
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                children: [
                  _buildBanner(context),
                  if ((state.error ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF1F2),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFFECDD3)),
                      ),
                      child: Text(
                        state.error!,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFFB42318),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  SectionCard(
                    icon: Icons.person_outline,
                    title: 'Información del cliente',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        InfoRow(
                          label: 'Cliente',
                          value: (service?.customerName ?? '').trim().isEmpty
                              ? 'Sin nombre'
                              : service!.customerName,
                          icon: Icons.badge_outlined,
                          emphasize: true,
                        ),
                        const SizedBox(height: 10),
                        InfoRow(
                          label: 'Teléfono',
                          value: (service?.customerPhone ?? '').trim().isEmpty
                              ? 'No registrado'
                              : service!.customerPhone,
                          icon: Icons.call_outlined,
                        ),
                        const SizedBox(height: 10),
                        InfoRow(
                          label: 'Creado por',
                          value: (service?.createdByName ?? '').trim().isEmpty
                              ? 'Sistema'
                              : service!.createdByName,
                          icon: Icons.person_add_alt_1_outlined,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SectionCard(
                    icon: Icons.assignment_outlined,
                    title: 'Información de la orden',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        InfoRow(
                          label: 'Orden',
                          value: service?.orderLabel ?? '—',
                          icon: Icons.confirmation_number_outlined,
                          emphasize: true,
                        ),
                        const SizedBox(height: 10),
                        InfoRow(
                          label: 'Título',
                          value: (service?.title ?? '').trim().isEmpty
                              ? 'Sin título'
                              : service!.title,
                          icon: Icons.title_outlined,
                          multiline: true,
                        ),
                        if ((service?.description ?? '').trim().isNotEmpty) ...[
                          const SizedBox(height: 10),
                          InfoRow(
                            label: 'Detalle',
                            value: service!.description,
                            icon: Icons.notes_outlined,
                            multiline: true,
                          ),
                        ],
                        const SizedBox(height: 10),
                        InfoRow(
                          label: 'Fase',
                          value: service == null
                              ? '—'
                              : effectiveServicePhaseLabel(service),
                          icon: Icons.flag_outlined,
                        ),
                        const SizedBox(height: 10),
                        InfoRow(
                          label: 'Estado',
                          value: (service?.status ?? '').trim().isEmpty
                              ? '—'
                              : effectiveServiceStatusLabel(service!),
                          icon: Icons.track_changes_outlined,
                        ),
                        const SizedBox(height: 10),
                        InfoRow(
                          label: 'Agendada',
                          value: _fmtDate(service?.scheduledStart),
                          icon: Icons.calendar_today_outlined,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SectionCard(
                    icon: Icons.place_outlined,
                    title: 'Ubicación',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        InfoRow(
                          label: 'Dirección',
                          value: location.label,
                          icon: Icons.location_on_outlined,
                          multiline: true,
                        ),
                        if (location.canOpenMaps) ...[
                          const SizedBox(height: 12),
                          ActionButton(
                            label: 'Abrir en Maps',
                            icon: Icons.map_outlined,
                            tonal: true,
                            onPressed: () => _openMaps(location),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SectionCard(
                    icon: Icons.request_quote_outlined,
                    title: 'Información de cotización',
                    child: quoteAsync.when(
                      loading: () => const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                      error: (error, _) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'No fue posible cargar la cotización más reciente.',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFFB42318),
                                ),
                          ),
                          if (_money(service?.quotedAmount).isNotEmpty) ...[
                            const SizedBox(height: 10),
                            InfoRow(
                              label: 'Cotizado',
                              value: _money(service?.quotedAmount),
                              icon: Icons.payments_outlined,
                            ),
                          ],
                        ],
                      ),
                      data: (quote) {
                        final canOpenQuote = (service?.customerPhone ?? '')
                            .trim()
                            .isNotEmpty;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            InfoRow(
                              label: 'Cotizado',
                              value: _money(
                                quote?.total ?? service?.quotedAmount,
                              ),
                              icon: Icons.payments_outlined,
                              emphasize: true,
                            ),
                            const SizedBox(height: 10),
                            InfoRow(
                              label: 'Fecha',
                              value: quote == null
                                  ? 'Sin cotización vinculada'
                                  : _fmtDate(quote.createdAt),
                              icon: Icons.event_outlined,
                            ),
                            if ((quote?.note ?? '').trim().isNotEmpty) ...[
                              const SizedBox(height: 10),
                              InfoRow(
                                label: 'Nota',
                                value: quote!.note,
                                icon: Icons.sticky_note_2_outlined,
                                multiline: true,
                              ),
                            ],
                            if (quote != null && quote.items.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Text(
                                'Items principales',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: const Color(0xFF10233F),
                                    ),
                              ),
                              const SizedBox(height: 8),
                              for (final item in quote.items.take(4)) ...[
                                InfoRow(
                                  label: item.qty.toStringAsFixed(
                                    item.qty.truncateToDouble() == item.qty
                                        ? 0
                                        : 1,
                                  ),
                                  value: item.nombre,
                                  icon: Icons.inventory_2_outlined,
                                ),
                                const SizedBox(height: 8),
                              ],
                            ],
                            if (canOpenQuote) ...[
                              const SizedBox(height: 8),
                              ActionButton(
                                label: 'Ver cotización',
                                icon: Icons.open_in_new_outlined,
                                tonal: true,
                                onPressed: () {
                                  final uri = Uri(
                                    path: Routes.cotizacionesHistorial,
                                    queryParameters: {
                                      'customerPhone': service!.customerPhone,
                                      'pick': '0',
                                    },
                                  );
                                  context.go(uri.toString());
                                },
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  SectionCard(
                    icon: Icons.photo_library_outlined,
                    title: 'Fotos',
                    child: FileUploadSection(
                      title: 'Fotos del servicio',
                      icon: Icons.photo_library_outlined,
                      emptyTitle: 'Sin fotos registradas',
                      emptyMessage:
                          'Captura imágenes del equipo, entorno y hallazgos para dejar evidencia clara.',
                      items: state.photos,
                      pendingUploads: state.pendingUploads,
                      isVideo: false,
                      onPickCamera: () =>
                          _pickPhoto(source: ImageSource.camera),
                      onPickGallery: () =>
                          _pickPhoto(source: ImageSource.gallery),
                      onRemove: ctrl.removePhotoAt,
                      enabled: !state.saving,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SectionCard(
                    icon: Icons.video_collection_outlined,
                    title: 'Videos',
                    child: FileUploadSection(
                      title: 'Videos del servicio',
                      icon: Icons.video_collection_outlined,
                      emptyTitle: 'Sin videos registrados',
                      emptyMessage:
                          'Añade videos cuando necesites mostrar pruebas dinámicas o funcionamiento del equipo.',
                      items: state.videos,
                      pendingUploads: state.pendingUploads,
                      isVideo: true,
                      onPickCamera: () =>
                          _pickVideo(source: ImageSource.camera),
                      onPickGallery: () =>
                          _pickVideo(source: ImageSource.gallery),
                      onRemove: ctrl.removeVideoAt,
                      enabled: !state.saving,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SectionCard(
                    icon: Icons.notes_outlined,
                    title: 'Notas',
                    child: NotesInput(
                      controller: _notesCtrl,
                      onChanged: ctrl.setNotes,
                      label: _isWarranty
                          ? 'Notas de garantía'
                          : 'Notas técnicas',
                      hintText: _isWarranty
                          ? 'Describe la falla reportada, diagnóstico, trabajo realizado y observaciones relevantes.'
                          : 'Documenta hallazgos, estado del sitio, recomendaciones y material de apoyo para evaluación.',
                      enabled: !state.saving,
                    ),
                  ),
                  if (_isWarranty) ...[
                    const SizedBox(height: 12),
                    SectionCard(
                      icon: Icons.build_circle_outlined,
                      title: 'Reemplazos realizados',
                      child: ReplacementListWidget(
                        items: state.replacements,
                        onAdd: ctrl.addReplacement,
                        onRemove: ctrl.removeReplacementAt,
                        enabled: !state.saving,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  SectionCard(
                    icon: Icons.draw_outlined,
                    title: 'Conformidad del cliente',
                    child: SignaturePadWidget(
                      signaturePreviewBytes:
                          state.clientSignature?.previewBytes,
                      signatureUrl: state.clientSignature?.fileUrl,
                      signedAt: state.clientSignature?.signedAt,
                      syncStatus: state.clientSignature?.syncStatus,
                      syncError: state.clientSignature?.syncError,
                      required: true,
                      enabled: !state.saving,
                      onCapture: () => _captureSignature(ctrl),
                      onClear: ctrl.clearClientSignature,
                    ),
                  ),
                ],
              ),
            ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: state.saving ? null : () => _save(finalize: false),
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Guardar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: state.saving ? null : () => _save(finalize: true),
                  icon: const Icon(Icons.task_alt_outlined),
                  label: Text(
                    _isWarranty
                        ? 'Finalizar garantía'
                        : 'Finalizar levantamiento',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
