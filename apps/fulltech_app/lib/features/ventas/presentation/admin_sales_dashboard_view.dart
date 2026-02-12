import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/sale_model.dart';
import '../application/sales_controller.dart';

class AdminSalesDashboardView extends ConsumerWidget {
  const AdminSalesDashboardView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(adminSalesProvider);
    final ctrl = ref.read(adminSalesProvider.notifier);

    return RefreshIndicator(
      onRefresh: ctrl.refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('KPIs', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _KpiCard(
                label: 'Ventas',
                value: '${state.kpis['totalSalesCount'] ?? 0}',
              ),
              _KpiCard(
                label: 'Ingresos',
                value: state.kpis['totalRevenue'] ?? '0',
              ),
              _KpiCard(label: 'Costos', value: state.kpis['totalCost'] ?? '0'),
              _KpiCard(
                label: 'Utilidad',
                value: state.kpis['totalProfit'] ?? '0',
              ),
              _KpiCard(
                label: 'Comisiones',
                value: state.kpis['totalCommission'] ?? '0',
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Top vendedores',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          ...(state.kpis['topSellers'] as List<dynamic>? ?? []).map(
            (s) => ListTile(
              leading: const Icon(Icons.workspace_premium_outlined),
              title: Text(s['sellerName'] ?? 'N/D'),
              subtitle: Text(
                'Utilidad: ${s['profit']} · Comisión: ${s['commission']}',
              ),
              trailing: Text(s['revenue'] ?? ''),
            ),
          ),
          const SizedBox(height: 12),
          Text('Top productos', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...(state.kpis['topProducts'] as List<dynamic>? ?? []).map(
            (p) => ListTile(
              leading: const Icon(Icons.local_offer_outlined),
              title: Text(p['productName'] ?? 'N/D'),
              subtitle: Text('Utilidad: ${p['profit']}'),
              trailing: Text('Ventas: ${p['revenue']}'),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Ventas recientes',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (state.loading) const Center(child: CircularProgressIndicator()),
          if (state.error != null)
            Text(
              state.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ...state.items.map((s) => _SaleRow(sale: s)),
        ],
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  const _KpiCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 170,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 6),
              Text(
                value,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SaleRow extends StatelessWidget {
  final SaleModel sale;
  const _SaleRow({required this.sale});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.receipt_long_outlined),
        title: Text(sale.clientName ?? 'Sin cliente'),
        subtitle: Text('${sale.soldAt} · ${sale.status}'),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              sale.subtotal.toStringAsFixed(2),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text('Utilidad ${sale.profit.toStringAsFixed(2)}'),
          ],
        ),
      ),
    );
  }
}
