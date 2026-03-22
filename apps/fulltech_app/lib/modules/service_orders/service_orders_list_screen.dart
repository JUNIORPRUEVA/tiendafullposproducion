import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/routing/routes.dart';
import '../../core/utils/app_feedback.dart';
import 'application/service_orders_list_controller.dart';
import 'service_order_models.dart';

class ServiceOrdersListScreen extends ConsumerWidget {
  const ServiceOrdersListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(serviceOrdersListControllerProvider);
    final controller = ref.read(serviceOrdersListControllerProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Órdenes de servicio'),
        actions: [
          IconButton(
            onPressed: state.refreshing ? null : controller.refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await context.push<bool>(Routes.serviceOrderCreate);
          if (created == true) {
            await controller.refresh();
            if (!context.mounted) return;
            await AppFeedback.showInfo(context, 'Lista actualizada con la nueva orden');
          }
        },
        icon: const Icon(Icons.add_circle_outline),
        label: const Text('Nueva orden'),
      ),
      body: RefreshIndicator(
        onRefresh: controller.refresh,
        child: state.loading
            ? const Center(child: CircularProgressIndicator())
            : state.error != null && state.items.isEmpty
            ? ListView(
                children: [
                  const SizedBox(height: 120),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(state.error!, textAlign: TextAlign.center),
                    ),
                  ),
                ],
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF11304A), Color(0xFF27667B)],
                      ),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Control operativo',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${state.items.length} órdenes cargadas',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Icon(
                            Icons.assignment_turned_in_outlined,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (state.items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 64),
                      child: Center(
                        child: Text('No hay órdenes registradas todavía'),
                      ),
                    ),
                  ...state.items.map((order) {
                    final client = state.clientsById[order.clientId];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(24),
                        onTap: () async {
                          final updated = await context.push<bool>(
                            Routes.serviceOrderById(order.id),
                          );
                          if (updated == true) {
                            await controller.refresh();
                          }
                        },
                        child: Ink(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: order.status.color.withValues(alpha: 0.18),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        client?.nombre ?? 'Cliente ${order.clientId}',
                                        style: theme.textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    _StatusChip(status: order.status),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    _MetaPill(icon: Icons.category_outlined, text: order.category.label),
                                    _MetaPill(icon: Icons.build_circle_outlined, text: order.serviceType.label),
                                    _MetaPill(
                                      icon: Icons.schedule_rounded,
                                      text: DateFormat('dd/MM/yyyy h:mm a', 'es_DO')
                                          .format(order.createdAt.toLocal()),
                                    ),
                                  ],
                                ),
                                if ((order.technicalNote ?? '').trim().isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  Text(
                                    order.technicalNote!,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final ServiceOrderStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.label,
        style: TextStyle(color: status.color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.icon, required this.text});

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