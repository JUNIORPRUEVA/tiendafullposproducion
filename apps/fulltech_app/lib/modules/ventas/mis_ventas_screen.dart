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

  List<_SalesDayPoint> _salesDayPoints(VentasState state) {
    final totalsByDay = <DateTime, double>{};
    for (final sale in state.sales) {
      final date = sale.saleDate ?? DateTime.now();
      final day = DateTime(date.year, date.month, date.day);
      totalsByDay.update(
        day,
        (value) => value + sale.totalSold,
        ifAbsent: () => sale.totalSold,
      );
    }

    final points =
        totalsByDay.entries
            .map((entry) => _SalesDayPoint(day: entry.key, total: entry.value))
            .toList(growable: false)
          ..sort((a, b) => a.day.compareTo(b.day));

    if (points.length <= 7) return points;
    return points.sublist(points.length - 7);
  }

  List<_TopProductStat> _topProducts(VentasState state) {
    final totals = <String, double>{};
    for (final sale in state.sales) {
      for (final item in sale.items) {
        final key = item.productNameSnapshot.trim();
        if (key.isEmpty) continue;
        totals.update(
          key,
          (value) => value + item.qty,
          ifAbsent: () => item.qty,
        );
      }
    }

    final rows =
        totals.entries
            .map(
              (entry) =>
                  _TopProductStat(name: entry.key, quantity: entry.value),
            )
            .toList(growable: false)
          ..sort((a, b) => b.quantity.compareTo(a.quantity));
    return rows.take(4).toList(growable: false);
  }

  List<_SalesWeekdayStat> _salesWeekdayStats(VentasState state) {
    final totals = <int, double>{for (var day = 1; day <= 7; day++) day: 0};
    for (final sale in state.sales) {
      final date = sale.saleDate ?? DateTime.now();
      totals.update(
        date.weekday,
        (value) => value + sale.totalSold,
        ifAbsent: () => sale.totalSold,
      );
    }

    return List.generate(
      7,
      (index) => _SalesWeekdayStat(
        weekday: index + 1,
        label: _weekdayShortLabel(index + 1),
        total: totals[index + 1] ?? 0,
      ),
      growable: false,
    );
  }

  String _weekdayShortLabel(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return 'Lun';
      case DateTime.tuesday:
        return 'Mar';
      case DateTime.wednesday:
        return 'Mie';
      case DateTime.thursday:
        return 'Jue';
      case DateTime.friday:
        return 'Vie';
      case DateTime.saturday:
        return 'Sab';
      case DateTime.sunday:
        return 'Dom';
    }
    return '';
  }

  String _moneyCompact(double value) {
    final absValue = value.abs();
    if (absValue >= 1000000) {
      return 'RD\$${(value / 1000000).toStringAsFixed(1)}M';
    }
    if (absValue >= 1000) {
      return 'RD\$${(value / 1000).toStringAsFixed(1)}k';
    }
    return 'RD\$${value.toStringAsFixed(0)}';
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
    final dayPoints = _salesDayPoints(state);
    final weekdayStats = _salesWeekdayStats(state);
    final topProducts = _topProducts(state);
    final remainingToGoal = goal > state.summary.totalProfit
        ? goal - state.summary.totalProfit
        : 0.0;
    final today = DateTime.now();
    final rangeEnd = DateTime(state.to.year, state.to.month, state.to.day);
    final safeToday = DateTime(today.year, today.month, today.day);
    final daysLeft = rangeEnd.isBefore(safeToday)
        ? 0
        : rangeEnd.difference(safeToday).inDays + 1;
    final neededPerDay = remainingToGoal > 0 && daysLeft > 0
        ? remainingToGoal / daysLeft
        : 0.0;
    final bestDay = dayPoints.isEmpty
        ? null
        : (dayPoints.toList()..sort((a, b) => b.total.compareTo(a.total)))
              .first;
    final averageDailySales = dayPoints.isEmpty
        ? 0.0
        : state.summary.totalSold / dayPoints.length;
    final strongestWeekday = weekdayStats
        .where((item) => item.total > 0)
        .fold<_SalesWeekdayStat?>(null, (current, item) {
          if (current == null || item.total > current.total) return item;
          return current;
        });

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
                    _DesktopGapCard(
                      remainingToGoal: remainingToGoal,
                      daysLeft: daysLeft,
                      neededPerDay: neededPerDay,
                      money: _money,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: _DesktopPerformanceBoard(
                  state: state,
                  goal: goal,
                  dayPoints: dayPoints,
                  weekdayStats: weekdayStats,
                  topProducts: topProducts,
                  bestDay: bestDay,
                  strongestWeekday: strongestWeekday,
                  averageDailySales: averageDailySales,
                  money: _money,
                  compactMoney: _moneyCompact,
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
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Wrap(
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
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 224,
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

class _DesktopGapCard extends StatelessWidget {
  const _DesktopGapCard({
    required this.remainingToGoal,
    required this.daysLeft,
    required this.neededPerDay,
    required this.money,
  });

  final double remainingToGoal;
  final int daysLeft;
  final double neededPerDay;
  final String Function(double value) money;

  @override
  Widget build(BuildContext context) {
    final reached = remainingToGoal <= 0;
    final accent = reached ? const Color(0xFF15803D) : const Color(0xFFB45309);
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
          Row(
            children: [
              Icon(
                reached ? Icons.check_circle_outline : Icons.flag_outlined,
                color: accent,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  reached ? 'Objetivo cubierto' : 'Lo que falta por lograr',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            reached
                ? 'Ya alcanzaste la meta de la quincena. Todo lo que generes ahora suma por encima del objetivo.'
                : 'Te faltan ${money(remainingToGoal)} para completar la meta. ${daysLeft <= 0 ? 'El rango actual ya cerró.' : 'Si mantienes un ritmo de ${money(neededPerDay)} por dia, llegas a tiempo.'}',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _DesktopPerformanceBoard extends StatelessWidget {
  const _DesktopPerformanceBoard({
    required this.state,
    required this.goal,
    required this.dayPoints,
    required this.weekdayStats,
    required this.topProducts,
    required this.bestDay,
    required this.strongestWeekday,
    required this.averageDailySales,
    required this.money,
    required this.compactMoney,
  });

  final VentasState state;
  final double goal;
  final List<_SalesDayPoint> dayPoints;
  final List<_SalesWeekdayStat> weekdayStats;
  final List<_TopProductStat> topProducts;
  final _SalesDayPoint? bestDay;
  final _SalesWeekdayStat? strongestWeekday;
  final double averageDailySales;
  final String Function(double value) money;
  final String Function(double value) compactMoney;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final progress = goal <= 0
        ? 0.0
        : (state.summary.totalProfit / goal).clamp(0.0, 1.0).toDouble();
    final hasData = state.sales.isNotEmpty || state.loading;
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
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Resumen de ventas',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.4,
                            color: const Color(0xFF0F172A),
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Mira con claridad tu avance comercial, el ritmo diario y los indicadores que importan para cerrar la quincena.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      scheme.primary.withValues(alpha: 0.16),
                      scheme.primary.withValues(alpha: 0.08),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: scheme.primary.withValues(alpha: 0.16),
                  ),
                ),
                child: Text(
                  '${(progress * 100).toStringAsFixed(0)}% de meta',
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
            SizedBox(
              height: 360,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.analytics_outlined,
                      size: 58,
                      color: scheme.outline,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Aun no hay datos suficientes',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Cuando empieces a registrar ventas, este panel mostrara tendencia, rendimiento y avance hacia la meta.',
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
                const spacing = 12.0;
                final cardsPerRow = constraints.maxWidth >= 1080
                    ? 3
                    : constraints.maxWidth >= 720
                    ? 2
                    : 1;
                final summaryCardWidth =
                    (constraints.maxWidth - spacing * (cardsPerRow - 1)) /
                    cardsPerRow;
                final stackAnalytics = constraints.maxWidth < 980;
                final analyticsHeight = stackAnalytics ? 660.0 : 470.0;

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Wrap(
                      spacing: spacing,
                      runSpacing: spacing,
                      children: [
                        SizedBox(
                          width: summaryCardWidth,
                          child: _DesktopSummaryCard(
                            title: 'Ventas registradas',
                            value: state.summary.totalSales.toString(),
                            subtitle: 'operaciones activas en el rango',
                            icon: Icons.receipt_long_outlined,
                          ),
                        ),
                        SizedBox(
                          width: summaryCardWidth,
                          child: _DesktopSummaryCard(
                            title: 'Total vendido',
                            value: money(state.summary.totalSold),
                            subtitle: 'facturacion acumulada',
                            icon: Icons.payments_outlined,
                          ),
                        ),
                        SizedBox(
                          width: summaryCardWidth,
                          child: _DesktopSummaryCard(
                            title: 'Puntos generados',
                            value: money(state.summary.totalProfit),
                            subtitle: 'avance que cuenta para tu meta',
                            icon: Icons.auto_graph_outlined,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: analyticsHeight,
                      child: stackAnalytics
                          ? Column(
                              children: [
                                Expanded(
                                  child: _DesktopTrendChartCard(
                                    points: dayPoints,
                                    bestDay: bestDay,
                                    averageDailySales: averageDailySales,
                                    money: money,
                                    compactMoney: compactMoney,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                SizedBox(
                                  height: 250,
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: _DesktopWeekdayPerformanceCard(
                                          stats: weekdayStats,
                                          strongestWeekday: strongestWeekday,
                                          compactMoney: compactMoney,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: _DesktopTopProductsCard(
                                          products: topProducts,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            )
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 7,
                                  child: _DesktopTrendChartCard(
                                    points: dayPoints,
                                    bestDay: bestDay,
                                    averageDailySales: averageDailySales,
                                    money: money,
                                    compactMoney: compactMoney,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  flex: 4,
                                  child: Column(
                                    children: [
                                      _DesktopWeekdayPerformanceCard(
                                        stats: weekdayStats,
                                        strongestWeekday: strongestWeekday,
                                        compactMoney: compactMoney,
                                      ),
                                      const SizedBox(height: 12),
                                      Expanded(
                                        child: _DesktopTopProductsCard(
                                          products: topProducts,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class _DesktopSummaryCard extends StatelessWidget {
  const _DesktopSummaryCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    this.compact = false,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 16 : 18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: compact ? 18 : 20, color: scheme.primary),
          SizedBox(height: compact ? 10 : 12),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: compact ? 30 : 36,
            child: Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  maxLines: 1,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
          ),
        ],
      ),
    );
  }
}

class _DesktopTrendChartCard extends StatelessWidget {
  const _DesktopTrendChartCard({
    required this.points,
    required this.bestDay,
    required this.averageDailySales,
    required this.money,
    required this.compactMoney,
  });

  final List<_SalesDayPoint> points;
  final _SalesDayPoint? bestDay;
  final double averageDailySales;
  final String Function(double value) money;
  final String Function(double value) compactMoney;

  @override
  Widget build(BuildContext context) {
    final maxValue = points.isEmpty
        ? 1.0
        : points.map((item) => item.total).reduce((a, b) => a > b ? a : b);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tendencia diaria',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'Asi se ha movido tu facturacion durante los ultimos dias del rango actual.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _DesktopInlineBadge(
                icon: Icons.show_chart_outlined,
                label: 'Promedio diario',
                value: compactMoney(averageDailySales),
              ),
              _DesktopInlineBadge(
                icon: Icons.trending_up_outlined,
                label: 'Pico del rango',
                value: bestDay == null
                    ? 'Sin datos'
                    : '${DateFormat('dd/MM').format(bestDay!.day)} · ${compactMoney(bestDay!.total)}',
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (points.isEmpty)
            SizedBox(
              height: 220,
              child: Center(
                child: Text(
                  'Todavia no hay suficientes datos para dibujar la tendencia.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            )
          else
            SizedBox(
              height: 220,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: points
                    .map(
                      (point) => Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(
                                compactMoney(point.total),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                              const SizedBox(height: 8),
                              Expanded(
                                child: Align(
                                  alignment: Alignment.bottomCenter,
                                  child: FractionallySizedBox(
                                    heightFactor: (point.total / maxValue)
                                        .clamp(0.08, 1.0)
                                        .toDouble(),
                                    child: Container(
                                      width: double.infinity,
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          begin: Alignment.bottomCenter,
                                          end: Alignment.topCenter,
                                          colors: [
                                            Color(0xFF1D4ED8),
                                            Color(0xFF60A5FA),
                                          ],
                                        ),
                                        borderRadius:
                                            const BorderRadius.vertical(
                                              top: Radius.circular(14),
                                              bottom: Radius.circular(14),
                                            ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                DateFormat('dd/MM').format(point.day),
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
        ],
      ),
    );
  }
}

class _DesktopInlineBadge extends StatelessWidget {
  const _DesktopInlineBadge({
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                value,
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DesktopWeekdayPerformanceCard extends StatelessWidget {
  const _DesktopWeekdayPerformanceCard({
    required this.stats,
    required this.strongestWeekday,
    required this.compactMoney,
  });

  final List<_SalesWeekdayStat> stats;
  final _SalesWeekdayStat? strongestWeekday;
  final String Function(double value) compactMoney;

  @override
  Widget build(BuildContext context) {
    final maxTotal = stats.fold<double>(0, (max, item) {
      if (item.total > max) return item.total;
      return max;
    });

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Dias con mejor salida',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            strongestWeekday == null
                ? 'Todavia no hay un patron claro de ventas.'
                : 'Tu dia mas fuerte ahora mismo es ${strongestWeekday!.label} con ${compactMoney(strongestWeekday!.total)} vendidos.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(height: 1.35),
          ),
          const SizedBox(height: 14),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: stats
                .map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 34,
                          child: Text(
                            item.label,
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              minHeight: 10,
                              value: maxTotal <= 0
                                  ? 0
                                  : (item.total / maxTotal)
                                        .clamp(0.0, 1.0)
                                        .toDouble(),
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.surface,
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                Color(0xFF1D4ED8),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 78,
                          child: Text(
                            compactMoney(item.total),
                            textAlign: TextAlign.right,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ),
    );
  }
}

class _DesktopTopProductsCard extends StatelessWidget {
  const _DesktopTopProductsCard({required this.products});

  final List<_TopProductStat> products;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Productos mas movidos',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          if (products.isEmpty)
            Text(
              'Sin movimientos suficientes por producto.',
              style: Theme.of(context).textTheme.bodyMedium,
            )
          else
            ...products.map(
              (product) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        product.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'x${product.quantity.toStringAsFixed(product.quantity % 1 == 0 ? 0 : 2)}',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SalesWeekdayStat {
  const _SalesWeekdayStat({
    required this.weekday,
    required this.label,
    required this.total,
  });

  final int weekday;
  final String label;
  final double total;
}

class _SalesDayPoint {
  const _SalesDayPoint({required this.day, required this.total});

  final DateTime day;
  final double total;
}

class _TopProductStat {
  const _TopProductStat({required this.name, required this.quantity});

  final String name;
  final double quantity;
}
