import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/models/product_model.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';
import 'application/catalog_controller.dart';

class CatalogoScreen extends ConsumerStatefulWidget {
  const CatalogoScreen({super.key});

  @override
  ConsumerState<CatalogoScreen> createState() => _CatalogoScreenState();
}

class _CatalogoScreenState extends ConsumerState<CatalogoScreen> {
  final _searchCtrl = TextEditingController();
  String _category = 'Todas';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).user;
    final role = user?.role ?? '';
    final isAdmin = role == 'ADMIN';
    final canManage = role == 'ADMIN' || role == 'ASISTENTE';

    final catalog = ref.watch(catalogControllerProvider);

    final categories = <String>{
      'Todas',
      ...catalog.items.map((p) => p.categoriaLabel)
    }.toList()
      ..sort();

    final query = _searchCtrl.text.trim().toLowerCase();
    final filtered = catalog.items.where((p) {
      final matchCategory = _category == 'Todas' || p.categoriaLabel == _category;
      final matchQuery = query.isEmpty || p.nombre.toLowerCase().contains(query);
      return matchCategory && matchQuery;
    }).toList();

    return Scaffold(
      appBar: const CustomAppBar(title: 'Catálogo', showLogo: true),
      drawer: AppDrawer(currentUser: user),
      floatingActionButton: canManage
          ? FloatingActionButton(
              onPressed: () => _openProductForm(),
              child: const Icon(Icons.add),
            )
          : null,
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'Buscar producto…',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 160,
                  child: DropdownButtonFormField<String>(
                    initialValue: categories.contains(_category) ? _category : 'Todas',
                    decoration: InputDecoration(
                      labelText: 'Categoría',
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    items: categories
                        .map(
                          (c) => DropdownMenuItem(
                            value: c,
                            child: Text(c, overflow: TextOverflow.ellipsis),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _category = v ?? 'Todas'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Builder(
                builder: (context) {
                  if (catalog.loading && catalog.items.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (catalog.error != null && catalog.items.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline, size: 56),
                          const SizedBox(height: 10),
                          Text(catalog.error ?? 'Error cargando productos'),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: () => ref.read(catalogControllerProvider.notifier).load(),
                            icon: const Icon(Icons.refresh),
                            label: const Text('Reintentar'),
                          )
                        ],
                      ),
                    );
                  }

                  if (filtered.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.inventory_2_outlined,
                            size: 56,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                          const SizedBox(height: 10),
                          const Text('No hay productos para mostrar'),
                        ],
                      ),
                    );
                  }

                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth;
                      final columns = width >= 1200
                          ? 4
                          : width >= 900
                              ? 3
                              : width >= 600
                                  ? 2
                                  : 1;

                      const spacing = 16.0;
                      final cardWidth = (width - spacing * (columns - 1)) / columns;
                      final tileHeight = (cardWidth * 1.1).clamp(220.0, 380.0);
                      final imageHeight = tileHeight * 0.45;

                      return RefreshIndicator(
                        onRefresh: () => ref.read(catalogControllerProvider.notifier).load(),
                        child: GridView.builder(
                          itemCount: filtered.length,
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: columns,
                            mainAxisSpacing: spacing,
                            crossAxisSpacing: spacing,
                            mainAxisExtent: tileHeight,
                          ),
                          itemBuilder: (context, i) {
                            final p = filtered[i];
                            return _ProductCard(
                              product: p,
                              showCost: isAdmin,
                              canManage: canManage,
                              imageHeight: imageHeight,
                              onEdit: () => _openProductForm(product: p),
                              onDelete: () => _confirmDelete(p),
                            );
                          },
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(ProductModel product) async {
    final controller = ref.read(catalogControllerProvider.notifier);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Eliminar producto'),
          content: Text('¿Eliminar "${product.nombre}"?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
              child: const Text('Eliminar'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    try {
      await controller.remove(product.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Producto eliminado')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo eliminar: $e')),
      );
    }
  }

  void _openProductForm({ProductModel? product}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            top: 16,
          ),
          child: _ProductForm(
            product: product,
            onSaved: () => Navigator.pop(context),
          ),
        );
      },
    );
  }
}

