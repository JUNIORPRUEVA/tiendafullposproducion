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

  bool get _hasActiveFilter => _category != 'Todas';

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
      ...catalog.items.map((p) => p.categoriaLabel),
    }.toList()..sort();

    final categoryOptions =
        catalog.items
            .map((p) => p.categoriaLabel)
            .where((c) => c.isNotEmpty && c != 'Sin categoría')
            .toSet()
            .toList()
          ..sort();

    final query = _searchCtrl.text.trim().toLowerCase();
    final filtered =
        catalog.items.where((p) {
          final matchCategory =
              _category == 'Todas' || p.categoriaLabel == _category;
          final matchQuery =
              query.isEmpty || p.nombre.toLowerCase().contains(query);
          return matchCategory && matchQuery;
        }).toList()..sort(
          (a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()),
        );

    final hasCategoryFilters = categories.length > 1;

    return Scaffold(
      appBar: CustomAppBar(
        title: 'Catálogo',
        showLogo: false,
        titleWidget: TextField(
          controller: _searchCtrl,
          textInputAction: TextInputAction.search,
          onChanged: (_) => setState(() {}),
          style: Theme.of(context).textTheme.bodyMedium,
          decoration: InputDecoration(
            hintText: 'Buscar producto',
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: _searchCtrl.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Limpiar búsqueda',
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() {});
                    },
                    icon: const Icon(Icons.close, size: 18),
                  ),
            isDense: true,
            filled: true,
            fillColor: Theme.of(context).colorScheme.surface,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: hasCategoryFilters
            ? [
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Badge(
                    isLabelVisible: _hasActiveFilter,
                    smallSize: 8,
                    child: IconButton(
                      tooltip: 'Filtrar categoría',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _openCategoryFilter(categories),
                      icon: const Icon(Icons.tune, size: 20),
                    ),
                  ),
                ),
              ]
            : null,
      ),
      drawer: AppDrawer(currentUser: user),
      floatingActionButton: canManage
          ? FloatingActionButton(
              onPressed: () => _openProductForm(categories: categoryOptions),
              child: const Icon(Icons.add),
            )
          : null,
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
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
                            onPressed: () => ref
                                .read(catalogControllerProvider.notifier)
                                .load(),
                            icon: const Icon(Icons.refresh),
                            label: const Text('Reintentar'),
                          ),
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
                      final useCompactList = width < 390;

                      if (useCompactList) {
                        return RefreshIndicator(
                          onRefresh: () =>
                              ref.read(catalogControllerProvider.notifier).load(),
                          child: ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (context, i) {
                              final p = filtered[i];
                              return _ProductCompactTile(
                                product: p,
                                showCost: isAdmin,
                                canManage: canManage,
                                onView: () => _showProductDetails(
                                  product: p,
                                  showCost: isAdmin,
                                  canManage: canManage,
                                  onEdit: () => _openProductForm(
                                    product: p,
                                    categories: categoryOptions,
                                  ),
                                  onDelete: () => _confirmDelete(p),
                                ),
                                onEdit: () => _openProductForm(
                                  product: p,
                                  categories: categoryOptions,
                                ),
                                onDelete: () => _confirmDelete(p),
                              );
                            },
                          ),
                        );
                      }

                      final columns = width >= 1180
                          ? 4
                          : width >= 820
                          ? 3
                          : width >= 360
                          ? 2
                          : 1;

                      const spacing = 12.0;
                      final cardWidth =
                          (width - spacing * (columns - 1)) / columns;
                      final tileHeight = (cardWidth * 1.18).clamp(160.0, 250.0);
                      final imageHeight = (tileHeight * 0.46).clamp(
                        72.0,
                        120.0,
                      );

                      return RefreshIndicator(
                        onRefresh: () =>
                            ref.read(catalogControllerProvider.notifier).load(),
                        child: GridView.builder(
                          itemCount: filtered.length,
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
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
                              onView: () => _showProductDetails(
                                product: p,
                                showCost: isAdmin,
                                canManage: canManage,
                                onEdit: () => _openProductForm(
                                  product: p,
                                  categories: categoryOptions,
                                ),
                                onDelete: () => _confirmDelete(p),
                              ),
                              onEdit: () => _openProductForm(
                                product: p,
                                categories: categoryOptions,
                              ),
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

  Future<void> _openCategoryFilter(List<String> categories) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return SafeArea(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: categories.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final option = categories[index];
              final selected = option == _category;
              return ListTile(
                dense: true,
                title: Text(option, overflow: TextOverflow.ellipsis),
                trailing: selected ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(context, option),
              );
            },
          ),
        );
      },
    );
    if (selected == null || !mounted) return;
    setState(() => _category = selected);
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
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Producto eliminado')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo eliminar: $e')));
    }
  }

  void _openProductForm({
    ProductModel? product,
    required List<String> categories,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
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
            categories: categories,
            onSaved: () => Navigator.pop(context),
          ),
        );
      },
    );
  }

  Future<void> _showProductDetails({
    required ProductModel product,
    required bool showCost,
    required bool canManage,
    required VoidCallback onEdit,
    required VoidCallback onDelete,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: product.fotoUrl == null || product.fotoUrl!.isEmpty
                        ? Container(
                            color: theme.colorScheme.surfaceContainerHighest,
                            alignment: Alignment.center,
                            child: Icon(
                              Icons.image_outlined,
                              size: 38,
                              color: theme.colorScheme.outline,
                            ),
                          )
                        : Image.network(
                            product.fotoUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: theme.colorScheme.surfaceContainerHighest,
                              alignment: Alignment.center,
                              child: Icon(
                                Icons.broken_image_outlined,
                                size: 38,
                                color: theme.colorScheme.outline,
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  product.nombre,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                _ProductDetailLine(label: 'Categoría', value: product.categoriaLabel),
                _ProductDetailLine(
                  label: 'Precio',
                  value: '\$${product.precio.toStringAsFixed(2)}',
                ),
                if (showCost)
                  _ProductDetailLine(
                    label: 'Costo',
                    value: '\$${product.costo.toStringAsFixed(2)}',
                  ),
                _ProductDetailLine(
                  label: 'Fecha',
                  value: product.createdAt == null
                      ? '—'
                      : '${product.createdAt!.day.toString().padLeft(2, '0')}/${product.createdAt!.month.toString().padLeft(2, '0')}/${product.createdAt!.year}',
                ),
                if (canManage) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            onEdit();
                          },
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Editar'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: theme.colorScheme.error,
                          ),
                          onPressed: () {
                            Navigator.pop(context);
                            onDelete();
                          },
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Eliminar'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
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
  final VoidCallback onView;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ProductCard({
    required this.product,
    required this.showCost,
    required this.canManage,
    required this.imageHeight,
    required this.onView,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onView,
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
                        size: 28,
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
                          size: 28,
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 6, 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      product.nombre,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (canManage)
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, size: 18),
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
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                product.categoriaLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '\$${product.precio.toStringAsFixed(2)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (showCost)
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        'Costo \$${product.costo.toStringAsFixed(2)}',
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

class _ProductCompactTile extends StatelessWidget {
  final ProductModel product;
  final bool showCost;
  final bool canManage;
  final VoidCallback onView;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ProductCompactTile({
    required this.product,
    required this.showCost,
    required this.canManage,
    required this.onView,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onView,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: product.fotoUrl == null || product.fotoUrl!.isEmpty
                      ? Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.image_outlined,
                            size: 20,
                            color: theme.colorScheme.outline,
                          ),
                        )
                      : Image.network(
                          product.fotoUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: theme.colorScheme.surfaceContainerHighest,
                            alignment: Alignment.center,
                            child: Icon(
                              Icons.broken_image_outlined,
                              size: 20,
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.nombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      product.categoriaLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      showCost
                          ? '\$${product.precio.toStringAsFixed(2)} · Costo \$${product.costo.toStringAsFixed(2)}'
                          : '\$${product.precio.toStringAsFixed(2)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (canManage)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 18),
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
      ),
    );
  }
}

class _ProductDetailLine extends StatelessWidget {
  const _ProductDetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.outline,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _ProductForm extends ConsumerStatefulWidget {
  final ProductModel? product;
  final VoidCallback onSaved;
  final List<String> categories;

  const _ProductForm({
    required this.product,
    required this.onSaved,
    required this.categories,
  });

  @override
  ConsumerState<_ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends ConsumerState<_ProductForm> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _costCtrl;
  late final TextEditingController _categoryCtrl;
  Uint8List? _imageBytes;
  String? _imageName;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.product?.nombre ?? '');
    _priceCtrl = TextEditingController(
      text: widget.product?.precio.toStringAsFixed(2) ?? '',
    );
    _costCtrl = TextEditingController(
      text: widget.product?.costo.toStringAsFixed(2) ?? '',
    );
    final initialCategory = widget.product?.categoriaLabel;
    _categoryCtrl = TextEditingController(
      text: initialCategory == 'Sin categoría' ? '' : (initialCategory ?? ''),
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _costCtrl.dispose();
    _categoryCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
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
    final category = _categoryCtrl.text.trim();

    if (name.isEmpty || price == null || cost == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Completa nombre, precio y costo con valores válidos'),
        ),
      );
      return;
    }

    if (category.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Agrega una categoría')));
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
          categoria: category,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Producto creado')));
      } else {
        await controller.update(
          id: widget.product!.id,
          nombre: name,
          precio: price,
          costo: cost,
          newImageBytes: _imageBytes,
          newFilename: _imageName,
          categoria: category,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Producto actualizado')));
      }

      widget.onSaved();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
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
              Text(
                isEdit ? 'Editar producto' : 'Crear producto',
                style: theme.textTheme.titleMedium,
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: _saving ? null : () => Navigator.pop(context),
              ),
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
          const SizedBox(height: 12),
          TextField(
            controller: _categoryCtrl,
            decoration: const InputDecoration(
              labelText: 'Categoría (elige o crea)',
            ),
          ),
          if (widget.categories.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: widget.categories
                  .map(
                    (c) => ChoiceChip(
                      label: Text(c),
                      selected: _categoryCtrl.text.trim() == c,
                      onSelected: (_) => _categoryCtrl.text = c,
                    ),
                  )
                  .toList(),
            ),
          ],
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
                  child: Image.memory(
                    _imageBytes!,
                    height: 64,
                    width: 64,
                    fit: BoxFit.cover,
                  ),
                )
              else if (isEdit && widget.product?.fotoUrl != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    widget.product!.fotoUrl!,
                    height: 64,
                    width: 64,
                    fit: BoxFit.cover,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _submit,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(isEdit ? 'Guardar cambios' : 'Crear producto'),
          ),
        ],
      ),
    );
  }
}
