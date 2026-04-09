import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/widgets/app_drawer.dart';
import 'application/service_order_commissions_controller.dart';
import 'commissions_models.dart';

class ServiceOrderCommissionsScreen extends ConsumerWidget {
  const ServiceOrderCommissionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);
    final currentUser = auth.user;
    final state = ref.watch(serviceOrderCommissionsControllerProvider);
    final controller = ref.read(
      serviceOrderCommissionsControllerProvider.notifier,
    );
    final theme = Theme.of(context);
    final currency = NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$ ');
    final dateFormat = DateFormat('dd/MM/yyyy', 'es_DO');

    return Scaffold(
      drawer: buildAdaptiveDrawer(context, currentUser: currentUser),
      appBar: AppBar(
        title: const Text('Comisiones'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: state.refreshing ? null : () => controller.refresh(),
            icon: state.refreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: controller.refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      theme.colorScheme.primaryContainer,
                      theme.colorScheme.surface,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Resumen de comisiones',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      state.range?.label.isNotEmpty == true
                          ? state.range!.label
                          : 'Cargando periodo...',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: ServiceOrderCommissionPeriod.values
                          .map(
                            (period) => ChoiceChip(
                              label: Text(period.label),
                              selected: state.selectedPeriod == period,
                              onSelected: (_) =>
                                  controller.changePeriod(period),
                            ),
                          )
                          .toList(growable: false),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _SummaryCard(
                    title: 'Total servicios',
                    value: '${state.summary.totalServices}',
                    subtitle: 'Órdenes finalizadas en el periodo',
                    icon: Icons.assignment_turned_in_outlined,
                  ),
                  _SummaryCard(
                    title: 'Monto total vendido',
                    value: currency.format(state.summary.totalSold),
                    subtitle: 'Suma de cotizaciones asociadas',
                    icon: Icons.payments_outlined,
                  ),
                  _SummaryCard(
                    title: 'Comisión estimada',
                    value: currency.format(
                      state.summary.visibleCommissionTotal,
                    ),
                    subtitle: 'Según tu visibilidad actual',
                    icon: Icons.account_balance_wallet_outlined,
                  ),
                  _SummaryCard(
                    title: 'Promedio por servicio',
                    value: currency.format(state.summary.averageSold),
                    subtitle: 'Promedio de venta por orden',
                    icon: Icons.analytics_outlined,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Órdenes filtradas',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    '${state.pagination.totalItems} resultados',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (state.loading && state.items.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (state.error != null && state.items.isEmpty)
                _StateMessageCard(
                  icon: Icons.error_outline_rounded,
                  title: 'No se pudieron cargar las comisiones',
                  message: state.error!,
                  actionLabel: 'Reintentar',
                  onAction: controller.refresh,
                )
              else if (state.items.isEmpty)
                const _StateMessageCard(
                  icon: Icons.inbox_outlined,
                  title: 'Sin resultados',
                  message:
                      'No hay órdenes finalizadas para esta quincena con los filtros de comisión aplicados.',
                )
              else ...[
                for (final item in state.items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _CommissionOrderCard(
                      item: item,
                      currency: currency,
                      dateFormat: dateFormat,
                    ),
                  ),
                if (state.pagination.hasMore)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: FilledButton.tonalIcon(
                      onPressed: state.loadingMore ? null : controller.loadMore,
                      icon: state.loadingMore
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.expand_more_rounded),
                      label: const Text('Cargar más'),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final cardWidth = width >= 1200
        ? (width - 72) / 4
        : width >= 800
        ? 260.0
        : double.infinity;

    return SizedBox(
      width: cardWidth,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              title,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommissionOrderCard extends StatelessWidget {
  const _CommissionOrderCard({
    required this.item,
    required this.currency,
    required this.dateFormat,
  });

  final ServiceOrderCommissionItem item;
  final NumberFormat currency;
  final DateFormat dateFormat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.clientName.isEmpty
                          ? 'Cliente sin nombre'
                          : item.clientName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.serviceType.isEmpty ? 'Servicio' : item.serviceType,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFE9F8EF),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'Finalizada',
                  style: TextStyle(
                    color: Color(0xFF197A3E),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 18,
            runSpacing: 10,
            children: [
              _MetaItem(
                label: 'Fecha',
                value: item.finalizedAt == null
                    ? 'No disponible'
                    : dateFormat.format(item.finalizedAt!.toLocal()),
              ),
              _MetaItem(
                label: 'Monto',
                value: currency.format(item.totalAmount),
              ),
              _MetaItem(
                label: 'Comisión estimada',
                value: currency.format(item.visibleCommissionAmount),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetaItem extends StatelessWidget {
  const _MetaItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _StateMessageCard extends StatelessWidget {
  const _StateMessageCard({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final Future<void> Function()? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(icon, size: 32, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: () => onAction!(),
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}
