import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/app_role.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/routing/app_navigator.dart';
import '../../core/routing/routes.dart';
import '../../core/utils/app_feedback.dart';
import 'application/service_order_detail_controller.dart';
import 'service_order_models.dart';

class ServiceOrderDetailScreen extends ConsumerWidget {
  const ServiceOrderDetailScreen({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = serviceOrderDetailControllerProvider(orderId);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final order = state.order;
    final currentUser = ref.watch(authStateProvider).user;
    final role = currentUser?.appRole ?? AppRole.unknown;
    final canSeeTechnicalArea = role.isTechnician || role.isAdmin;

    return Scaffold(
      appBar: AppBar(
        leading: AppNavigator.maybeBackButton(
          context,
          fallbackRoute: Routes.serviceOrders,
        ),
        title: const Text('Detalle de orden'),
        actions: [
          IconButton(
            onPressed: state.loading || state.working ? null : controller.refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: state.loading && order == null
            ? const Center(child: CircularProgressIndicator())
            : order == null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(state.error ?? 'No se pudo cargar la orden'),
                ),
              )
            : RefreshIndicator(
                onRefresh: controller.refresh,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                  children: [
                    _HeroHeader(order: order, clientName: state.client?.nombre),
                    const SizedBox(height: 16),
                    if (state.actionError != null) ...[
                      _MessageBanner(message: state.actionError!),
                      const SizedBox(height: 16),
                    ],
                    _DetailSection(
                      title: 'Estado operativo',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          DropdownButtonFormField<ServiceOrderStatus>(
                            initialValue: order.status,
                            decoration: const InputDecoration(
                              labelText: 'Estado',
                              border: OutlineInputBorder(),
                            ),
                            items: [order.status, ...order.status.allowedNextStatuses]
                                .map(
                                  (status) => DropdownMenuItem(
                                    value: status,
                                    child: Text(status.label),
                                  ),
                                )
                                .toList(growable: false),
                            onChanged: state.working
                                ? null
                                : (value) async {
                                    if (value == null || value == order.status) {
                                      return;
                                    }
                                    try {
                                      await controller.updateStatus(value);
                                      if (!context.mounted) return;
                                      await AppFeedback.showInfo(
                                        context,
                                        'Estado actualizado',
                                      );
                                    } catch (_) {
                                      if (!context.mounted) return;
                                      await AppFeedback.showError(
                                        context,
                                        ref.read(provider).actionError ??
                                            'No se pudo actualizar el estado',
                                      );
                                    }
                                  },
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _MiniPill(
                                icon: Icons.person_outline,
                                text: state.client?.nombre ?? order.clientId,
                              ),
                              _MiniPill(
                                icon: Icons.build_outlined,
                                text: order.serviceType.label,
                              ),
                              _MiniPill(
                                icon: Icons.category_outlined,
                                text: order.category.label,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (canSeeTechnicalArea) ...[
                      _DetailSection(
                        title: 'Información técnica',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _ReadOnlyField(
                              label: 'Nota técnica',
                              value: order.technicalNote,
                            ),
                            const SizedBox(height: 12),
                            _ReadOnlyField(
                              label: 'Requisitos extra',
                              value: order.extraRequirements,
                            ),
                            const SizedBox(height: 12),
                            _ReadOnlyField(
                              label: 'Técnico asignado',
                              value: order.assignedToId == null
                                  ? null
                                  : state.usersById[order.assignedToId!]
                                          ?.nombreCompleto ??
                                      order.assignedToId,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    _DetailSection(
                      title: 'Referencia',
                      child: order.referenceItems.isEmpty
                          ? const Text('Sin referencias registradas')
                          : Column(
                              children: order.referenceItems
                                  .map(
                                    (evidence) => Padding(
                                      padding: const EdgeInsets.only(bottom: 12),
                                      child: _EvidenceCard(evidence: evidence),
                                    ),
                                  )
                                  .toList(growable: false),
                            ),
                    ),
                    if (canSeeTechnicalArea) ...[
                      const SizedBox(height: 16),
                      _DetailSection(
                        title: 'Evidencia técnica',
                        trailing: MenuAnchor(
                              menuChildren: [
                                MenuItemButton(
                                  onPressed: () => _addTextEvidence(context, ref, provider),
                                  child: const Text('Agregar texto'),
                                ),
                                MenuItemButton(
                                  onPressed: () => _addImageEvidence(context, ref, provider),
                                  child: const Text('Subir imagen'),
                                ),
                                MenuItemButton(
                                  onPressed: () => _addVideoEvidence(context, ref, provider),
                                  child: const Text('Subir video'),
                                ),
                              ],
                              builder: (context, menuController, child) {
                                return OutlinedButton.icon(
                                  onPressed: state.working
                                      ? null
                                      : () {
                                          if (menuController.isOpen) {
                                            menuController.close();
                                          } else {
                                            menuController.open();
                                          }
                                        },
                                  icon: const Icon(Icons.add_photo_alternate_outlined),
                                  label: const Text('Nueva evidencia'),
                                );
                              },
                            ),
                        child: order.technicalEvidenceItems.isEmpty
                            ? const Text('Sin evidencias técnicas registradas')
                            : Column(
                                children: order.technicalEvidenceItems
                                    .map(
                                      (evidence) => Padding(
                                        padding: const EdgeInsets.only(bottom: 12),
                                        child: _EvidenceCard(evidence: evidence),
                                      ),
                                    )
                                    .toList(growable: false),
                              ),
                      ),
                      const SizedBox(height: 16),
                      _DetailSection(
                        title: 'Reporte técnico',
                        trailing: FilledButton.tonalIcon(
                          onPressed: state.working
                              ? null
                              : () => _addReport(context, ref, provider),
                          icon: const Icon(Icons.note_add_outlined),
                          label: const Text('Agregar reporte'),
                        ),
                        child: order.reports.isEmpty
                            ? const Text('No hay reportes cargados')
                            : Column(
                                children: order.reports
                                    .map(
                                      (report) => Padding(
                                        padding: const EdgeInsets.only(bottom: 12),
                                        child: _ReportCard(
                                          report: report,
                                          authorName: state.usersById[report.createdById]
                                              ?.nombreCompleto,
                                        ),
                                      ),
                                    )
                                    .toList(growable: false),
                              ),
                      ),
                    ] else ...[
                      const SizedBox(height: 16),
                      _DetailSection(
                        title: 'Evidencia técnica',
                        child: const Text(
                          'Solo técnico y administración pueden registrar evidencias técnicas y reportes.',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
      ),
      bottomNavigationBar: order == null || !order.isCloneSourceAllowed
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: FilledButton.icon(
                onPressed: () async {
                  final created = await context.push<bool>(
                    Routes.serviceOrderCreate,
                    extra: ServiceOrderCreateArgs(cloneSource: order),
                  );
                  if (created == true) {
                    if (!context.mounted) return;
                    context.pop(true);
                  }
                },
                icon: const Icon(Icons.copy_all_outlined),
                label: const Text('Crear nueva orden desde esta'),
              ),
            ),
    );
  }

  Future<void> _addTextEvidence(
    BuildContext context,
    WidgetRef ref,
    AutoDisposeStateNotifierProvider<
      ServiceOrderDetailController,
      ServiceOrderDetailState
    > provider,
  ) async {
    final value = await _promptMultilineInput(
      context,
      title: 'Nueva evidencia de texto',
      label: 'Describe la evidencia',
    );
    if ((value ?? '').trim().isEmpty) return;
    try {
      await ref.read(provider.notifier).addTextEvidence(value!.trim());
      if (!context.mounted) return;
      await AppFeedback.showInfo(context, 'Evidencia agregada');
    } catch (_) {
      if (!context.mounted) return;
      await AppFeedback.showError(
        context,
        ref.read(provider).actionError ?? 'No se pudo guardar la evidencia',
      );
    }
  }

  Future<void> _addImageEvidence(
    BuildContext context,
    WidgetRef ref,
    AutoDisposeStateNotifierProvider<
      ServiceOrderDetailController,
      ServiceOrderDetailState
    > provider,
  ) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = result?.files.single;
    if (file == null || file.bytes == null) return;
    try {
      await ref.read(provider.notifier).addImageEvidence(
            bytes: file.bytes!,
            fileName: file.name,
        path: file.path,
          );
      if (!context.mounted) return;
      await AppFeedback.showInfo(context, 'Imagen cargada como evidencia');
    } catch (_) {
      if (!context.mounted) return;
      await AppFeedback.showError(
        context,
        ref.read(provider).actionError ?? 'No se pudo subir la imagen',
      );
    }
  }

  Future<void> _addVideoEvidence(
    BuildContext context,
    WidgetRef ref,
    AutoDisposeStateNotifierProvider<
      ServiceOrderDetailController,
      ServiceOrderDetailState
    > provider,
  ) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp4', 'mov', 'webm', 'mkv'],
      withData: kIsWeb,
    );
    final file = result?.files.single;
    if (file == null) return;
    try {
      await ref.read(provider.notifier).addVideoEvidence(
            fileName: file.name,
            bytes: file.bytes,
            path: file.path,
          );
      if (!context.mounted) return;
      await AppFeedback.showInfo(context, 'Video agregado');
    } catch (_) {
      if (!context.mounted) return;
      await AppFeedback.showError(
        context,
        ref.read(provider).actionError ?? 'No se pudo guardar el video',
      );
    }
  }

  Future<void> _addReport(
    BuildContext context,
    WidgetRef ref,
    AutoDisposeStateNotifierProvider<
      ServiceOrderDetailController,
      ServiceOrderDetailState
    > provider,
  ) async {
    final value = await _promptMultilineInput(
      context,
      title: 'Nuevo reporte técnico',
      label: 'Resumen del trabajo realizado',
    );
    if ((value ?? '').trim().isEmpty) return;
    try {
      await ref.read(provider.notifier).addReport(value!.trim());
      if (!context.mounted) return;
      await AppFeedback.showInfo(context, 'Reporte guardado');
    } catch (_) {
      if (!context.mounted) return;
      await AppFeedback.showError(
        context,
        ref.read(provider).actionError ?? 'No se pudo guardar el reporte',
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

class _HeroHeader extends StatelessWidget {
  const _HeroHeader({required this.order, required this.clientName});

  final ServiceOrderModel order;
  final String? clientName;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF102542), Color(0xFF0F7B6C)],
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  clientName ?? order.clientId,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  order.status.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _HeaderTag(text: order.category.label),
              _HeaderTag(text: order.serviceType.label),
              _HeaderTag(
                text: DateFormat('dd/MM/yyyy h:mm a', 'es_DO')
                    .format(order.createdAt.toLocal()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderTag extends StatelessWidget {
  const _HeaderTag({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text, style: const TextStyle(color: Colors.white)),
    );
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
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

class _ReadOnlyField extends StatelessWidget {
  const _ReadOnlyField({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text((value ?? '').trim().isEmpty ? 'Sin información' : value!),
        ),
      ],
    );
  }
}

class _MiniPill extends StatelessWidget {
  const _MiniPill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 8),
          Text(text),
        ],
      ),
    );
  }
}

class _EvidenceCard extends StatelessWidget {
  const _EvidenceCard({required this.evidence});

  final ServiceOrderEvidenceModel evidence;

  @override
  Widget build(BuildContext context) {
    final isUrl = evidence.content.startsWith('http://') ||
        evidence.content.startsWith('https://');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                evidence.type.isText
                    ? Icons.notes_outlined
                    : evidence.type.isImage
                    ? Icons.image_outlined
                    : Icons.videocam_outlined,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(evidence.type.label)),
              Text(
                DateFormat('dd/MM h:mm a', 'es_DO').format(evidence.createdAt.toLocal()),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (evidence.type.isImage && isUrl)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(
                evidence.content,
                height: 180,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    const SizedBox(
                      height: 120,
                      child: Center(child: Text('No se pudo cargar la imagen')),
                    ),
              ),
            )
          else
            Text(evidence.content),
          if (isUrl) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final uri = Uri.tryParse(evidence.content);
                  if (uri == null) return;
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                },
                icon: const Icon(Icons.open_in_new_outlined),
                label: const Text('Abrir enlace'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.report, required this.authorName});

  final ServiceOrderReportModel report;
  final String? authorName;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(report.report),
          const SizedBox(height: 10),
          Text(
            '${authorName ?? report.createdById} · ${DateFormat('dd/MM/yyyy h:mm a', 'es_DO').format(report.createdAt.toLocal())}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _MessageBanner extends StatelessWidget {
  const _MessageBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(message),
    );
  }
}