import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/routing/routes.dart';
import '../../core/widgets/app_drawer.dart';
import '../nomina/data/nomina_repository.dart';
import 'application/ventas_controller.dart';
import 'sales_models.dart';
import 'utils/print_service_stub.dart'
    if (dart.library.html) 'utils/print_service_web.dart';

final salesGoalProvider = FutureProvider<double>((ref) async {
  final user = ref.watch(authStateProvider).user;
  if (user == null) return 0;
  return ref
      .watch(nominaRepositoryProvider)
      .getCuotaMinimaForUser(userId: user.id, userName: user.nombreCompleto);
});

class MisVentasScreen extends ConsumerStatefulWidget {
  const MisVentasScreen({super.key});

  @override
  ConsumerState<MisVentasScreen> createState() => _MisVentasScreenState();
}

class _MisVentasScreenState extends ConsumerState<MisVentasScreen> {
  bool _goalNotified = false;
  String _lastRangeKey = '';

  String _money(double value) =>
      NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$').format(value);
  String _date(DateTime date) => DateFormat('dd/MM/yyyy').format(date);

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ventasControllerProvider);
    final user = ref.watch(authStateProvider).user;
    final goalAsync = ref.watch(salesGoalProvider);

    final goal = goalAsync.value ?? 0;
    _maybeNotifyGoal(state, goal);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis Ventas'),
        actions: [
          IconButton(
            tooltip: 'Filtrar por fecha',
            onPressed: () async {
              final range = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2024),
                lastDate: DateTime(2100),
                initialDateRange: DateTimeRange(
                  start: state.from,
                  end: state.to,
                ),
              );
              if (range == null) return;
              await ref
                  .read(ventasControllerProvider.notifier)
                  .setCustomRange(range.start, range.end);
            },
            icon: const Icon(Icons.date_range),
          ),
          IconButton(
            tooltip: 'Generar comprobante',
            onPressed: state.sales.isEmpty
                ? null
                : () async {
                    try {
                      await printSalesSummary(
                        employeeName:
                            user?.nombreCompleto ?? user?.email ?? 'Empleado',
                        from: state.from,
                        to: state.to,
                        summary: state.summary,
                        sales: state.sales,
                      );
                    } catch (_) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Impresión disponible en web'),
                        ),
                      );
                    }
                  },
            icon: const Icon(Icons.print_outlined),
          ),
        ],
      ),
      drawer: AppDrawer(currentUser: user),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'sales_summary_fab',
            onPressed: () => _openSummaryDialog(context, state),
            icon: const Icon(Icons.summarize_outlined),
            label: const Text('Resumen'),
          ),
          const SizedBox(height: 10),
          FloatingActionButton.extended(
            heroTag: 'sales_new_fab',
            onPressed: () async {
              final created = await context.push<bool>(Routes.registrarVenta);
              if (created == true) {
                await ref.read(ventasControllerProvider.notifier).refresh();
              }
            },
            icon: const Icon(Icons.add_shopping_cart),
            label: const Text('Registrar venta'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(ventasControllerProvider.notifier).refresh(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          children: [
            _buildGoalHeader(state, goal),
            const SizedBox(height: 10),
            _buildSummary(state),
            const SizedBox(height: 16),
            if (state.loading) const LinearProgressIndicator(),
            if (state.error != null) ...[
              const SizedBox(height: 8),
              Text(
                state.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 8),
            if (state.sales.isEmpty && !state.loading)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Icon(Icons.receipt_long_outlined, size: 44),
                      const SizedBox(height: 8),
                      const Text('No hay ventas en este rango'),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () async {
                          final created = await context.push<bool>(
                            Routes.registrarVenta,
                          );
                          if (created == true) {
                            await ref
                                .read(ventasControllerProvider.notifier)
                                .refresh();
                          }
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('Registrar primera venta'),
                      ),
                    ],
                  ),
                ),
              ),
            ...state.sales.map(
              (sale) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    title: Text(
                      '${_date(sale.saleDate ?? DateTime.now())} · ${sale.customerName ?? 'Sin cliente'}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Wrap(
                        spacing: 14,
                        runSpacing: 6,
                        children: [
                          Text('Vendido: ${_money(sale.totalSold)}'),
                          Text('Utilidad: ${_money(sale.totalProfit)}'),
                          Text('Comisión: ${_money(sale.commissionAmount)}'),
                        ],
                      ),
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) async {
                        if (value == 'details') {
                          _showDetails(context, sale);
                          return;
                        }
                        if (value == 'delete') {
                          await _deleteSale(context, sale.id);
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'details',
                          child: Text('Ver detalles'),
                        ),
                        PopupMenuItem(value: 'delete', child: Text('Eliminar')),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGoalHeader(VentasState state, double goal) {
    final progress = goal <= 0
        ? 0.0
        : (state.summary.totalSold / goal).clamp(0.0, 1.0).toDouble();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.filter_alt_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Meta quincenal: ${_money(goal)} · Acumulado: ${_money(state.summary.totalSold)}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Rango activo: ${_date(state.from)} - ${_date(state.to)}',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 6),
            Text('${(progress * 100).toStringAsFixed(1)}% de la meta'),
          ],
        ),
      ),
    );
  }

  Widget _buildSummary(VentasState state) {
    return Row(
      children: [
        Expanded(child: _kpi('Total vendido', _money(state.summary.totalSold))),
        const SizedBox(width: 8),
        Expanded(
          child: _kpi('Total utilidad', _money(state.summary.totalProfit)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _kpi('Total comisión', _money(state.summary.totalCommission)),
        ),
      ],
    );
  }

  Widget _kpi(String label, String value) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  void _showDetails(BuildContext context, SaleModel sale) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: ListView(
            shrinkWrap: true,
            children: [
              Text(
                'Venta ${sale.id.substring(0, 8)}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text('Cliente: ${sale.customerName ?? 'Sin cliente'}'),
              Text(
                'Nota: ${(sale.note ?? '').trim().isEmpty ? 'N/A' : sale.note}',
              ),
              const SizedBox(height: 12),
              ...sale.items.map(
                (item) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(item.productNameSnapshot),
                  subtitle: Text(
                    'Qty: ${item.qty} · Precio: ${_money(item.priceSoldUnit)} · Costo: ${_money(item.costUnitSnapshot)}',
                  ),
                  trailing: Text(_money(item.subtotalSold)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _deleteSale(BuildContext context, String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar venta'),
        content: const Text(
          'Esta acción ocultará la venta del historial. ¿Deseas continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await ref.read(ventasControllerProvider.notifier).deleteSale(id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Venta eliminada')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo eliminar: $e')));
    }
  }

  void _maybeNotifyGoal(VentasState state, double goal) {
    final rangeKey =
        '${state.from.toIso8601String()}_${state.to.toIso8601String()}';
    if (_lastRangeKey != rangeKey) {
      _lastRangeKey = rangeKey;
      _goalNotified = false;
    }

    if (goal <= 0) return;
    if (state.summary.totalSold < goal) return;
    if (_goalNotified) return;

    _goalNotified = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🎉 Felicidades, has llegado a tu meta de ventas'),
        ),
      );
    });
  }

  void _openSummaryDialog(BuildContext context, VentasState state) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Resumen de ventas'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Rango: ${_date(state.from)} - ${_date(state.to)}'),
            const SizedBox(height: 8),
            Text('Total vendido: ${_money(state.summary.totalSold)}'),
            Text('Total costo: ${_money(state.summary.totalCost)}'),
            Text('Utilidad: ${_money(state.summary.totalProfit)}'),
            Text('Comisión (10%): ${_money(state.summary.totalCommission)}'),
            const SizedBox(height: 10),
            const Text(
              'Cálculo:\n'
              'Total vendido = Σ(cantidad × precio vendido)\n'
              'Total costo = Σ(cantidad × costo)\n'
              'Utilidad = Total vendido - Total costo\n'
              'Comisión = 10% de la utilidad (si utilidad < 0, comisión = 0)',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }
}
