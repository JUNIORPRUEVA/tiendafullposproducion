import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';
import 'data/nomina_repository.dart';
import 'nomina_models.dart';

class MisPagosScreen extends ConsumerStatefulWidget {
  const MisPagosScreen({super.key});

  @override
  ConsumerState<MisPagosScreen> createState() => _MisPagosScreenState();
}

class _MisPagosScreenState extends ConsumerState<MisPagosScreen> {
  bool _loading = true;
  String? _error;
  List<PayrollHistoryItem> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await ref
          .read(nominaRepositoryProvider)
          .listMyPayrollHistory();
      if (!mounted) return;
      setState(() {
        _items = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo cargar Mis Pagos: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider);
    final currentUser = auth.user;

    final totalHistorico = _items.fold<double>(
      0,
      (sum, item) => sum + item.netTotal,
    );
    final thisYear = DateTime.now().year;
    final totalAnio = _items
        .where((item) => item.periodEnd.year == thisYear)
        .fold<double>(0, (sum, item) => sum + item.netTotal);
    final proximoPago = _items
        .where(
          (item) =>
              item.periodStatus.toUpperCase() == 'DRAFT' ||
              item.periodStatus.toUpperCase() == 'CLOSED',
        )
        .fold<double>(0, (sum, item) => sum + item.netTotal);

    return Scaffold(
      appBar: CustomAppBar(
        title: 'Mis Pagos',
        showLogo: false,
        actions: [
          IconButton(
            tooltip: 'Recargar',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      drawer: AppDrawer(currentUser: currentUser),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _AccountSummaryCard(
                    totalHistorico: totalHistorico,
                    totalAnio: totalAnio,
                    proximoPago: proximoPago,
                  ),
                  const SizedBox(height: 12),
                  if (_error != null)
                    Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    'Historial de quincenas',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (_items.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Icon(
                              Icons.receipt_long_outlined,
                              size: 36,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Aún no tienes pagos registrados',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ..._items.map((item) => _PayrollHistoryCard(item: item)),
                ],
              ),
      ),
    );
  }
}

class _AccountSummaryCard extends StatelessWidget {
  const _AccountSummaryCard({
    required this.totalHistorico,
    required this.totalAnio,
    required this.proximoPago,
  });

  final double totalHistorico;
  final double totalAnio;
  final double proximoPago;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Estado de cuenta',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 10),
            _SummaryLine(
              label: 'Total pagado histórico',
              value: totalHistorico,
            ),
            _SummaryLine(label: 'Total pagado este año', value: totalAnio),
            _SummaryLine(label: 'Próximo pago estimado', value: proximoPago),
          ],
        ),
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    final format = NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            format.format(value),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _PayrollHistoryCard extends StatelessWidget {
  const _PayrollHistoryCard({required this.item});

  final PayrollHistoryItem item;

  @override
  Widget build(BuildContext context) {
    final range =
        '${DateFormat('dd/MM/yyyy').format(item.periodStart)} - ${DateFormat('dd/MM/yyyy').format(item.periodEnd)}';
    final net = NumberFormat.currency(
      locale: 'es_DO',
      symbol: 'RD\$',
    ).format(item.netTotal);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        title: Text(
          item.periodTitle,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(range),
        trailing: Chip(
          label: Text(item.isPaid ? 'Pagado' : 'Pendiente'),
          backgroundColor: item.isPaid
              ? Colors.green.withValues(alpha: 0.15)
              : Colors.orange.withValues(alpha: 0.15),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          _Line(label: 'Neto quincena', value: net, bold: true),
          _Line(label: 'Salario base', value: item.baseSalary),
          _Line(label: 'Comisión', value: item.commissionFromSales),
          _Line(
            label: 'Extras',
            value: item.overtimeAmount + item.bonusesAmount,
          ),
          _Line(label: 'Beneficios', value: item.benefitsAmount),
          _Line(label: 'Deducciones', value: item.deductionsAmount),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value, this.bold = false});

  final String label;
  final Object value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final text = value is num
        ? NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$').format(value)
        : value.toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            text,
            style: TextStyle(
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
