import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/company/company_settings_repository.dart';
import '../../core/errors/api_exception.dart';
import '../../core/models/product_model.dart';
import '../../core/routing/routes.dart';
import '../../core/widgets/app_drawer.dart';
import '../clientes/cliente_model.dart';
import '../ventas/data/ventas_repository.dart';
import 'cotizacion_models.dart';
import 'data/cotizaciones_repository.dart';
import 'utils/cotizacion_pdf_service.dart';

class CotizacionesScreen extends ConsumerStatefulWidget {
  const CotizacionesScreen({super.key});

  @override
  ConsumerState<CotizacionesScreen> createState() => _CotizacionesScreenState();
}

class _CotizacionesScreenState extends ConsumerState<CotizacionesScreen> {
  final TextEditingController _searchCtrl = TextEditingController();

  final List<CotizacionItem> _items = [];
  List<ProductModel> _productos = const [];

  bool _loadingProducts = true;
  String? _error;
  String? _selectedCategory;

  String? _selectedClientId;
  String _selectedClientName = 'Sin cliente';
  String? _selectedClientPhone;
  String _note = '';

  bool _includeItbis = false;
  static const double _itbisRate = 0.18;

  String? _editingId;
  DateTime? _editingCreatedAt;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    setState(() {
      _loadingProducts = true;
      _error = null;
    });

