import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/sale_model.dart';
import '../application/sales_controller.dart';

class SalesHistoryView extends ConsumerWidget {
  const SalesHistoryView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(salesHistoryProvider);
    final ctrl = ref.read(salesHistoryProvider.notifier);

    return RefreshIndicator(
      onRefresh: () =>
          ctrl.load(from: state.from, to: state.to, status: state.status),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              _FilterChip(
                label: 'Hoy',
                selected:
                    state.from != null &&
                    state.to != null &&
                    _isSameDay(state.from!, DateTime.now()),
                onTap: () => ctrl.refreshForToday(),
              ),
              const SizedBox(width: 8),
              _FilterChip(
                label: 'Ayer',
                selected:
                    state.from != null &&
                    state.to != null &&
                    _isSameDay(
                      state.from!,
                      DateTime.now().subtract(const Duration(days: 1)),
                    ),
                onTap: () {
                  final yesterday = DateTime.now().subtract(
                    const Duration(days: 1),
                  );
                  final start = DateTime(
                    yesterday.year,
                    yesterday.month,
                    yesterday.day,
                  );
                  ctrl.load(from: start, to: start);
                },
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => _pickRange(context, ctrl),
                icon: const Icon(Icons.calendar_today, size: 18),
                label: const Text('Rango'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _SummaryBar(summary: state.summary),
          const SizedBox(height: 12),
          if (state.loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            ),
          if (state.error != null)
            Text(
              state.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ...state.items.map((s) => _SaleCard(sale: s)),
        ],
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> _pickRange(
    BuildContext context,
    SalesHistoryController ctrl,
  ) async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 1),
    );
    if (picked != null) {
      await ctrl.load(from: picked.start, to: picked.end);
    }
  }
}

class _SaleCard extends StatelessWidget {
  final SaleModel sale;
  const _SaleCard({required this.sale});

  Color _statusColor(BuildContext context) {
    switch (sale.status) {
      case saleStatusConfirmed:
        return Colors.green.shade600;
      case saleStatusCancelled:
        return Theme.of(context).colorScheme.error;
      default:
        return Colors.orange.shade700;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _statusColor(context).withValues(alpha: 0.15),
          child: Icon(Icons.receipt_long, color: _statusColor(context)),
        ),
        title: Text(sale.clientName ?? 'Sin cliente'),
        subtitle: Text(
          '${sale.soldAt.toLocal()}\nUtilidad: ${sale.profit.toStringAsFixed(2)} · Comisión: ${sale.commission.toStringAsFixed(2)}',
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              sale.subtotal.toStringAsFixed(2),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Chip(
              label: Text(sale.status),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
        onTap: () => _showDetail(context, sale),
      ),
    );
  }

  void _showDetail(BuildContext context, SaleModel sale) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ticket ${sale.id}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text('Cliente: ${sale.clientName ?? 'N/A'}'),
            Text('Estado: ${sale.status}'),
            Text('Nota: ${sale.note ?? '-'}'),
            const Divider(),
            ...sale.items.map(
              (i) => ListTile(
                dense: true,
                title: Text(i.productName),
                subtitle: Text(
                  'Cant ${i.qty} · Precio ${i.unitPrice.toStringAsFixed(2)}',
                ),
                trailing: Text(i.lineTotal.toStringAsFixed(2)),
              ),
            ),
            const Divider(),
            Text('Subtotal: ${sale.subtotal.toStringAsFixed(2)}'),
            Text('Utilidad: ${sale.profit.toStringAsFixed(2)}'),
            Text('Comisión: ${sale.commission.toStringAsFixed(2)}'),
          ],
        ),
      ),
    );
  }
}

class _SummaryBar extends StatelessWidget {
  final Map<String, dynamic> summary;
  const _SummaryBar({required this.summary});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _KpiTile(label: 'Ventas', value: '${summary['count'] ?? 0}'),
        _KpiTile(label: 'Ingresos', value: summary['totalRevenue'] ?? '0'),
        _KpiTile(label: 'Utilidad', value: summary['totalProfit'] ?? '0'),
        _KpiTile(label: 'Comisión', value: summary['totalCommission'] ?? '0'),
      ],
    );
  }
}

class _KpiTile extends StatelessWidget {
  final String label;
  final String value;
  const _KpiTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Column(
            children: [
              Text(label, style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 4),
              Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      selected: selected,
      label: Text(label),
      onSelected: (_) => onTap(),
    );
  }
}
