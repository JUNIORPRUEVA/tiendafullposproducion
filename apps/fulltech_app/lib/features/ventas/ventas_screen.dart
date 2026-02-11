import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/sale_model.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/widgets/app_drawer.dart';

class VentasScreen extends ConsumerWidget {
  const VentasScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).user;
    final mockSales = List.generate(
      6,
      (i) => SaleModel(
        id: 'S-${1000 + i}',
        total: 15.5 + (i * 7.25),
        note: i.isEven ? 'Cliente frecuente' : null,
        createdAt: DateTime.now().subtract(Duration(hours: i * 3)),
        items: [
          SaleItemModel(
            id: 'I-$i-1',
            productName: 'Producto A',
            qty: 1,
            price: 10,
            lineTotal: 10,
          ),
          SaleItemModel(
            id: 'I-$i-2',
            productName: 'Producto B',
            qty: 1,
            price: 5.5,
            lineTotal: 5.5,
          ),
        ],
      ),
    );

    final totalDay = mockSales.fold<double>(0, (sum, s) => sum + s.total);

    return Scaffold(
      appBar: AppBar(title: const Text('Ventas')),
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
                    const Icon(Icons.point_of_sale, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Resumen del día',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Ventas: ${mockSales.length} · Total: \$${totalDay.toStringAsFixed(2)}',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.add),
                label: const Text('Nueva venta (placeholder)'),
              ),
            ),
            const SizedBox(height: 12),
            Text('Recientes', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                itemCount: mockSales.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final s = mockSales[i];
                  return Card(
                    child: ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.receipt_long),
                      ),
                      title: Text('Ticket ${s.id}'),
                      subtitle: Text(
                        '${s.createdAt.toLocal()}\nItems: ${s.items.length}${s.note != null ? ' · ${s.note}' : ''}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Text('\$${s.total.toStringAsFixed(2)}'),
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