    try {
      final rows = await ref.read(ventasRepositoryProvider).fetchProducts();
      if (!mounted) return;
      setState(() {
        _productos = rows;
        _loadingProducts = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingProducts = false;
        _error = 'No se pudieron cargar productos: $e';
      });
    }
  }

  List<String> get _categories {
    final values = _productos
        .map((product) => product.categoriaLabel.trim())
        .where((label) => label.isNotEmpty)
        .toSet()
        .toList();
    values.sort((left, right) => left.compareTo(right));
    return values;
  }

  List<ProductModel> get _visibleProducts {
    final query = _searchCtrl.text.trim().toLowerCase();
    return _productos.where((product) {
      if (_selectedCategory != null &&
          product.categoriaLabel != _selectedCategory) {
        return false;
      }
      if (query.isEmpty) return true;
      return product.nombre.toLowerCase().contains(query) ||
          product.categoriaLabel.toLowerCase().contains(query);
    }).toList();
  }

  double get _subtotal => _items.fold(0, (sum, item) => sum + item.total);
  double get _itbisAmount => _includeItbis ? (_subtotal * _itbisRate) : 0;
  double get _total => _subtotal + _itbisAmount;

  String _money(double value) =>
      NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$').format(value);

  String _newId() => DateTime.now().microsecondsSinceEpoch.toString();

  void _addProduct(ProductModel product) {
    final index = _items.indexWhere((item) => item.productId == product.id);
    setState(() {
      if (index >= 0) {
        final current = _items[index];
        _items[index] = current.copyWith(qty: current.qty + 1);
      } else {
        _items.add(
          CotizacionItem(
            productId: product.id,
            nombre: product.nombre,
            imageUrl: product.fotoUrl,
            unitPrice: product.precio,
            qty: 1,
          ),
        );
      }
    });
  }

  void _setQty(int index, double qty) {
    if (qty <= 0) {
      setState(() => _items.removeAt(index));
      return;
    }
    setState(() => _items[index] = _items[index].copyWith(qty: qty));
  }

  void _setUnitPrice(int index, double price) {
    if (price < 0) return;
    setState(() => _items[index] = _items[index].copyWith(unitPrice: price));
  }

  Future<void> _pickCategory() async {
    final selected = await showModalBottomSheet<String?>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final categories = _categories;
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              RadioListTile<String?>(
                title: const Text('Todas las categorías'),
                value: null,
                groupValue: _selectedCategory,
                onChanged: (value) => Navigator.pop(context, value),
              ),
              ...categories.map(
                (category) => RadioListTile<String?>(
                  title: Text(category),
                  value: category,
                  groupValue: _selectedCategory,
                  onChanged: (value) => Navigator.pop(context, value),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted) return;
    if (selected == _selectedCategory) return;
    setState(() => _selectedCategory = selected);
  }

  Future<void> _openNoteDialog() async {
    final controller = TextEditingController(text: _note);
    final nextNote = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nota de cotización'),
        content: TextField(
          controller: controller,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Escribe una nota para esta cotización',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (nextNote == null || !mounted) return;
    setState(() => _note = nextNote);
  }

  Future<void> _openClientDialog() async {
    final repo = ref.read(ventasRepositoryProvider);
    final searchCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();

    List<ClienteModel> clients = const [];
    bool loading = true;
    bool creating = false;
    String? error;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          Future<void> loadClients() async {
            setStateDialog(() {
              loading = true;
              error = null;
            });
            try {
              clients = await repo.searchClients(searchCtrl.text.trim());
              if (!context.mounted) return;
              setStateDialog(() => loading = false);
            } catch (e) {
              if (!context.mounted) return;
              setStateDialog(() {
                loading = false;
                error = '$e';
              });
            }
          }

          if (loading && clients.isEmpty && error == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) => loadClients());
          }

          return AlertDialog(
            title: const Text('Cliente'),
            content: SizedBox(
              width: 430,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!creating) ...[
                    TextField(
                      controller: searchCtrl,
                      decoration: InputDecoration(
                        hintText: 'Buscar cliente',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: IconButton(
                          onPressed: loadClients,
                          icon: const Icon(Icons.filter_alt_outlined),
                        ),
                        isDense: true,
                      ),
                      onSubmitted: (_) => loadClients(),
                    ),
                    const SizedBox(height: 10),
                    if (loading)
                      const LinearProgressIndicator()
                    else if (error != null)
                      Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      )
                    else
                      SizedBox(
                        height: 280,
                        child: clients.isEmpty
                            ? const Center(
                                child: Text('No hay clientes, crea uno nuevo'),
                              )
                            : ListView.separated(
                                itemCount: clients.length,
                                separatorBuilder: (context, index) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final client = clients[index];
                                  return ListTile(
                                    dense: true,
                                    title: Text(client.nombre),
                                    subtitle: Text(
                                      client.telefono,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    onTap: () {
                                      setState(() {
                                        _selectedClientId = client.id;
                                        _selectedClientName = client.nombre;
                                        _selectedClientPhone = client.telefono;
                                      });
                                      Navigator.pop(context);
                                    },
                                  );
                                },
                              ),
                      ),
                  ] else ...[
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nombre',
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Teléfono',
                        isDense: true,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cerrar'),
              ),
              if (!creating)
                OutlinedButton.icon(
                  onPressed: () => setStateDialog(() => creating = true),
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: const Text('Nuevo'),
                )
              else
                OutlinedButton.icon(
                  onPressed: () => setStateDialog(() => creating = false),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Lista'),
                ),
              if (creating)
                FilledButton(
                  onPressed: () async {
                    final name = nameCtrl.text.trim();
                    final phone = phoneCtrl.text.trim();
                    if (name.isEmpty || phone.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Nombre y teléfono son obligatorios'),
                        ),
                      );
                      return;
                    }
                    try {
                      final created = await repo.createQuickClient(
                        nombre: name,
                        telefono: phone,
                      );
                      if (!context.mounted) return;
                      setState(() {
                        _selectedClientId = created.id;
                        _selectedClientName = created.nombre;
                        _selectedClientPhone = created.telefono;
                      });
                      Navigator.pop(context);
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('No se pudo crear: $e')),
                      );
                    }
                  },
                  child: const Text('Guardar cliente'),
                ),
            ],
          );
        },
      ),
    );
  }

  CotizacionModel _buildDraftCotizacion() {
    return CotizacionModel(
      id: _editingId ?? _newId(),
      createdAt: _editingCreatedAt ?? DateTime.now(),
      customerId: _selectedClientId,
      customerName: _selectedClientName,
      customerPhone: _selectedClientPhone,
      note: _note,
      includeItbis: _includeItbis,
      itbisRate: _itbisRate,
      items: [..._items],
    );
  }

  Future<void> _openPdfPreview() async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agrega productos para generar PDF')),
      );
      return;
    }

    final cotizacion = _buildDraftCotizacion();
    final company = await ref
        .read(companySettingsRepositoryProvider)
        .getSettings();
    final bytes = await buildCotizacionPdf(
      cotizacion: cotizacion,
      company: company,
    );

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) {
        final media = MediaQuery.sizeOf(context);
        final compact = media.width < 560;
        return Dialog(
          insetPadding: EdgeInsets.all(compact ? 8 : 16),
          child: SizedBox(
            width: compact ? media.width - 16 : 900,
            height: compact ? media.height * 0.92 : 760,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 8, 6),
                  child: Row(
                    children: [
                      const Icon(Icons.picture_as_pdf_outlined),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'PDF de cotización',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => shareCotizacionPdf(
                          bytes: bytes,
                          cotizacion: cotizacion,
                        ),
                        icon: const Icon(Icons.download_outlined),
                        label: const Text('Descargar'),
                      ),
                      IconButton(
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
                    build: (_) async => bytes,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openHistory() async {
    final payload = await context.push<CotizacionEditorPayload>(
      Routes.cotizacionesHistorial,
    );

    if (payload == null || !mounted) return;

    setState(() {
      _items
        ..clear()
        ..addAll(payload.source.items.map((item) => item.copyWith()));
      _selectedClientId = payload.source.customerId;
      _selectedClientName = payload.source.customerName;
      _selectedClientPhone = payload.source.customerPhone;
      _note = payload.source.note;
      _includeItbis = payload.source.includeItbis;
      _editingId = payload.duplicate ? null : payload.source.id;
      _editingCreatedAt = payload.duplicate ? null : payload.source.createdAt;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          payload.duplicate
              ? 'Cotización duplicada en editor'
              : 'Cotización cargada para editar',
        ),
      ),
    );
  }

  Future<void> _finalizeCotizacion() async {
    if (_selectedClientId == null || _selectedClientName == 'Sin cliente') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona o crea un cliente primero')),
      );
      return;
    }

    if ((_selectedClientPhone ?? '').trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El cliente debe tener teléfono')),
      );
      return;
    }

    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agrega al menos un producto al ticket')),
      );
      return;
    }

    final wasEditing = (_editingId ?? '').trim().isNotEmpty;
    final cotizacion = _buildDraftCotizacion();
    try {
      if ((_editingId ?? '').trim().isEmpty) {
        await ref.read(cotizacionesRepositoryProvider).create(cotizacion);
      } else {
        await ref.read(cotizacionesRepositoryProvider).update(_editingId!, cotizacion);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : '$e')),
      );
      return;
    }

    if (!mounted) return;

    setState(() {
      _items.clear();
      _searchCtrl.clear();
      _selectedCategory = null;
      _selectedClientId = null;
      _selectedClientName = 'Sin cliente';
      _selectedClientPhone = null;
      _note = '';
      _includeItbis = false;
      _editingId = null;
      _editingCreatedAt = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          wasEditing ? 'Cotización actualizada en nube' : 'Cotización guardada en nube',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).user;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Buscar producto',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: IconButton(
                        tooltip: 'Filtrar por categoría',
                        onPressed: _pickCategory,
                        icon: Icon(
                          _selectedCategory == null
                              ? Icons.filter_alt_outlined
                              : Icons.filter_alt,
                          size: 20,
                        ),
                      ),
                      isDense: true,
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Cliente',
                onPressed: _openClientDialog,
                icon: const Icon(Icons.person_outline),
              ),
              IconButton(
                tooltip: 'Nota',
                onPressed: _openNoteDialog,
                icon: Icon(
                  _note.trim().isEmpty
                      ? Icons.sticky_note_2_outlined
                      : Icons.sticky_note_2,
                ),
              ),
              IconButton(
                tooltip: 'PDF',
                onPressed: _openPdfPreview,
                icon: const Icon(Icons.picture_as_pdf_outlined),
              ),
              IconButton(
                tooltip: 'Historial',
                onPressed: _openHistory,
                icon: const Icon(Icons.history),
              ),
            ],
          ),
        ),
      ),
      drawer: AppDrawer(currentUser: user),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  Chip(
                    avatar: const Icon(Icons.person, size: 16),
                    label: Text(_selectedClientName),
                  ),
                  if (_selectedCategory != null)
                    Chip(
                      avatar: const Icon(Icons.category_outlined, size: 16),
                      label: Text(_selectedCategory!),
                      onDeleted: () => setState(() => _selectedCategory = null),
                    ),
                  if (_note.trim().isNotEmpty)
                    Chip(
                      avatar: const Icon(Icons.note_alt_outlined, size: 16),
                      label: Text(_note, overflow: TextOverflow.ellipsis),
                      onDeleted: () => setState(() => _note = ''),
                    ),
                ],
              ),
            ),
            if (_loadingProducts)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: CircularProgressIndicator(),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              )
            else
              SizedBox(
                height: 116,
                child: _visibleProducts.isEmpty
                    ? const Center(
                        child: Text('No hay productos con este filtro'),
                      )
                    : ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: _visibleProducts.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final product = _visibleProducts[index];
                          return _ProductThumbCard(
                            product: product,
                            onTap: () => _addProduct(product),
                            money: _money,
                          );
                        },
                      ),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLowest,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(18),
                  ),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                      child: Row(
                        children: [
                          const Icon(Icons.receipt_long_outlined, size: 18),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _editingId == null
                                  ? 'Ticket abierto · ${_items.length} líneas'
                                  : 'Editando cotización · ${_items.length} líneas',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Text(
                            DateFormat('dd/MM HH:mm').format(DateTime.now()),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: _items.isEmpty
                          ? const Center(
                              child: Text(
                                'Toca un producto arriba para agregarlo',
                                textAlign: TextAlign.center,
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                              itemCount: _items.length,
                              separatorBuilder: (context, index) =>
                                  const SizedBox(height: 4),
                              itemBuilder: (context, index) {
                                final item = _items[index];
                                return _TicketCompactItem(
                                  item: item,
                                  money: _money,
                                  onMinus: () => _setQty(index, item.qty - 1),
                                  onPlus: () => _setQty(index, item.qty + 1),
                                  onChangePrice: (value) =>
                                      _setUnitPrice(index, value),
                                  onRemove: () =>
                                      setState(() => _items.removeAt(index)),
                                );
                              },
                            ),
                    ),
                    Container(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        border: Border(
                          top: BorderSide(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const Expanded(child: Text('Subtotal')),
                              Text(_money(_subtotal)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Expanded(
                                child: Row(
                                  children: [
                                    const Text('Aplicar ITBIS'),
                                    const SizedBox(width: 6),
                                    Switch.adaptive(
                                      value: _includeItbis,
                                      onChanged: (value) =>
                                          setState(() => _includeItbis = value),
                                    ),
                                  ],
                                ),
                              ),
                              Text(_money(_itbisAmount)),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Total cotización',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                              ),
                              Text(
                                _money(_total),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _items.isEmpty
                                      ? null
                                      : () {
                                          setState(() {
                                            _items.clear();
                                            _editingId = null;
                                            _editingCreatedAt = null;
                                          });
                                        },
                                  icon: const Icon(Icons.delete_sweep_outlined),
                                  label: const Text('Limpiar'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: _finalizeCotizacion,
                                  icon: const Icon(Icons.check_circle_outline),
                                  label: const Text('Finalizar'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
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
}

class _ProductThumbCard extends StatelessWidget {
  const _ProductThumbCard({
    required this.product,
    required this.onTap,
    required this.money,
  });

  final ProductModel product;
  final VoidCallback onTap;
  final String Function(double) money;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 96,
      child: Material(
        borderRadius: BorderRadius.circular(10),
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 19,
                  backgroundColor:
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: (product.fotoUrl ?? '').trim().isEmpty
                      ? const Icon(Icons.inventory_2_outlined, size: 17)
                      : ClipOval(
                          child: Image.network(
                            product.fotoUrl!,
                            width: 38,
                            height: 38,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Center(
                                child: Icon(
                                  Icons.broken_image_outlined,
                                  size: 18,
                                  color:
                                      Theme.of(context).colorScheme.outline,
                                ),
                              );
                            },
                          ),
                        ),
                ),
                const SizedBox(height: 5),
                Text(
                  product.nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  money(product.precio),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TicketCompactItem extends StatefulWidget {
  const _TicketCompactItem({
    required this.item,
    required this.money,
    required this.onMinus,
    required this.onPlus,
    required this.onChangePrice,
    required this.onRemove,
  });

  final CotizacionItem item;
  final String Function(double) money;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final ValueChanged<double> onChangePrice;
  final VoidCallback onRemove;

  @override
  State<_TicketCompactItem> createState() => _TicketCompactItemState();
}

class _TicketCompactItemState extends State<_TicketCompactItem> {
  late final TextEditingController _priceCtrl;

  @override
  void initState() {
    super.initState();
    _priceCtrl = TextEditingController(
      text: widget.item.unitPrice.toStringAsFixed(2),
    );
  }

  @override
  void didUpdateWidget(covariant _TicketCompactItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.unitPrice != widget.item.unitPrice) {
      _priceCtrl.text = widget.item.unitPrice.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final qtyText = item.qty % 1 == 0
        ? item.qty.toStringAsFixed(0)
        : item.qty.toStringAsFixed(2);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              item.nombre,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 86,
            child: TextField(
              controller: _priceCtrl,
              style: const TextStyle(fontSize: 11),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Precio',
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                border: OutlineInputBorder(),
              ),
              onSubmitted: (value) {
                final next = double.tryParse(value.trim());
                if (next != null) widget.onChangePrice(next);
              },
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minHeight: 28, minWidth: 28),
            splashRadius: 14,
            onPressed: widget.onMinus,
            icon: const Icon(Icons.remove_circle_outline, size: 18),
          ),
          Text(
            qtyText,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minHeight: 28, minWidth: 28),
            splashRadius: 14,
            onPressed: widget.onPlus,
            icon: const Icon(Icons.add_circle_outline, size: 18),
          ),
          const SizedBox(width: 6),
          Text(
            widget.money(item.total),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minHeight: 28, minWidth: 28),
            splashRadius: 14,
            onPressed: widget.onRemove,
            icon: const Icon(Icons.close, size: 16),
          ),
        ],
      ),
    );
  }
}
