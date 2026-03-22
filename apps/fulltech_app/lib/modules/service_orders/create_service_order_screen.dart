import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/app_navigator.dart';
import '../../core/utils/app_feedback.dart';
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

    return Scaffold(
      appBar: AppBar(
        leading: AppNavigator.maybeBackButton(
          context,
          fallbackRoute: '/service-orders',
        ),
        title: Text(state.isCloneMode ? 'Clonar orden' : 'Nueva orden'),
      ),
      body: SafeArea(
        child: state.loading && !state.initialized
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                children: [
                  if (state.isCloneMode) ...[
                    _CloneBanner(source: state.cloneSource!),
                    const SizedBox(height: 16),
                  ],
                  if (state.error != null) ...[
                    _ErrorCard(message: state.error!),
                    const SizedBox(height: 16),
                  ],
                  if (state.actionError != null) ...[
                    _InfoCard(
                      message: state.actionError!,
                      color: Theme.of(context).colorScheme.errorContainer,
                    ),
                    const SizedBox(height: 16),
                  ],
                  _SectionCard(
                    title: 'Cliente y cotización',
                    subtitle: 'La orden siempre se crea ligada a un cliente y su cotización.',
                    child: Column(
                      children: [
                        DropdownButtonFormField<String>(
                          value: state.selectedClient?.id,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Cliente',
                            border: OutlineInputBorder(),
                          ),
                          items: state.clients
                              .map(
                                (client) => DropdownMenuItem<String>(
                                  value: client.id,
                                  child: Text(
                                    client.nombre,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: state.isCloneMode
                              ? null
                              : (value) {
                                  if (value == null) return;
                                  final selected = state.clients.firstWhere(
                                    (item) => item.id == value,
                                  );
                                  controller.selectClient(selected);
                                },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: state.selectedQuotation?.id,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Cotización',
                            border: OutlineInputBorder(),
                          ),
                          items: state.quotations
                              .map(
                                (quotation) => DropdownMenuItem<String>(
                                  value: quotation.id,
                                  child: Text(
                                    '${quotation.id.substring(0, quotation.id.length > 8 ? 8 : quotation.id.length)} · ${quotation.customerName}',
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
                                      .firstWhere(
                                        (item) => item != null,
                                        orElse: () => null,
                                      );
                                  controller.selectQuotation(selected);
                                },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SectionCard(
                    title: 'Configuración de servicio',
                    subtitle: 'Define categoría, tipo y responsable técnico.',
                    child: Column(
                      children: [
                        DropdownButtonFormField<ServiceOrderCategory>(
                          value: state.category,
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
                          value: state.serviceType,
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
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: state.selectedTechnician?.id,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Técnico asignado',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            const DropdownMenuItem<String>(
                              value: '',
                              child: Text('Sin asignar'),
                            ),
                            ...state.technicians.map(
                              (technician) => DropdownMenuItem<String>(
                                value: technician.id,
                                child: Text(
                                  technician.nombreCompleto,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            if ((value ?? '').isEmpty) {
                              controller.selectTechnician(null);
                              return;
                            }
                            final selected = state.technicians.firstWhere(
                              (item) => item.id == value,
                            );
                            controller.selectTechnician(selected);
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SectionCard(
                    title: 'Notas para operación',
                    subtitle: 'La información aquí alimenta el detalle operativo y técnico.',
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
              ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: FilledButton.icon(
          onPressed: state.submitting
              ? null
              : () async {
                  try {
                    await controller.submit(
                      technicalNote: _technicalNoteController.text,
                      extraRequirements: _extraRequirementsController.text,
                    );
                    if (!mounted) return;
                    await AppFeedback.showInfo(
                      context,
                      state.isCloneMode
                          ? 'Orden clonada correctamente'
                          : 'Orden creada correctamente',
                    );
                    if (!mounted) return;
                    context.pop(true);
                  } catch (_) {
                    if (!mounted) return;
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
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

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
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
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