class _ProductCard extends StatelessWidget {
  final ProductModel product;
  final bool showCost;
  final bool canManage;
  final double imageHeight;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ProductCard({
    required this.product,
    required this.showCost,
    required this.canManage,
    required this.imageHeight,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {},
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: imageHeight,
              width: double.infinity,
              child: product.fotoUrl == null || product.fotoUrl!.isEmpty
                  ? Container(
                      color: theme.colorScheme.surfaceContainerHighest,
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.image_outlined,
                        size: 40,
                        color: theme.colorScheme.outline,
                      ),
                    )
                  : Image.network(
                      product.fotoUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: theme.colorScheme.surfaceContainerHighest,
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.broken_image_outlined,
                          size: 40,
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      product.nombre,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (canManage)
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert),
                      onSelected: (v) {
                        if (v == 'edit') onEdit();
                        if (v == 'delete') onDelete();
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(value: 'edit', child: Text('Editar')),
                        PopupMenuItem(value: 'delete', child: Text('Eliminar')),
                      ],
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(product.categoriaLabel),
                  ),
                ],
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Precio: \$${product.precio.toStringAsFixed(2)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (showCost)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        'Costo: \$${product.costo.toStringAsFixed(2)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductForm extends ConsumerStatefulWidget {
  final ProductModel? product;
  final VoidCallback onSaved;

  const _ProductForm({required this.product, required this.onSaved});

  @override
  ConsumerState<_ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends ConsumerState<_ProductForm> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _costCtrl;
  Uint8List? _imageBytes;
  String? _imageName;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.product?.nombre ?? '');
    _priceCtrl = TextEditingController(text: widget.product?.precio.toStringAsFixed(2) ?? '');
    _costCtrl = TextEditingController(text: widget.product?.costo.toStringAsFixed(2) ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _costCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image, allowMultiple: false, withData: true);
    if (result != null && result.files.single.bytes != null) {
      setState(() {
        _imageBytes = result.files.single.bytes;
        _imageName = result.files.single.name;
      });
    }
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    final price = double.tryParse(_priceCtrl.text.trim());
    final cost = double.tryParse(_costCtrl.text.trim());

    if (name.isEmpty || price == null || cost == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Completa nombre, precio y costo con valores válidos')),
      );
      return;
    }

    if (widget.product == null && _imageBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona una imagen para el producto')),
      );
      return;
    }

    setState(() => _saving = true);
    final controller = ref.read(catalogControllerProvider.notifier);

    try {
      if (widget.product == null) {
        await controller.create(
          nombre: name,
          precio: price,
          costo: cost,
          imageBytes: _imageBytes!,
          filename: _imageName ?? 'producto.png',
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Producto creado')));
      } else {
        await controller.update(
          id: widget.product!.id,
          nombre: name,
          precio: price,
          costo: cost,
          newImageBytes: _imageBytes,
          newFilename: _imageName,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Producto actualizado')));
      }

      widget.onSaved();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.product != null;
    final theme = Theme.of(context);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(isEdit ? 'Editar producto' : 'Crear producto', style: theme.textTheme.titleMedium),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: _saving ? null : () => Navigator.pop(context),
              )
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(labelText: 'Nombre'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _priceCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Precio'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _costCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Costo'),
          ),
          const SizedBox(height: 16),
          Text('Imagen', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _saving ? null : _pickImage,
                icon: const Icon(Icons.file_upload),
                label: Text(_imageName ?? 'Seleccionar archivo'),
              ),
              const SizedBox(width: 12),
              if (_imageBytes != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(_imageBytes!, height: 64, width: 64, fit: BoxFit.cover),
                )
              else if (isEdit && widget.product?.fotoUrl != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(widget.product!.fotoUrl!, height: 64, width: 64, fit: BoxFit.cover),
                )
            ],
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _submit,
            child: _saving
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(isEdit ? 'Guardar cambios' : 'Crear producto'),
          ),
        ],
      ),
    );
  }
}
