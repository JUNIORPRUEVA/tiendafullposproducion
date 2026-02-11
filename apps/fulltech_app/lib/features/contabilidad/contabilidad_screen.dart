import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/ledger_entry_model.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/widgets/app_drawer.dart';

class ContabilidadScreen extends ConsumerWidget {
  const ContabilidadScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).user;
    final entries = <LedgerEntryModel>[
      LedgerEntryModel(
        id: 'L-1',
        type: 'income',
        description: 'Venta mostrador',
        amount: 120.50,
        date: DateTime.now(),
      ),
      LedgerEntryModel(
        id: 'L-2',
        type: 'expense',
        description: 'Compra insumos',
        amount: 35.20,
        date: DateTime.now().subtract(const Duration(hours: 4)),
      ),
      LedgerEntryModel(
        id: 'L-3',
        type: 'income',
        description: 'Servicio técnico',
        amount: 80.00,
        date: DateTime.now().subtract(const Duration(days: 1)),
      ),
      LedgerEntryModel(
        id: 'L-4',
        type: 'expense',
        description: 'Transporte',
        amount: 12.75,
        date: DateTime.now().subtract(const Duration(days: 1, hours: 3)),
      ),
    ];

    final income = entries
        .where((e) => e.type == 'income')
        .fold<double>(0, (s, e) => s + e.amount);
    final expense = entries
        .where((e) => e.type == 'expense')
        .fold<double>(0, (s, e) => s + e.amount);
    final balance = income - expense;

    return Scaffold(
      appBar: AppBar(title: const Text('Contabilidad')),
      drawer: AppDrawer(currentUser: user),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.account_balance, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Resumen',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 6),
                          Text('Ingresos: \$${income.toStringAsFixed(2)}'),
                          Text('Gastos: \$${expense.toStringAsFixed(2)}'),
                          const Divider(height: 16),
                          Text(
                            'Balance: \$${balance.toStringAsFixed(2)}',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text('Movimientos', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                itemCount: entries.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final e = entries[i];
                  final isIncome = e.type == 'income';
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Icon(
                          isIncome ? Icons.trending_up : Icons.trending_down,
                        ),
                      ),
                      title: Text(e.description),
                      subtitle: Text(e.date.toLocal().toString()),
                      trailing: Text(
                        '${isIncome ? '+' : '-'}\$${e.amount.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: isIncome ? Colors.green : Colors.red,
                        ),
                      ),
                      onTap: () {},
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
