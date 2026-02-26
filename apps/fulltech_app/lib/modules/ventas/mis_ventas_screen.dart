import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/routing/routes.dart';
import '../../core/widgets/app_drawer.dart';
import '../nomina/data/nomina_repository.dart';
import 'application/ventas_controller.dart';
import 'data/ventas_repository.dart';
import 'sales_models.dart';
import 'utils/sales_pdf_service.dart';

final salesGoalProvider = FutureProvider<double>((ref) async {
  final user = ref.watch(authStateProvider).user;
  if (user == null) return 0;
  try {
    return await ref.watch(nominaRepositoryProvider).getCuotaMinimaForUser();
  } catch (_) {
    return 0;
  }
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
            tooltip: 'Ver informe PDF',
            onPressed: state.sales.isEmpty
                ? null
                : () async {
                    await _openPdfPreviewDialog(
                      context,
                      employeeName:
                          user?.nombreCompleto ?? user?.email ?? 'Empleado',
                      state: state,
                    );
                  },
            icon: const Icon(Icons.picture_as_pdf_outlined),
          ),
        ],
      ),
      drawer: AppDrawer(currentUser: user),
      floatingActionButton: FloatingActionButton.extended(
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
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: SizedBox(
          height: 50,
          child: FilledButton.icon(
            onPressed: () => _openSalesHistoryDialog(context),
            icon: const Icon(Icons.history),
            label: const Text('Historial de ventas'),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(ventasControllerProvider.notifier).refresh(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
          children: [
            _buildGoalCompact(state, goal),
            const SizedBox(height: 10),
            _buildCurrentQuincenaCard(state, goal),
            const SizedBox(height: 10),
            _buildSalesByDayStats(state),
            if (state.loading) const LinearProgressIndicator(),
            if (state.error != null) ...[
              const SizedBox(height: 8),
              Text(
                state.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 10),
            if (state.sales.isEmpty && !state.loading)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Icon(Icons.receipt_long_outlined, size: 44),
                      const SizedBox(height: 8),
                      const Text('No hay ventas registradas en esta quincena'),
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
                        label: const Text('Registrar venta'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildGoalCompact(VentasState state, double goal) {
    final progress = goal <= 0
        ? 0.0
        : (state.summary.totalSold / goal).clamp(0.0, 1.0).toDouble();
    final progressLabel = '${(progress * 100).toStringAsFixed(0)}%';
    final reachedGoal = goal > 0 && state.summary.totalSold >= goal;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.filter_alt_outlined, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Embudo de meta quincenal',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: reachedGoal
                        ? Colors.green.withValues(alpha: 0.12)
                        : Colors.orange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(
                    progressLabel,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${_date(state.from)} - ${_date(state.to)} · Meta mínima: ${_money(goal)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 8),
            Text(
              'Acumulado actual: ${_money(state.summary.totalSold)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentQuincenaCard(VentasState state, double goal) {
    final reachedGoal = goal > 0 && state.summary.totalSold >= goal;
    final lockColor = reachedGoal ? Colors.green : Colors.red;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.event_note_outlined, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Quincena actual fija',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  '${_date(state.from)} - ${_date(state.to)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _miniMetric(
                    'Total vendido',
                    _money(state.summary.totalSold),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _miniMetric(
                    'Total puntos',
                    state.summary.totalSales.toString(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                color: lockColor.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: lockColor.withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  Icon(
                    reachedGoal ? Icons.lock_open_outlined : Icons.lock_outline,
                    color: lockColor,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Comisión por ventas',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    reachedGoal
                        ? _money(state.summary.totalCommission)
                        : 'BLOQUEADA',
                    style: TextStyle(
                      color: lockColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              reachedGoal
                  ? 'Meta alcanzada: beneficios desbloqueados.'
                  : 'Debes alcanzar la meta mínima para desbloquear beneficios extras.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniMetric(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _buildSalesByDayStats(VentasState state) {
    final totalsByDay = <String, double>{};
    for (final sale in state.sales) {
      final date = sale.saleDate ?? DateTime.now();
      final key = DateFormat('dd/MM').format(date);
      totalsByDay.update(
        key,
        (value) => value + sale.totalSold,
        ifAbsent: () => sale.totalSold,
      );
    }

    final entries = totalsByDay.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = entries.take(6).toList();
    final maxValue = top.isEmpty ? 1.0 : top.first.value;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.bar_chart_outlined, size: 18),
                SizedBox(width: 8),
                Text(
                  'Ventas por día',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (top.isEmpty)
              Text(
                'Aún no hay datos para estadísticas de días.',
                style: Theme.of(context).textTheme.bodySmall,
              )
            else
              ...top.map((entry) {
                final ratio = (entry.value / maxValue).clamp(0.0, 1.0);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 48,
                        child: Text(
                          entry.key,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(value: ratio),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 90,
                        child: Text(
                          _money(entry.value),
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  void _showDetailsDialog(BuildContext context, SaleModel sale) {
    showDialog<void>(
      context: context,
      builder: (context) {
        final saleDate = sale.saleDate ?? DateTime.now();
        return AlertDialog(
          title: Text('Cotización · Venta ${sale.id.substring(0, 8)}'),
          content: SizedBox(
            width: 680,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _detailLine('Fecha', _date(saleDate)),
                  _detailLine('Cliente', sale.customerName ?? 'Sin cliente'),
                  _detailLine(
                    'Nota',
                    (sale.note ?? '').trim().isEmpty ? 'N/A' : sale.note!,
                  ),
                  const Divider(height: 20),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: const [
                        Expanded(
                          flex: 5,
                          child: Text(
                            'Producto',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            'Cantidad',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            'Precio U.',
                            textAlign: TextAlign.right,
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            'Total',
                            textAlign: TextAlign.right,
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  ...sale.items.asMap().entries.map((entry) {
                    final item = entry.value;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 5,
                            child: Text(
                              item.productNameSnapshot,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              item.qty.toString(),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              _money(item.priceSoldUnit),
                              textAlign: TextAlign.right,
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              _money(item.subtotalSold),
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      width: 330,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        children: [
                          _totalsLine('Total vendido', _money(sale.totalSold)),
                          _totalsLine('Total costo', _money(sale.totalCost)),
                          _totalsLine(
                            'Total utilidad',
                            _money(sale.totalProfit),
                          ),
                          const Divider(height: 14),
                          _totalsLine(
                            'Comisión',
                            _money(sale.commissionAmount),
                            highlight: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }

  Widget _totalsLine(String label, String value, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: highlight ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
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
          content: Text('🎉 Felicidades, has alcanzado tu meta de ventas'),
        ),
      );
    });
  }

  Future<void> _openPdfPreviewDialog(
    BuildContext context, {
    required String employeeName,
    required VentasState state,
  }) async {
    final pdfBytes = await buildSalesSummaryPdf(
      employeeName: employeeName,
      from: state.from,
      to: state.to,
      summary: state.summary,
      sales: state.sales,
    );

    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: SizedBox(
            width: 920,
            height: 760,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 8, 6),
                  child: Row(
                    children: [
                      const Icon(Icons.picture_as_pdf_outlined),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Informe PDF de ventas',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          await downloadSalesSummaryPdf(
                            bytes: pdfBytes,
                            from: state.from,
                            to: state.to,
                          );
                        },
                        icon: const Icon(Icons.download_outlined),
                        label: const Text('Descargar'),
                      ),
                      IconButton(
                        tooltip: 'Cerrar',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: PdfPreview(
                    canChangePageFormat: false,
                    canChangeOrientation: false,
                    canDebug: false,
                    allowPrinting: false,
                    allowSharing: false,
                    build: (_) async => pdfBytes,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openSalesHistoryDialog(BuildContext context) async {
    final repo = ref.read(ventasRepositoryProvider);
    DateTime from = DateTime(DateTime.now().year, DateTime.now().month, 1);
    DateTime to = DateTime.now();
    List<SaleModel> items = const [];
    bool loading = false;
    String? error;
    bool initialized = false;

    Future<void> load(StateSetter setStateDialog) async {
      setStateDialog(() {
        loading = true;
        error = null;
      });
      try {
        final rows = await repo.listSales(from: from, to: to);
        if (!context.mounted) return;
        setStateDialog(() {
          items = rows;
          loading = false;
        });
      } catch (e) {
        if (!context.mounted) return;
        setStateDialog(() {
          loading = false;
          error = '$e';
        });
      }
    }

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          if (!initialized) {
            initialized = true;
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => load(setStateDialog),
            );
          }

          return AlertDialog(
            title: const Text('Historial de ventas'),
            content: SizedBox(
              width: 720,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: from,
                              firstDate: DateTime(2024),
                              lastDate: DateTime(2100),
                            );
                            if (picked == null) return;
                            setStateDialog(
                              () => from = DateTime(
                                picked.year,
                                picked.month,
                                picked.day,
                              ),
                            );
                          },
                          icon: const Icon(Icons.event),
                          label: Text('Desde ${_date(from)}'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: to,
                              firstDate: DateTime(2024),
                              lastDate: DateTime(2100),
                            );
                            if (picked == null) return;
                            setStateDialog(
                              () => to = DateTime(
                                picked.year,
                                picked.month,
                                picked.day,
                              ),
                            );
                          },
                          icon: const Icon(Icons.event_available),
                          label: Text('Hasta ${_date(to)}'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: loading ? null : () => load(setStateDialog),
                        child: const Text('Filtrar'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (loading) const LinearProgressIndicator(),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 380,
                    child: items.isEmpty && !loading
                        ? const Center(
                            child: Text('No hay ventas en este rango'),
                          )
                        : ListView.separated(
                            itemCount: items.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final sale = items[index];
                              return ListTile(
                                onTap: () => _showDetailsDialog(context, sale),
                                title: Text(
                                  '${_date(sale.saleDate ?? DateTime.now())} · ${sale.customerName ?? 'Sin cliente'}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  'Vendido ${_money(sale.totalSold)} · Comisión ${_money(sale.commissionAmount)}',
                                ),
                                trailing: IconButton(
                                  tooltip: 'Eliminar',
                                  onPressed: () =>
                                      _deleteSale(context, sale.id),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cerrar'),
              ),
            ],
          );
        },
      ),
    );
  }
}
