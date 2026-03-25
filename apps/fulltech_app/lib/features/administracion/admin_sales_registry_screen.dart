import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/models/user_model.dart';
import '../../core/routing/routes.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../features/user/data/users_repository.dart';
import '../../modules/ventas/data/ventas_repository.dart';
import '../../modules/ventas/sales_models.dart';

class AdminSalesRegistryScreen extends ConsumerStatefulWidget {
  const AdminSalesRegistryScreen({super.key});

  @override
  ConsumerState<AdminSalesRegistryScreen> createState() =>
      _AdminSalesRegistryScreenState();
}

class _AdminSalesRegistryScreenState
    extends ConsumerState<AdminSalesRegistryScreen> {
  bool _loading = false;
  String? _error;
  SalesSummaryModel _summary = SalesSummaryModel.empty();
  List<SaleModel> _items = const [];
  List<UserModel> _users = const [];
  String? _selectedUserId;
  DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  DateTime _to = DateTime.now();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final repo = ref.read(ventasRepositoryProvider);
      final from = DateTime(_from.year, _from.month, _from.day);
      final to = DateTime(_to.year, _to.month, _to.day);
      final selectedUserId = (_selectedUserId ?? '').trim();
      final results = await Future.wait<dynamic>([
        repo.listSales(
          from: from,
          to: to,
          userId: selectedUserId.isEmpty ? null : selectedUserId,
        ),
        repo.summary(
          from: from,
          to: to,
          userId: selectedUserId.isEmpty ? null : selectedUserId,
        ),
        ref.read(usersRepositoryProvider).getAllUsers(skipLoader: true),
      ]);
      if (!mounted) return;
      final sales = results[0] as List<SaleModel>;
      final summary = results[1] as SalesSummaryModel;
      final users = results[2] as List<UserModel>;

      final filteredSales = selectedUserId.isEmpty
          ? sales
          : sales
              .where((item) => item.userId.trim() == selectedUserId)
              .toList(growable: false);

      final filteredSummary = selectedUserId.isEmpty
          ? summary
          : SalesSummaryModel(
              totalSales: filteredSales.length,
              totalSold: filteredSales.fold<double>(
                0,
                (sum, item) => sum + item.totalSold,
              ),
              totalCost: filteredSales.fold<double>(
                0,
                (sum, item) => sum + item.totalCost,
              ),
              totalProfit: filteredSales.fold<double>(
                0,
                (sum, item) => sum + item.totalProfit,
              ),
              totalCommission: filteredSales.fold<double>(
                0,
                (sum, item) => sum + item.commissionAmount,
              ),
            );

      setState(() {
        _items = filteredSales;
        _summary = filteredSummary;
        _users = users;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _money(double value) =>
      NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$').format(value);

  String _dateOnlyText(DateTime value) {
    return DateFormat('dd/MM/yyyy', 'es_DO').format(value);
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: _from, end: _to),
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 3)),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _from = DateTime(picked.start.year, picked.start.month, picked.start.day);
      _to = DateTime(picked.end.year, picked.end.month, picked.end.day);
    });
    await _load();
  }

  void _openSaleDetail(SaleModel sale) {
    final dateText = sale.saleDate == null
        ? 'Sin fecha'
        : DateFormat('dd/MM/yyyy h:mm a', 'es_DO').format(sale.saleDate!.toLocal());

    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Detalle de venta'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('ID: ${sale.id}'),
                  Text('Usuario: ${sale.userId}'),
                  Text(
                    'Cliente: ${sale.customerName?.trim().isNotEmpty == true ? sale.customerName : 'No especificado'}',
                  ),
                  Text('Fecha: $dateText'),
                  if ((sale.note ?? '').trim().isNotEmpty) Text('Nota: ${sale.note}'),
                  const Divider(height: 18),
                  ...sale.items.map(
                    (item) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${item.productNameSnapshot} x${item.qty.toStringAsFixed(item.qty % 1 == 0 ? 0 : 2)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(_money(item.subtotalSold)),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 18),
                  Text('Total vendido: ${_money(sale.totalSold)}'),
                  Text('Total costo: ${_money(sale.totalCost)}'),
                  Text('Utilidad: ${_money(sale.totalProfit)}'),
                  Text('Comisión: ${_money(sale.commissionAmount)}'),
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

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(authStateProvider).user;

    return Scaffold(
      drawer: buildAdaptiveDrawer(context, currentUser: currentUser),
      appBar: CustomAppBar(
        title: 'Registro global de ventas',
        fallbackRoute: Routes.administracion,
        showLogo: false,
        showDepartmentLabel: false,
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
            child: DropdownButtonFormField<String?>(
              value: _selectedUserId,
              decoration: const InputDecoration(
                labelText: 'Filtrar por usuario',
                prefixIcon: Icon(Icons.person_search_outlined),
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Todos los usuarios'),
                ),
                ..._users.map(
                  (user) => DropdownMenuItem<String?>(
                    value: user.id,
                    child: Text(
                      user.nombreCompleto.trim().isEmpty
                          ? user.email
                          : user.nombreCompleto,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
              onChanged: (value) {
                setState(() => _selectedUserId = value);
                unawaited(_load());
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _pickDateRange,
                icon: const Icon(Icons.date_range_rounded),
                label: Text(
                  'Rango: ${_dateOnlyText(_from)} - ${_dateOnlyText(_to)}',
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: _SummaryChip(
                    label: 'Ventas',
                    value: _summary.totalSales.toString(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SummaryChip(
                    label: 'Total vendido',
                    value: _money(_summary.totalSold),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SummaryChip(
                    label: 'Utilidad',
                    value: _money(_summary.totalProfit),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  )
                : _items.isEmpty
                    ? const Center(
                        child: Text('No hay ventas globales para mostrar.'),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                          itemCount: _items.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final sale = _items[index];
                            final dateText = sale.saleDate == null
                                ? 'Sin fecha'
                                : DateFormat(
                                    'dd/MM/yyyy h:mm a',
                                    'es_DO',
                                  ).format(sale.saleDate!.toLocal());

                            return Card(
                              child: ListTile(
                                onTap: () => _openSaleDetail(sale),
                                title: Text(
                                  sale.customerName?.trim().isNotEmpty == true
                                      ? sale.customerName!
                                      : 'Cliente no especificado',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  '$dateText · Usuario: ${sale.userId}',
                                ),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      _money(sale.totalSold),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    Text(
                                      'Utilidad: ${_money(sale.totalProfit)}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
