import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/client_model.dart';
import '../../../core/models/product_model.dart';
import '../application/clients_controller.dart';
import '../application/sales_controller.dart';

class SaleBuilderView extends ConsumerStatefulWidget {
  const SaleBuilderView({super.key});

  @override
  ConsumerState<SaleBuilderView> createState() => _SaleBuilderViewState();
}

class _SaleBuilderViewState extends ConsumerState<SaleBuilderView> with AutomaticKeepAliveClientMixin {
  final TextEditingController _noteCtrl = TextEditingController();
  String _productSearch = '';

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final builder = ref.watch(salesBuilderProvider);
    final builderCtrl = ref.watch(salesBuilderProvider.notifier);
    final clientsCtrl = ref.watch(clientsControllerProvider.notifier);

    _noteCtrl.value = _noteCtrl.value.copyWith(text: builder.note, selection: TextSelection.collapsed(offset: builder.note.length));

    return RefreshIndicator(
      onRefresh: () async {
        try {
          await builderCtrl.refresh();
          await ref.read(clientsControllerProvider.notifier).load();
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al refrescar: ${e is Exception ? e.toString() : 'Error desconocido'}')));
          }
        }
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: _ClientSelector(
                  clients: builder.clients,
                  selected: builder.selectedClient,
                  onSelect: builderCtrl.selectClient,
                  onCreate: (c) async {
                    final created = await clientsCtrl.create(
                      nombre: c.nombre,
                      telefono: c.telefono,
                      email: c.email,
                      direccion: c.direccion,
                      notas: c.notas,
                    );
                    builderCtrl.selectClient(created);
                  },
                ),
              ),
              const SizedBox(width: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: saleStatusDraft, label: Text('Borrador')),
                  ButtonSegment(value: saleStatusConfirmed, label: Text('Confirmar')),
                ],
                selected: {builder.status},
                onSelectionChanged: (v) => builderCtrl.setStatus(v.first),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _noteCtrl,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Nota (opcional)', border: OutlineInputBorder()),
            onChanged: builderCtrl.updateNote,
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Items (${builder.items.length})', style: Theme.of(context).textTheme.titleMedium),
              FilledButton.icon(
                onPressed: builder.products.isEmpty ? null : () => _openProductPicker(context, builder.products, builderCtrl.addItem),
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('Agregar producto'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (builder.items.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 12),
                    const Expanded(child: Text('Añade productos con precio y cantidad para crear el ticket.')),
                  ],
                ),
              ),
            )
          else
            ...builder.items.map((i) => Card(
                  child: ListTile(
                    title: Text(i.product.nombre),
                    subtitle: Text('Cant: ${i.qty} · Precio: ${i.price.toStringAsFixed(2)}'),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('Total ${i.lineTotal.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        Text('Utilidad ${i.lineProfit.toStringAsFixed(2)}', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                      ],
                    ),
                    onTap: () => _editItem(context, i, builderCtrl.updateItem),
                    onLongPress: () => builderCtrl.removeItem(i.id),
                  ),
                )),
          const SizedBox(height: 16),
          _TotalsCard(
            subtotal: builder.subtotal,
            totalCost: builder.totalCost,
            profit: builder.profit,
            commission: builder.commission,
          ),
          if (builder.error != null) ...[
            const SizedBox(height: 8),
            Text(builder.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: builder.saving ? null : () async {
                    try {
                      await builderCtrl.save(confirm: false);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Borrador guardado')));
                      }
                    } catch (_) {}
                  },
                  child: builder.saving ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Guardar borrador'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: builder.saving ? null : () async {
                    try {
                      await builderCtrl.save(confirm: true);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Venta confirmada')));
                      }
                    } catch (_) {}
                  },
                  child: builder.saving ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Confirmar venta'),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;

  Future<void> _openProductPicker(BuildContext context, List<ProductModel> products, void Function(ProductModel, {int qty, double? price}) onAdd) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final controller = TextEditingController(text: _productSearch);
        return StatefulBuilder(builder: (context, setState) {
          final filtered = products.where((p) => p.nombre.toLowerCase().contains(_productSearch.toLowerCase())).toList();
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    controller: controller,
                    decoration: const InputDecoration(labelText: 'Buscar producto', prefixIcon: Icon(Icons.search)),
                    onChanged: (v) => setState(() => _productSearch = v),
                  ),
                ),
                SizedBox(
                  height: 320,
                  child: ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, i) {
                      final p = filtered[i];
                      return ListTile(
                        title: Text(p.nombre),
                        subtitle: Text('Precio ${p.precio.toStringAsFixed(2)} · Costo ${p.costo.toStringAsFixed(2)}'),
                        onTap: () async {
                          final result = await _askQtyPrice(context, p);
                          if (result != null) {
                            onAdd(p, qty: result.$1, price: result.$2);
                            if (mounted) Navigator.pop(context);
                          }
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        });
      },
    );
  }

  Future<(int, double)?> _askQtyPrice(BuildContext context, ProductModel product) async {
    final qtyCtrl = TextEditingController(text: '1');
    final priceCtrl = TextEditingController(text: product.precio.toStringAsFixed(2));
    final result = await showDialog<(int, double)>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Agregar ${product.nombre}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: qtyCtrl,
                decoration: const InputDecoration(labelText: 'Cantidad'),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: priceCtrl,
                decoration: const InputDecoration(labelText: 'Precio vendido'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () {
                final qty = int.tryParse(qtyCtrl.text.trim());
                final price = double.tryParse(priceCtrl.text.trim());
                if (qty == null || qty < 1 || price == null) return;
                Navigator.pop(context, (qty, price));
              },
              child: const Text('Agregar'),
            ),
          ],
        );
      },
    );
    return result;
  }

  Future<void> _editItem(BuildContext context, SaleItemInput item, void Function(String, {int? qty, double? price}) onUpdate) async {
    final qtyCtrl = TextEditingController(text: item.qty.toString());
    final priceCtrl = TextEditingController(text: item.price.toStringAsFixed(2));
    final result = await showDialog<(int, double)?>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Editar ${item.product.nombre}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: qtyCtrl,
              decoration: const InputDecoration(labelText: 'Cantidad'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: priceCtrl,
              decoration: const InputDecoration(labelText: 'Precio vendido'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              final qty = int.tryParse(qtyCtrl.text.trim());
              final price = double.tryParse(priceCtrl.text.trim());
              if (qty == null || qty < 1 || price == null) return;
              Navigator.pop(context, (qty, price));
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (result != null) {
      onUpdate(item.id, qty: result.$1, price: result.$2);
    }
  }
}

class _TotalsCard extends StatelessWidget {
  final double subtotal;
  final double totalCost;
  final double profit;
  final double commission;

  const _TotalsCard({required this.subtotal, required this.totalCost, required this.profit, required this.commission});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Subtotal'),
                Text(subtotal.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Costo'),
                Text(totalCost.toStringAsFixed(2)),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Utilidad'),
                Text(profit.toStringAsFixed(2), style: TextStyle(color: Theme.of(context).colorScheme.primary)),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Comisión (10%)'),
                Text(commission.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ClientSelector extends StatelessWidget {
  final List<ClientModel> clients;
  final ClientModel? selected;
  final void Function(ClientModel?) onSelect;
  final Future<void> Function(ClientModel) onCreate;

  const _ClientSelector({required this.clients, required this.selected, required this.onSelect, required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Cliente', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: selected?.id,
                isExpanded: true,
                hint: const Text('Seleccionar (opcional)'),
                items: clients
                    .map(
                      (c) => DropdownMenuItem(
                        value: c.id,
                        child: Text(c.nombre),
                      ),
                    )
                    .toList(),
                onChanged: (id) {
                  if (id == null) return;
                  onSelect(clients.firstWhere((c) => c.id == id));
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Crear cliente rápido',
              onPressed: () => _quickCreate(context),
              icon: const Icon(Icons.person_add_alt_1),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _quickCreate(BuildContext context) async {
    final nombreCtrl = TextEditingController();
    final telefonoCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final direccionCtrl = TextEditingController();
    final notasCtrl = TextEditingController();

    final result = await showDialog<ClientModel?>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nuevo cliente'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nombreCtrl, decoration: const InputDecoration(labelText: 'Nombre')),
              TextField(controller: telefonoCtrl, decoration: const InputDecoration(labelText: 'Teléfono')),
              TextField(controller: emailCtrl, decoration: const InputDecoration(labelText: 'Email')),
              TextField(controller: direccionCtrl, decoration: const InputDecoration(labelText: 'Dirección')),
              TextField(controller: notasCtrl, decoration: const InputDecoration(labelText: 'Notas')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              if (nombreCtrl.text.trim().isEmpty || telefonoCtrl.text.trim().isEmpty) return;
              final client = ClientModel(
                id: '',
                nombre: nombreCtrl.text.trim(),
                telefono: telefonoCtrl.text.trim(),
                email: emailCtrl.text.trim().isEmpty ? null : emailCtrl.text.trim(),
                direccion: direccionCtrl.text.trim().isEmpty ? null : direccionCtrl.text.trim(),
                notas: notasCtrl.text.trim().isEmpty ? null : notasCtrl.text.trim(),
              );
              Navigator.pop(context, client);
            },
            child: const Text('Crear'),
          ),
        ],
      ),
    );

    if (result != null) {
      try {
        await onCreate(result);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al crear cliente: ${e is Exception ? e.toString() : 'Error desconocido'}')));
        }
      }
    }
  }
}
