import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/routing/routes.dart';
import '../../core/widgets/app_drawer.dart';
import 'application/clientes_controller.dart';
import 'cliente_model.dart';
import 'data/clientes_repository.dart';

class ClientesScreen extends ConsumerStatefulWidget {
  const ClientesScreen({super.key});

  @override
  ConsumerState<ClientesScreen> createState() => _ClientesScreenState();
}

class _ClientesScreenState extends ConsumerState<ClientesScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 320), () {
      ref.read(clientesControllerProvider.notifier).load(search: _searchCtrl.text);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(clientesControllerProvider);
    final user = ref.watch(authStateProvider).user;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: SizedBox(
            height: 42,
            child: TextField(
              controller: _searchCtrl,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Buscar por nombre o teléfono',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchCtrl.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _searchCtrl.clear();
                          ref.read(clientesControllerProvider.notifier).load(search: '');
                          setState(() {});
                        },
                        icon: const Icon(Icons.close),
                      ),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                filled: true,
                fillColor: theme.colorScheme.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Filtros',
            onPressed: () => _openFilters(context, state),
            icon: const Icon(Icons.tune),
          ),
        ],
      ),
      drawer: AppDrawer(currentUser: user),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await context.push<bool>(Routes.clienteNuevo);
          if (created == true) {
            await ref.read(clientesControllerProvider.notifier).refresh();
          }
        },
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Nuevo cliente'),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(clientesControllerProvider.notifier).refresh(),
        child: Builder(
          builder: (context) {
            if (state.loading && state.items.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }

            if (state.error != null && state.items.isEmpty) {
              return ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Icon(Icons.error_outline, size: 56, color: theme.colorScheme.error),
                  const SizedBox(height: 12),
                  Text(
                    state.error!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => ref.read(clientesControllerProvider.notifier).refresh(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reintentar'),
                  ),
                ],
              );
            }

            if (state.items.isEmpty) {
              return ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Icon(
                    Icons.group_outlined,
                    size: 62,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No hay clientes para mostrar',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Agrega tu primer cliente para iniciar.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () async {
                      final created = await context.push<bool>(Routes.clienteNuevo);
                      if (created == true) {
                        await ref.read(clientesControllerProvider.notifier).refresh();
                      }
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Nuevo cliente'),
                  ),
                ],
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: state.items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final cliente = state.items[index];
                return _ClienteCard(
                  cliente: cliente,
                  onTap: () async {
                    final changed = await context.push<bool>(Routes.clienteDetail(cliente.id));
                    if (changed == true) {
                      await ref.read(clientesControllerProvider.notifier).refresh();
                    }
                  },
                  onEdit: () async {
                    final changed = await context.push<bool>(Routes.clienteEdit(cliente.id));
                    if (changed == true) {
                      await ref.read(clientesControllerProvider.notifier).refresh();
                    }
                  },
                  onDelete: () => _confirmDelete(context, cliente),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, ClienteModel cliente) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar cliente'),
        content: const Text(
          '¿Seguro que deseas eliminar este cliente? Esta acción puede afectar el historial.',
        ),
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
      ),
    );

    if (confirmed != true) return;

    try {
      await ref.read(clientesControllerProvider.notifier).remove(cliente.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cliente eliminado')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo eliminar: $e')),
      );
    }
  }

  Future<void> _openFilters(BuildContext context, ClientesState state) async {
    var order = state.order;
    var correo = state.correoFilter;
    var estado = state.estadoFilter;

    final applied = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Filtros', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 12),
                    Text('Orden', style: Theme.of(context).textTheme.titleSmall),
                    RadioListTile<ClientesOrder>(
                      value: ClientesOrder.az,
                      groupValue: order,
                      onChanged: (value) => setModalState(() => order = value ?? ClientesOrder.az),
                      title: const Text('A-Z'),
                    ),
                    RadioListTile<ClientesOrder>(
                      value: ClientesOrder.za,
                      groupValue: order,
                      onChanged: (value) => setModalState(() => order = value ?? ClientesOrder.za),
                      title: const Text('Z-A'),
                    ),
                    const SizedBox(height: 6),
                    Text('Correo', style: Theme.of(context).textTheme.titleSmall),
                    RadioListTile<CorreoFilter>(
                      value: CorreoFilter.todos,
                      groupValue: correo,
                      onChanged: (value) => setModalState(() => correo = value ?? CorreoFilter.todos),
                      title: const Text('Todos'),
                    ),
                    RadioListTile<CorreoFilter>(
                      value: CorreoFilter.conCorreo,
                      groupValue: correo,
                      onChanged: (value) => setModalState(() => correo = value ?? CorreoFilter.conCorreo),
                      title: const Text('Con correo'),
                    ),
                    RadioListTile<CorreoFilter>(
                      value: CorreoFilter.sinCorreo,
                      groupValue: correo,
                      onChanged: (value) => setModalState(() => correo = value ?? CorreoFilter.sinCorreo),
                      title: const Text('Sin correo'),
                    ),
                    const SizedBox(height: 6),
                    Text('Estado', style: Theme.of(context).textTheme.titleSmall),
                    RadioListTile<EstadoFilter>(
                      value: EstadoFilter.activos,
                      groupValue: estado,
                      onChanged: (value) => setModalState(() => estado = value ?? EstadoFilter.activos),
                      title: const Text('Activos'),
                    ),
                    RadioListTile<EstadoFilter>(
                      value: EstadoFilter.eliminados,
                      groupValue: estado,
                      onChanged: (value) => setModalState(() => estado = value ?? EstadoFilter.eliminados),
                      title: const Text('Eliminados'),
                    ),
                    RadioListTile<EstadoFilter>(
                      value: EstadoFilter.todos,
                      groupValue: estado,
                      onChanged: (value) => setModalState(() => estado = value ?? EstadoFilter.todos),
                      title: const Text('Todos'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancelar'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Aplicar'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (applied == true) {
      await ref.read(clientesControllerProvider.notifier).applyFilters(
            order: order,
            correoFilter: correo,
            estadoFilter: estado,
          );
    }
  }
}

class _ClienteCard extends StatelessWidget {
  const _ClienteCard({
    required this.cliente,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final ClienteModel cliente;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitleChunks = <String>[cliente.telefono];
    if ((cliente.direccion ?? '').trim().isNotEmpty) {
      subtitleChunks.add(cliente.direccion!.trim());
    }

    return Card(
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        leading: CircleAvatar(
          child: Text(
            cliente.nombre.trim().isEmpty
                ? '?'
                : cliente.nombre.trim().characters.first.toUpperCase(),
          ),
        ),
        title: Text(
          cliente.nombre,
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              subtitleChunks.join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if ((cliente.correo ?? '').trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  cliente.correo!,
                  style: theme.textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'detail') onTap();
            if (value == 'edit') onEdit();
            if (value == 'delete') onDelete();
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'detail', child: Text('Ver detalle')),
            PopupMenuItem(value: 'edit', child: Text('Editar')),
            PopupMenuItem(value: 'delete', child: Text('Eliminar')),
          ],
        ),
      ),
    );
  }
}
