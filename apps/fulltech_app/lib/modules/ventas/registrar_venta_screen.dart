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

  bool _loadingProducts = true;
  bool _saving = false;
  List<ProductModel> _products = const [];
  List<SaleDraftItem> _cart = [];
  int _visibleProducts = 24;

  ClienteModel? _selectedClient;

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
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isWide = screenWidth >= 1024;
    final isCompact = screenWidth < 900;
    final showInlineTotals = screenWidth >= 700 && screenHeight >= 780;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Registrar Venta'),
        actions: isWide
            ? [
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
              ]
            : [
                IconButton(
                  tooltip: 'Vender fuera del inventario',
                  onPressed: _openExternalSaleModal,
                  icon: const Icon(Icons.add_box_outlined),
                ),
              ],
      ),
      drawer: AppDrawer(currentUser: user),
      body: Column(
        children: [
          if (!isWide)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
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
                  ),
                  isDense: true,
                ),
              ),
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                const dividerHeight = 1.0;
                final available = constraints.maxHeight;
                final contentHeight = (available - dividerHeight).clamp(
                  160.0,
                  available,
                );

                final panelHeight = contentHeight * 0.50;
                final productHeight = contentHeight - panelHeight;

                return Column(
                  children: [
                    SizedBox(
                      height: productHeight,
                      child: _buildProductGrid(isCompact: isCompact),
                    ),
                    Container(
                      height: dividerHeight,
                      color: Theme.of(context).dividerColor,
                    ),
                    SizedBox(
                      height: panelHeight,
                      child: _buildCartPanel(
                        isCompact: isCompact,
                        showInlineTotals: showInlineTotals,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductGrid({required bool isCompact}) {
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
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Productos disponibles',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Chip(
                visualDensity: VisualDensity.compact,
                label: Text('$filtered.length'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final crossAxisCount = width < 360
                  ? 1
                  : width < 520
                  ? 2
                  : width < 900
                  ? 3
                  : 4;
              final aspectRatio = isCompact ? 0.78 : 0.9;

              return GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: aspectRatio,
                ),
                itemCount: visible.length,
                itemBuilder: (context, index) {
                  final p = visible[index];
                  return InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _addProduct(p),
                    child: Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: Theme.of(
                            context,
                          ).dividerColor.withValues(alpha: 0.25),
                        ),
                      ),
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
                                    errorBuilder:
                                        (context, error, stackTrace) =>
                                            const Center(
                                              child: Icon(
                                                Icons.broken_image_outlined,
                                              ),
                                            ),
                                  ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
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

  Widget _buildCartPanel({
    required bool isCompact,
    required bool showInlineTotals,
  }) {
    return Padding(
      padding: EdgeInsets.all(isCompact ? 10 : 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.25),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            isCompact ? 10 : 12,
            isCompact ? 10 : 12,
            isCompact ? 10 : 12,
            isCompact ? 8 : 10,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final availableHeight = constraints.maxHeight;
              final compactVertical = availableHeight < 320;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Resumen de venta',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (!showInlineTotals)
                        TextButton.icon(
                          onPressed: _showTotalsDialog,
                          icon: const Icon(Icons.receipt_long_outlined),
                          label: const Text('Resumen'),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            minimumSize: const Size(0, 34),
                          ),
                        ),
                    ],
                  ),
                  if (_cart.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '${_cart.length} item(s)',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  SizedBox(height: compactVertical ? 6 : 10),
                  Expanded(
                    flex: 5,
                    child: _cart.isEmpty
                        ? const Center(
                            child: Text('Agrega productos para iniciar'),
                          )
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                            onPressed: () => setState(
                                              () => _cart.removeAt(index),
                                            ),
                                            icon: const Icon(
                                              Icons.delete_outline,
                                            ),
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
                                      Text(
                                        'Subtotal: ${_money(item.subtotalSold)}',
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  SizedBox(height: compactVertical ? 6 : 8),
                  Expanded(
                    flex: showInlineTotals ? 4 : 3,
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.tonalIcon(
                                  onPressed: _openClientPickerDialog,
                                  icon: const Icon(
                                    Icons.person_search_outlined,
                                  ),
                                  label: Text(
                                    _selectedClient == null
                                        ? 'Cliente'
                                        : _selectedClient!.nombre,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _openNoteDialog,
                                  icon: const Icon(
                                    Icons.sticky_note_2_outlined,
                                  ),
                                  label: Text(
                                    _noteCtrl.text.trim().isEmpty
                                        ? 'Nota'
                                        : 'Editar nota',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (_noteCtrl.text.trim().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                _noteCtrl.text.trim(),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          if (showInlineTotals) ...[
                            const SizedBox(height: 10),
                            _totalsTile('Total vendido', _money(_totalSold)),
                            _totalsTile('Total costo', _money(_totalCost)),
                            _totalsTile('Total utilidad', _money(_totalProfit)),
                            _totalsTile(
                              'Comisión (10%)',
                              _money(_commission),
                              highlight: true,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: compactVertical ? 4 : 6),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _saving ? null : _saveSale,
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: compactVertical ? 10 : 12,
                        ),
                        child: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'GUARDAR VENTA',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _openNoteDialog() async {
    final noteEditor = TextEditingController(text: _noteCtrl.text);

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nota de la venta'),
        content: TextField(
          controller: noteEditor,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Escribe una nota (opcional)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (saved == true && mounted) {
      setState(() {
        _noteCtrl.text = noteEditor.text.trim();
      });
    }
  }

  Future<void> _openClientPickerDialog() async {
    final searchCtrl = TextEditingController();
    var rows = <ClienteModel>[];
    bool loading = false;

    Future<void> runSearch(StateSetter setDialogState) async {
      setDialogState(() => loading = true);
      try {
        final result = await ref
            .read(ventasRepositoryProvider)
            .searchClients(searchCtrl.text);
        if (!mounted) return;
        setDialogState(() {
          rows = result;
          loading = false;
        });
      } catch (_) {
        if (!mounted) return;
        setDialogState(() => loading = false);
      }
    }

    final selected = await showDialog<ClienteModel>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Seleccionar cliente'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: searchCtrl,
                    onSubmitted: (_) => runSearch(setDialogState),
                    decoration: InputDecoration(
                      hintText: 'Buscar por nombre o teléfono',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        onPressed: () => runSearch(setDialogState),
                        icon: const Icon(Icons.search),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (loading)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(),
                    )
                  else
                    SizedBox(
                      height: 220,
                      child: rows.isEmpty
                          ? const Center(
                              child: Text(
                                'Busca un cliente para seleccionarlo',
                              ),
                            )
                          : ListView.separated(
                              itemCount: rows.length,
                              separatorBuilder: (context, index) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final c = rows[index];
                                return ListTile(
                                  dense: true,
                                  title: Text(c.nombre),
                                  subtitle: Text(c.telefono),
                                  onTap: () => Navigator.of(context).pop(c),
                                );
                              },
                            ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancelar'),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  _createQuickClient();
                },
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Agregar nuevo cliente'),
              ),
            ],
          );
        },
      ),
    );

    if (selected != null && mounted) {
      setState(() => _selectedClient = selected);
    }
  }

  Future<void> _showTotalsDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Resumen de totales'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _totalsTile('Total vendido', _money(_totalSold)),
            _totalsTile('Total costo', _money(_totalCost)),
            _totalsTile('Total utilidad', _money(_totalProfit)),
            _totalsTile('Comisión (10%)', _money(_commission), highlight: true),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
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
        _noteCtrl.clear();
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
