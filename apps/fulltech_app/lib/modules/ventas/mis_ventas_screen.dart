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

  bool _isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= 1180;

  String _money(double value) =>
      NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$').format(value);
  String _date(DateTime date) => DateFormat('dd/MM/yyyy').format(date);

  String _quincenaName(DateTime from, DateTime to) {
    if (from.day == 15) return '1ra quincena';
    if (to.day == 14) return '2da quincena';
    return 'Rango personalizado';
  }

  String _quincenaLabel(DateTime from, DateTime to) {
    return '${_quincenaName(from, to)} · ${_date(from)} - ${_date(to)}';
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ventasControllerProvider);
    final user = ref.watch(authStateProvider).user;
    final goalAsync = ref.watch(salesGoalProvider);
    final goal = goalAsync.value ?? 0;
    final isDesktop = _isDesktop(context);

    _maybeNotifyGoal(state, goal);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis Ventas'),
        actions: [
          IconButton(
            tooltip: 'Informe PDF de quincena',
            onPressed: () async {
              await _openPdfPreviewDialog(
                context,
                employeeName: user?.nombreCompleto ?? user?.email ?? 'Empleado',
                state: state,
              );
            },
            icon: const Icon(Icons.picture_as_pdf_outlined),
          ),
        ],
      ),
      drawer: buildAdaptiveDrawer(context, currentUser: user),
      floatingActionButton: isDesktop
          ? null
          : FloatingActionButton.extended(
              heroTag: 'sales_new_fab',
              onPressed: _openRegisterSale,
              icon: const Icon(Icons.add_shopping_cart),
              label: const Text('Registrar venta'),
            ),
      bottomNavigationBar: isDesktop
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                height: 50,
                child: FilledButton.icon(
                  onPressed: () => _openSalesHistoryDialog(context, state),
                  icon: const Icon(Icons.history),
                  label: const Text('Historial de ventas'),
                ),
              ),
            ),
      body: isDesktop
          ? _buildDesktopBody(state, goal, user?.nombreCompleto ?? user?.email)
          : RefreshIndicator(
              onRefresh: () =>
                  ref.read(ventasControllerProvider.notifier).refresh(),
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
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
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
                            Text(
                              'No hay ventas registradas en ${_quincenaLabel(state.from, state.to)}',
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed: _openRegisterSale,
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

  Future<void> _openRegisterSale() async {
    final created = await context.push<bool>(Routes.registrarVenta);
    if (created == true) {
      await ref.read(ventasControllerProvider.notifier).refresh();
    }
  }

  Widget _buildDesktopBody(
    VentasState state,
    double goal,
    String? employeeName,
  ) {
    final averageTicket = state.summary.totalSales == 0
        ? 0.0
        : state.summary.totalSold / state.summary.totalSales;
    final bestSale = state.sales.isEmpty
        ? null
        : (state.sales.toList()
                ..sort((a, b) => b.totalSold.compareTo(a.totalSold)))
              .first;
    final daysWithSales = state.sales
        .map(
          (sale) =>
              DateFormat('yyyy-MM-dd').format(sale.saleDate ?? DateTime.now()),
        )
        .toSet()
        .length;

    return RefreshIndicator(
      onRefresh: () => ref.read(ventasControllerProvider.notifier).refresh(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
        children: [
          _DesktopSalesHero(
            rangeLabel: _quincenaLabel(state.from, state.to),
            totalSold: _money(state.summary.totalSold),
            totalProfit: _money(state.summary.totalProfit),
            totalCommission: _money(state.summary.totalCommission),
            onRegisterSale: _openRegisterSale,
            onOpenHistory: () => _openSalesHistoryDialog(context, state),
            onOpenPdf: () => _openPdfPreviewDialog(
              context,
              employeeName: employeeName ?? 'Empleado',
              state: state,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 360,
                child: Column(
                  children: [
                    _DesktopGoalCard(
                      goal: goal,
                      achieved: state.summary.totalProfit,
                      rangeLabel: _quincenaLabel(state.from, state.to),
                    ),
                    const SizedBox(height: 16),
                    _DesktopMetricsPanel(
                      items: [
                        _DesktopMetricData(
                          title: 'Ventas registradas',
                          value: state.summary.totalSales.toString(),
                          subtitle: 'Operaciones en el rango activo',
                          icon: Icons.receipt_long_outlined,
                        ),
                        _DesktopMetricData(
                          title: 'Ticket promedio',
                          value: _money(averageTicket),
                          subtitle: 'Valor medio por venta',
                          icon: Icons.leaderboard_outlined,
                        ),
                        _DesktopMetricData(
                          title: 'Días con ventas',
                          value: daysWithSales.toString(),
                          subtitle: 'Días con actividad comercial',
                          icon: Icons.calendar_month_outlined,
                        ),
                        _DesktopMetricData(
                          title: 'Mejor venta',
                          value: bestSale == null
                              ? 'RD\$0.00'
                              : _money(bestSale.totalSold),
                          subtitle: bestSale == null
                              ? 'Sin registros todavía'
                              : (bestSale.customerName ?? 'Sin cliente'),
                          icon: Icons.emoji_events_outlined,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _DesktopInsightCard(
                      reachedGoal:
                          goal > 0 && state.summary.totalProfit >= goal,
                      message: goal <= 0
                          ? 'No hay una meta configurada para este usuario. Aun asi puedes usar este panel para monitorear desempeño.'
                          : state.summary.totalProfit >= goal
                          ? 'Meta alcanzada. Tus beneficios ya estan desbloqueados y puedes empujar por una quincena record.'
                          : 'Sigue monitoreando tus puntos acumulados para desbloquear beneficios antes de cerrar la quincena.',
                    ),
                    const SizedBox(height: 16),
                    _buildSalesByDayStats(state),
                  ],
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: _DesktopSalesBoard(
                  state: state,
                  goal: goal,
                  onViewSale: (sale) => _showDetailsDialog(context, sale),
                  onDeleteSale: (sale) => _deleteSale(context, sale.id),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGoalCompact(VentasState state, double goal) {
    final progress = goal <= 0
        ? 0.0
        : (state.summary.totalProfit / goal).clamp(0.0, 1.0).toDouble();
    final progressLabel = '${(progress * 100).toStringAsFixed(0)}%';
    final reachedGoal = goal > 0 && state.summary.totalProfit >= goal;

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
              '${_quincenaLabel(state.from, state.to)} · Meta mínima (puntos): ${_money(goal)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 8),
            Text(
              'Puntos acumulados: ${_money(state.summary.totalProfit)}',
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
    final reachedGoal = goal > 0 && state.summary.totalProfit >= goal;
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
                    'Quincena activa',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _quincenaLabel(state.from, state.to),
              style: Theme.of(context).textTheme.bodySmall,
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
                    'Cantidad',
                    state.summary.totalSales.toString(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _miniMetric(
                    'Total puntos',
                    _money(state.summary.totalProfit),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _miniMetric(
                    'Total beneficio (10%)',
                    _money(state.summary.totalCommission),
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
                      'Comisión por ventas (usuario)',
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
                  : 'Debes alcanzar la meta mínima en puntos para desbloquear beneficios.',
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
    if (state.summary.totalProfit < goal) return;
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
        final media = MediaQuery.sizeOf(context);
        final isCompact = media.width < 520;
        return Dialog(
          insetPadding: EdgeInsets.all(isCompact ? 8 : 16),
          child: SizedBox(
            width: isCompact ? media.width - 16 : 920,
            height: isCompact ? media.height * 0.92 : 760,
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(isCompact ? 10 : 14, 10, 8, 6),
                  child: Row(
                    children: [
                      const Icon(Icons.picture_as_pdf_outlined),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Informe PDF de ventas · ${_quincenaName(state.from, state.to)}',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: isCompact ? 14 : 16,
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
                        label: Text(isCompact ? 'Bajar' : 'Descargar'),
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
                    allowPrinting: true,
                    allowSharing: true,
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

  Future<void> _openSalesHistoryDialog(
    BuildContext context,
    VentasState currentState,
  ) async {
    final repo = ref.read(ventasRepositoryProvider);
    DateTime from = currentState.from;
    DateTime to = currentState.to;
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

          final media = MediaQuery.sizeOf(context);
          final isCompact = media.width < 560;
          final filteredCount = items.length;
          final filteredSold = items.fold<double>(
            0,
            (sum, sale) => sum + sale.totalSold,
          );
          final filteredPoints = items.fold<double>(
            0,
            (sum, sale) => sum + sale.totalProfit,
          );
          final filteredBenefit = items.fold<double>(
            0,
            (sum, sale) => sum + sale.commissionAmount,
          );
          final scheme = Theme.of(context).colorScheme;

          return Dialog(
            insetPadding: EdgeInsets.all(isCompact ? 8 : 16),
            child: SizedBox(
              width: isCompact ? media.width - 16 : 760,
              height: isCompact ? media.height * 0.92 : 560,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Historial de ventas',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Cerrar',
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Quincena visible: ${_quincenaLabel(from, to)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest.withValues(
                          alpha: 0.45,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: scheme.outlineVariant.withValues(alpha: 0.65),
                        ),
                      ),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            SizedBox(
                              width: isCompact ? 165 : 200,
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
                            SizedBox(
                              width: isCompact ? 165 : 200,
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
                            SizedBox(
                              width: isCompact ? 120 : 130,
                              child: FilledButton.icon(
                                onPressed: loading
                                    ? null
                                    : () => load(setStateDialog),
                                icon: const Icon(Icons.filter_alt_outlined),
                                label: const Text('Filtrar'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 4,
                        children: [
                          Text(
                            'Cantidad: $filteredCount',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text('Vendido: ${_money(filteredSold)}'),
                          Text('Puntos: ${_money(filteredPoints)}'),
                          Text(
                            'Beneficio 10%: ${_money(filteredBenefit)}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
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
                    Expanded(
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
                                  onTap: () =>
                                      _showDetailsDialog(context, sale),
                                  title: Text(
                                    '${_date(sale.saleDate ?? DateTime.now())} · ${sale.customerName ?? 'Sin cliente'}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    'Vendido ${_money(sale.totalSold)} · Comisión ${_money(sale.commissionAmount)}',
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: 'Ver detalle',
                                        onPressed: () =>
                                            _showDetailsDialog(context, sale),
                                        icon: const Icon(
                                          Icons.visibility_outlined,
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Eliminar',
                                        onPressed: () =>
                                            _deleteSale(context, sale.id),
                                        icon: const Icon(Icons.delete_outline),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DesktopSalesHero extends StatelessWidget {
  const _DesktopSalesHero({
    required this.rangeLabel,
    required this.totalSold,
    required this.totalProfit,
    required this.totalCommission,
    required this.onRegisterSale,
    required this.onOpenHistory,
    required this.onOpenPdf,
  });

  final String rangeLabel;
  final String totalSold;
  final String totalProfit;
  final String totalCommission;
  final VoidCallback onRegisterSale;
  final VoidCallback onOpenHistory;
  final VoidCallback onOpenPdf;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1D4ED8), Color(0xFF0F172A)],
        ),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withValues(alpha: 0.18),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Panel comercial de escritorio',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Controla tus ventas, monitorea el avance de tu meta y revisa tu rendimiento quincenal desde una vista mas clara.',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: Colors.white.withValues(alpha: 0.82),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _DesktopHeroChip(
                      icon: Icons.event_note_outlined,
                      label: 'Rango',
                      value: rangeLabel,
                    ),
                    _DesktopHeroChip(
                      icon: Icons.payments_outlined,
                      label: 'Vendido',
                      value: totalSold,
                    ),
                    _DesktopHeroChip(
                      icon: Icons.auto_graph_outlined,
                      label: 'Puntos',
                      value: totalProfit,
                    ),
                    _DesktopHeroChip(
                      icon: Icons.workspace_premium_outlined,
                      label: 'Beneficio',
                      value: totalCommission,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 18),
          SizedBox(
            width: 240,
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onRegisterSale,
                    icon: const Icon(Icons.add_shopping_cart),
                    label: const Text('Registrar venta'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF0F172A),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onOpenHistory,
                    icon: const Icon(Icons.history),
                    label: const Text('Historial'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.35),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onOpenPdf,
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('Exportar PDF'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.35),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopHeroChip extends StatelessWidget {
  const _DesktopHeroChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 150, maxWidth: 240),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.72),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopGoalCard extends StatelessWidget {
  const _DesktopGoalCard({
    required this.goal,
    required this.achieved,
    required this.rangeLabel,
  });

  final double goal;
  final double achieved;
  final String rangeLabel;

  @override
  Widget build(BuildContext context) {
    final progress = goal <= 0 ? 0.0 : (achieved / goal).clamp(0.0, 1.0);
    final reachedGoal = goal > 0 && achieved >= goal;
    final accent = reachedGoal
        ? const Color(0xFF15803D)
        : const Color(0xFFEA580C);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.track_changes_outlined, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Meta quincenal',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      rangeLabel,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 12,
              color: accent,
              backgroundColor: accent.withValues(alpha: 0.12),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _DesktopMiniStat(
                  label: 'Acumulado',
                  value: NumberFormat.currency(
                    locale: 'es_DO',
                    symbol: 'RD\$',
                  ).format(achieved),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DesktopMiniStat(
                  label: 'Meta',
                  value: NumberFormat.currency(
                    locale: 'es_DO',
                    symbol: 'RD\$',
                  ).format(goal),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            reachedGoal
                ? 'Meta alcanzada. La comision ya esta desbloqueada para esta quincena.'
                : 'Vas en ${(progress * 100).toStringAsFixed(0)}% de tu objetivo actual.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _DesktopMiniStat extends StatelessWidget {
  const _DesktopMiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _DesktopMetricsPanel extends StatelessWidget {
  const _DesktopMetricsPanel({required this.items});

  final List<_DesktopMetricData> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Resumen ejecutivo',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              mainAxisExtent: 118,
            ),
            itemBuilder: (context, index) {
              final item = items[index];
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      item.icon,
                      size: 18,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      item.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.title,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DesktopMetricData {
  const _DesktopMetricData({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
}

class _DesktopInsightCard extends StatelessWidget {
  const _DesktopInsightCard({required this.reachedGoal, required this.message});

  final bool reachedGoal;
  final String message;

  @override
  Widget build(BuildContext context) {
    final accent = reachedGoal
        ? const Color(0xFF15803D)
        : const Color(0xFF1D4ED8);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.10),
            accent.withValues(alpha: 0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            reachedGoal ? Icons.lock_open_outlined : Icons.insights_outlined,
            color: accent,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reachedGoal ? 'Estado de beneficios' : 'Siguiente enfoque',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(message, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopSalesBoard extends StatelessWidget {
  const _DesktopSalesBoard({
    required this.state,
    required this.goal,
    required this.onViewSale,
    required this.onDeleteSale,
  });

  final VentasState state;
  final double goal;
  final ValueChanged<SaleModel> onViewSale;
  final ValueChanged<SaleModel> onDeleteSale;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ventas recientes',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Gestiona tus ventas actuales y revisa el detalle de cada operacion sin salir del panel.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  '${state.sales.length} ventas',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: scheme.primary,
                  ),
                ),
              ),
            ],
          ),
          if (state.loading) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          if (state.error != null) ...[
            const SizedBox(height: 12),
            Text(
              state.error!,
              style: TextStyle(
                color: scheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (state.sales.isEmpty && !state.loading)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.receipt_long_outlined,
                      size: 58,
                      color: scheme.outline,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No hay ventas registradas',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Cuando empieces a vender, esta vista mostrara el resumen de cada operacion y tu avance hacia la meta.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 1100 ? 2 : 1;
                final gap = 14.0;
                final cardWidth =
                    (constraints.maxWidth - gap * (columns - 1)) / columns;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: state.sales
                      .map(
                        (sale) => SizedBox(
                          width: cardWidth,
                          child: _DesktopSaleCard(
                            sale: sale,
                            goal: goal,
                            money: NumberFormat.currency(
                              locale: 'es_DO',
                              symbol: 'RD\$',
                            ).format,
                            onView: () => onViewSale(sale),
                            onDelete: () => onDeleteSale(sale),
                          ),
                        ),
                      )
                      .toList(growable: false),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _DesktopSaleCard extends StatelessWidget {
  const _DesktopSaleCard({
    required this.sale,
    required this.goal,
    required this.money,
    required this.onView,
    required this.onDelete,
  });

  final SaleModel sale;
  final double goal;
  final String Function(double value) money;
  final VoidCallback onView;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final saleDate = sale.saleDate ?? DateTime.now();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final unlocked = goal <= 0 || sale.totalProfit >= goal;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
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
                      sale.customerName ?? 'Sin cliente',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      DateFormat('dd/MM/yyyy').format(saleDate),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'view') onView();
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'view', child: Text('Ver detalle')),
                  PopupMenuItem(value: 'delete', child: Text('Eliminar')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _DesktopMiniStat(
                  label: 'Vendido',
                  value: money(sale.totalSold),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _DesktopMiniStat(
                  label: 'Puntos',
                  value: money(sale.totalProfit),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _DesktopMiniStat(
                  label: 'Beneficio',
                  value: money(sale.commissionAmount),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: sale.items
                .take(3)
                .map(
                  (item) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${item.productNameSnapshot} x${item.qty.toStringAsFixed(item.qty % 1 == 0 ? 0 : 2)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
          if ((sale.note ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              sale.note!.trim(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ],
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color:
                  (unlocked ? const Color(0xFF15803D) : const Color(0xFFB91C1C))
                      .withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(
                  unlocked ? Icons.lock_open_outlined : Icons.lock_outline,
                  size: 18,
                  color: unlocked
                      ? const Color(0xFF15803D)
                      : const Color(0xFFB91C1C),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    unlocked
                        ? 'Beneficio listo para esta venta'
                        : 'Sigue empujando la meta general',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
