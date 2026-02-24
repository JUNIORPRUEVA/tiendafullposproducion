import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/models/product_model.dart';
import '../../core/widgets/app_drawer.dart';
import '../clientes/cliente_model.dart';
import 'data/ventas_repository.dart';
import 'sales_models.dart';

class RegistrarVentaScreen extends ConsumerStatefulWidget {
  const RegistrarVentaScreen({super.key});

  @override
  ConsumerState<RegistrarVentaScreen> createState() =>
      _RegistrarVentaScreenState();
}

class _RegistrarVentaScreenState extends ConsumerState<RegistrarVentaScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();
  final TextEditingController _clientSearchCtrl = TextEditingController();

  bool _loadingProducts = true;
  bool _saving = false;
  List<ProductModel> _products = const [];
  List<SaleDraftItem> _cart = [];
  int _visibleProducts = 24;

  ClienteModel? _selectedClient;
  List<ClienteModel> _clientOptions = const [];

  String _money(double value) =>
      NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$').format(value);

  List<ProductModel> get _filteredProducts {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return _products;
    return _products.where((p) => p.nombre.toLowerCase().contains(q)).toList();
  }

  double get _totalSold =>
      _cart.fold(0, (sum, item) => sum + item.subtotalSold);
  double get _totalCost =>
      _cart.fold(0, (sum, item) => sum + item.subtotalCost);
  double get _totalProfit => _totalSold - _totalCost;
  double get _commission => _totalProfit > 0 ? _totalProfit * 0.1 : 0;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _noteCtrl.dispose();
    _clientSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    setState(() => _loadingProducts = true);
    try {
      final products = await ref.read(ventasRepositoryProvider).fetchProducts();
      setState(() {
        _products = products;
        _loadingProducts = false;
      });
    } catch (e) {
      setState(() => _loadingProducts = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudieron cargar productos: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).user;
    final isWide = MediaQuery.of(context).size.width >= 1024;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Registrar Venta'),
        actions: [
          SizedBox(
            width: 320,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Buscar producto...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchCtrl.text.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() {});
                          },
                          icon: const Icon(Icons.close),
                        ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: FilledButton.icon(
              onPressed: _openExternalSaleModal,
              icon: const Icon(Icons.add_box_outlined),
              label: const Text('Vender fuera del inventario'),
            ),
          ),
        ],
      ),
      drawer: AppDrawer(currentUser: user),
      body: isWide
          ? Row(
              children: [
                Expanded(flex: 7, child: _buildProductGrid()),
                Container(width: 1, color: Theme.of(context).dividerColor),
                Expanded(flex: 3, child: _buildCartPanel()),
              ],
            )
          : Column(
              children: [
                Expanded(flex: 6, child: _buildProductGrid()),
                const Divider(height: 1),
                Expanded(flex: 4, child: _buildCartPanel()),
              ],
            ),
    );
  }

  Widget _buildProductGrid() {
    if (_loadingProducts) {
      return const Center(child: CircularProgressIndicator());
    }

    final filtered = _filteredProducts;
    final visible = filtered.take(_visibleProducts).toList();

    if (visible.isEmpty) {
      return const Center(child: Text('No hay productos para mostrar'));
    }

    return Column(
      children: [
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.9,
            ),
            itemCount: visible.length,
            itemBuilder: (context, index) {
              final p = visible[index];
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _addProduct(p),
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: p.fotoUrl == null || p.fotoUrl!.isEmpty
                            ? Container(
                                color: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                                child: const Center(
                                  child: Icon(Icons.inventory_2_outlined),
                                ),
                              )
                            : Image.network(
                                p.fotoUrl!,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    const Center(
                                      child: Icon(Icons.broken_image_outlined),
                                    ),
                              ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.nombre,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text('Precio: ${_money(p.precio)}'),
                            Text(
                              'Costo: ${_money(p.costo)}',
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        if (filtered.length > _visibleProducts)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: OutlinedButton.icon(
              onPressed: () => setState(() => _visibleProducts += 24),
              icon: const Icon(Icons.expand_more),
              label: const Text('Cargar más'),
            ),
          ),
      ],
    );
  }

  Widget _buildCartPanel() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Detalle de venta',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _cart.isEmpty
                ? const Center(child: Text('Agrega productos para iniciar'))
                : ListView.separated(
                    itemCount: _cart.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = _cart[index];
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      item.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Quitar item',
                                    onPressed: () =>
                                        setState(() => _cart.removeAt(index)),
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  Expanded(
                                    child: _NumberField(
                                      label: 'Cantidad',
                                      initialValue: item.qty,
                                      min: 0.001,
                                      onChanged: (v) => _updateItem(
                                        index,
                                        item.copyWith(qty: v),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _NumberField(
                                      label: 'Precio vendido',
                                      initialValue: item.priceSoldUnit,
                                      min: 0,
                                      onChanged: (v) => _updateItem(
                                        index,
                                        item.copyWith(priceSoldUnit: v),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Costo unitario: ${_money(item.costUnitSnapshot)}',
                              ),
                              Text('Subtotal: ${_money(item.subtotalSold)}'),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 8),
          _buildClientSelector(),
          const SizedBox(height: 8),
          TextField(
            controller: _noteCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Nota (opcional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          _totalsTile('Total vendido', _money(_totalSold)),
          _totalsTile('Total costo', _money(_totalCost)),
          _totalsTile('Total utilidad', _money(_totalProfit)),
          _totalsTile('Comisión (10%)', _money(_commission), highlight: true),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _saveSale,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(
                        'GUARDAR VENTA',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClientSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _clientSearchCtrl,
                onSubmitted: (_) => _searchClients(),
                decoration: InputDecoration(
                  labelText: _selectedClient == null
                      ? 'Buscar cliente'
                      : 'Cliente seleccionado: ${_selectedClient!.nombre}',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    onPressed: _searchClients,
                    icon: const Icon(Icons.search),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Nuevo cliente rápido',
              onPressed: _createQuickClient,
              icon: const Icon(Icons.person_add_alt_1),
            ),
            IconButton(
              tooltip: 'Quitar cliente',
              onPressed: _selectedClient == null
                  ? null
                  : () => setState(() => _selectedClient = null),
              icon: const Icon(Icons.clear),
            ),
          ],
        ),
        if (_clientOptions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 6),
            constraints: const BoxConstraints(maxHeight: 120),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _clientOptions.length,
              itemBuilder: (context, index) {
                final c = _clientOptions[index];
                return ListTile(
                  dense: true,
                  title: Text(c.nombre),
                  subtitle: Text(c.telefono),
                  onTap: () {
                    setState(() {
                      _selectedClient = c;
                      _clientOptions = const [];
                      _clientSearchCtrl.text = c.nombre;
                    });
                  },
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _totalsTile(String label, String value, {bool highlight = false}) {
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

  void _addProduct(ProductModel product) {
    final idx = _cart.indexWhere((item) => item.productId == product.id);
    if (idx >= 0) {
      final current = _cart[idx];
      _updateItem(idx, current.copyWith(qty: current.qty + 1));
      return;
    }

    setState(() {
      _cart = [
        ..._cart,
        SaleDraftItem(
          product: product,
          productId: product.id,
          name: product.nombre,
          imageUrl: product.fotoUrl,
          isExternal: false,
          qty: 1,
          priceSoldUnit: product.precio,
          costUnitSnapshot: product.costo,
        ),
      ];
    });
  }

  void _updateItem(int index, SaleDraftItem next) {
    setState(() {
      final list = [..._cart];
      list[index] = next;
      _cart = list;
    });
  }

  Future<void> _searchClients() async {
    try {
      final rows = await ref
          .read(ventasRepositoryProvider)
          .searchClients(_clientSearchCtrl.text);
      if (!mounted) return;
      setState(() => _clientOptions = rows);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error buscando clientes: $e')));
    }
  }

  Future<void> _createQuickClient() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Crear cliente rápido'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Nombre'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: phoneCtrl,
              decoration: const InputDecoration(labelText: 'Teléfono'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Crear'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      final created = await ref
          .read(ventasRepositoryProvider)
          .createQuickClient(nombre: nameCtrl.text, telefono: phoneCtrl.text);
      if (!mounted) return;
      setState(() {
        _selectedClient = created;
        _clientSearchCtrl.text = created.nombre;
        _clientOptions = const [];
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Cliente creado')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo crear cliente: $e')));
    }
  }

  Future<void> _openExternalSaleModal() async {
    final nameCtrl = TextEditingController();
    final qtyCtrl = TextEditingController(text: '1');
    final costCtrl = TextEditingController();
    final priceCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Vender fuera del inventario'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nombre producto/servicio',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: qtyCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Cantidad'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: costCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Costo unitario'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: priceCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Precio vendido unitario',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Agregar'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    final name = nameCtrl.text.trim();
    final qty = double.tryParse(qtyCtrl.text.trim()) ?? 0;
    final cost = double.tryParse(costCtrl.text.trim()) ?? -1;
    final price = double.tryParse(priceCtrl.text.trim()) ?? -1;

    if (name.isEmpty || qty <= 0 || cost < 0 || price < 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Completa datos válidos: nombre, qty > 0, costo >= 0, precio >= 0',
          ),
        ),
      );
      return;
    }

    setState(() {
      _cart = [
        ..._cart,
        SaleDraftItem(
          productId: null,
          name: name,
          imageUrl: null,
          isExternal: true,
          qty: qty,
          priceSoldUnit: price,
          costUnitSnapshot: cost,
        ),
      ];
    });
  }

  Future<void> _saveSale() async {
    if (_cart.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Agrega al menos un item')));
      return;
    }

    if (_cart.any(
      (item) =>
          item.qty <= 0 || item.priceSoldUnit < 0 || item.costUnitSnapshot < 0,
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Revisa: qty > 0 y montos no negativos')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await ref
          .read(ventasRepositoryProvider)
          .createSale(
            customerId: _selectedClient?.id,
            note: _noteCtrl.text,
            items: _cart,
          );

      if (!mounted) return;
      setState(() {
        _cart = [];
        _selectedClient = null;
        _clientOptions = const [];
        _noteCtrl.clear();
        _clientSearchCtrl.clear();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Venta guardada correctamente')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo guardar: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _NumberField extends StatefulWidget {
  final String label;
  final double initialValue;
  final double min;
  final ValueChanged<double> onChanged;

  const _NumberField({
    required this.label,
    required this.initialValue,
    required this.min,
    required this.onChanged,
  });

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initialValue.toStringAsFixed(2),
    );
  }

  @override
  void didUpdateWidget(covariant _NumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue) {
      _controller.text = widget.initialValue.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: widget.label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      onSubmitted: (value) {
        final parsed = double.tryParse(value.trim()) ?? widget.initialValue;
        final safe = parsed < widget.min ? widget.min : parsed;
        widget.onChanged(safe);
      },
    );
  }
}
