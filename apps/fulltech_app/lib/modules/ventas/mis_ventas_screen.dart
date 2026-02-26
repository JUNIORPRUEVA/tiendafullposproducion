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
import 'sales_models.dart';
import 'utils/sales_pdf_service.dart';

final salesGoalProvider = FutureProvider<double>((ref) async {
  final user = ref.watch(authStateProvider).user;
  if (user == null) return 0;
  try {
    return await ref
        .watch(nominaRepositoryProvider)
        .getCuotaMinimaForUser(userId: user.id, userName: user.nombreCompleto);
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
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'sales_summary_fab',
            onPressed: () => _openSummaryDialog(context, state, goal),
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
            _buildGoalCompact(state, goal),
            const SizedBox(height: 10),
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
                    onTap: () => _showDetailsDialog(context, sale),
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.12),
                      child: Icon(
                        Icons.receipt_long_outlined,
                        size: 17,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    title: Text(
                      '${_date(sale.saleDate ?? DateTime.now())} · ${sale.customerName ?? 'Sin cliente'} · Vendido ${_money(sale.totalSold)} · Utilidad ${_money(sale.totalProfit)} · Comisión ${_money(sale.commissionAmount)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) async {
                        if (value == 'delete') {
                          await _deleteSale(context, sale.id);
                        }
                      },
                      itemBuilder: (context) => const [
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

  Widget _buildGoalCompact(VentasState state, double goal) {
    final progress = goal <= 0
        ? 0.0
        : (state.summary.totalSold / goal).clamp(0.0, 1.0).toDouble();
    final progressLabel = '${(progress * 100).toStringAsFixed(1)}%';

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.filter_alt_outlined, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Meta de ventas quincena · ${_date(state.from)} - ${_date(state.to)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  progressLabel,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 8),
            Text(
              'Meta: ${_money(goal)} · Acumulado: ${_money(state.summary.totalSold)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
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

  void _openSummaryDialog(
    BuildContext context,
    VentasState state,
    double goal,
  ) {
    final reachedGoal = goal > 0 && state.summary.totalSold >= goal;
    final gainUnlocked = goal <= 0 || reachedGoal;
    final gainColor = gainUnlocked ? Colors.green : Colors.red;

    showDialog<void>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);

        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.summarize_outlined, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              const Text('Resumen de ventas'),
            ],
          ),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Rango: ${_date(state.from)} - ${_date(state.to)}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                _summaryItem(
                  context,
                  icon: Icons.point_of_sale_outlined,
                  label: 'Total vendido',
                  value: _money(state.summary.totalSold),
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 8),
                _summaryItem(
                  context,
                  icon: Icons.shopping_bag_outlined,
                  label: 'Total costo',
                  value: _money(state.summary.totalCost),
                  color: Colors.blueGrey,
                ),
                const SizedBox(height: 8),
                _summaryItem(
                  context,
                  icon: Icons.trending_up_outlined,
                  label: 'Utilidad total',
                  value: _money(state.summary.totalProfit),
                  color: Colors.teal,
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: gainColor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: gainColor.withValues(alpha: 0.40),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        gainUnlocked
                            ? Icons.workspace_premium_outlined
                            : Icons.lock_outline,
                        color: gainColor,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Ganancia del usuario',
                              style: TextStyle(
                                color: gainColor,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              gainUnlocked
                                  ? 'Disponible por meta alcanzada'
                                  : 'Bloqueada: no le pertenece hasta cumplir la meta',
                              style: TextStyle(
                                color: gainColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        gainUnlocked
                            ? _money(state.summary.totalCommission)
                            : 'BLOQUEADA',
                        style: TextStyle(
                          color: gainColor,
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Meta quincenal: ${_money(goal)}',
                  style: theme.textTheme.bodySmall,
                ),
                Text(
                  'La ganancia del usuario se habilita al cumplir la meta quincenal. Si aún no llega a la meta, ese monto aparece bloqueado.',
                  style: theme.textTheme.bodySmall,
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
    );
  }

  Widget _summaryItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
