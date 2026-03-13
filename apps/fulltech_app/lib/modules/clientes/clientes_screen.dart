import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/routing/routes.dart';
import '../../core/widgets/app_drawer.dart';
import '../../features/operaciones/application/operations_controller.dart';
import '../../features/operaciones/operations_models.dart';
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
  String? _selectedDesktopClientId;
  ClienteModel? _selectedDesktopClient;
  List<ServiceModel> _selectedDesktopServices = const [];
  bool _desktopDetailLoading = false;
  String? _desktopDetailError;
  _ClienteServiceFilter _desktopServiceFilter = _ClienteServiceFilter.all;

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
      ref
          .read(clientesControllerProvider.notifier)
          .load(search: _searchCtrl.text);
    });
  }

  void _primeDesktopSelection(List<ClienteModel> items) {
    if (items.isEmpty) {
      _selectedDesktopClientId = null;
      _selectedDesktopClient = null;
      _selectedDesktopServices = const [];
      _desktopDetailError = null;
      return;
    }

    final currentId = _selectedDesktopClientId;
    final exists = items.any((item) => item.id == currentId);
    final next = exists && currentId != null ? currentId : items.first.id;
    final needsLoad =
        _selectedDesktopClientId != next || _selectedDesktopClient?.id != next;

    _selectedDesktopClientId = next;
    if (needsLoad) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _selectedDesktopClientId != next) return;
        unawaited(_loadDesktopClient(next));
      });
    }
  }

  Future<void> _loadDesktopClient(String clientId) async {
    setState(() {
      _desktopDetailLoading = true;
      _desktopDetailError = null;
      _desktopServiceFilter = _ClienteServiceFilter.all;
    });

    try {
      final client = await ref
          .read(clientesControllerProvider.notifier)
          .getById(clientId);
      final services = await ref
          .read(operationsControllerProvider.notifier)
          .customerServices(clientId);
      if (!mounted || _selectedDesktopClientId != clientId) return;
      setState(() {
        _selectedDesktopClient = client;
        _selectedDesktopServices = services;
        _desktopDetailLoading = false;
      });
    } catch (e) {
      if (!mounted || _selectedDesktopClientId != clientId) return;
      setState(() {
        _desktopDetailLoading = false;
        _desktopDetailError = 'No se pudo cargar el detalle del cliente';
      });
    }
  }

  void _selectDesktopClient(String clientId) {
    if (_selectedDesktopClientId == clientId) return;
    setState(() {
      _selectedDesktopClientId = clientId;
      _desktopServiceFilter = _ClienteServiceFilter.all;
    });
    unawaited(_loadDesktopClient(clientId));
  }

  List<ServiceModel> _filteredDesktopServices() {
    final items = [..._selectedDesktopServices]
      ..sort((a, b) {
        final right =
            b.scheduledStart ??
            b.completedAt ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final left =
            a.scheduledStart ??
            a.completedAt ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return right.compareTo(left);
      });

    return items
        .where((service) {
          final status = parseStatus(service.status);
          switch (_desktopServiceFilter) {
            case _ClienteServiceFilter.all:
              return true;
            case _ClienteServiceFilter.active:
              return status == ServiceStatus.inProgress ||
                  status == ServiceStatus.scheduled ||
                  status == ServiceStatus.survey ||
                  status == ServiceStatus.reserved ||
                  status == ServiceStatus.warranty;
            case _ClienteServiceFilter.completed:
              return status == ServiceStatus.completed ||
                  status == ServiceStatus.closed;
            case _ClienteServiceFilter.pending:
              return status == ServiceStatus.reserved ||
                  status == ServiceStatus.survey ||
                  status == ServiceStatus.scheduled;
          }
        })
        .toList(growable: false);
  }

  Widget _buildDesktopBody(BuildContext context, ClientesState state) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final filteredServices = _filteredDesktopServices();

    _primeDesktopSelection(state.items);

    ClienteModel? selectedClient;
    if (_selectedDesktopClientId != null) {
      if (_selectedDesktopClient?.id == _selectedDesktopClientId) {
        selectedClient = _selectedDesktopClient;
      } else {
        for (final item in state.items) {
          if (item.id == _selectedDesktopClientId) {
            selectedClient = item;
            break;
          }
        }
      }
    }

    final selectedClientId = _selectedDesktopClientId;
    final selectedClientSyncStatusRaw = selectedClient?.syncStatus?.trim();
    final selectedClientSyncStatus =
        selectedClientSyncStatusRaw == null ||
            selectedClientSyncStatusRaw.isEmpty
        ? 'Normal'
        : selectedClientSyncStatusRaw;
    final selectedClientCorreoRaw = selectedClient?.correo?.trim();
    final selectedClientCorreo =
        selectedClientCorreoRaw == null || selectedClientCorreoRaw.isEmpty
        ? 'Sin correo registrado'
        : selectedClientCorreoRaw;
    final selectedClientDireccionRaw = selectedClient?.direccion?.trim();
    final selectedClientDireccion =
        selectedClientDireccionRaw == null || selectedClientDireccionRaw.isEmpty
        ? 'Sin dirección registrada'
        : selectedClientDireccionRaw;

    Widget detailChild;
    if (selectedClientId == null) {
      detailChild = _ClientesDesktopEmptyState(
        icon: Icons.touch_app_outlined,
        title: 'Selecciona un cliente',
        message:
            'El detalle aparecerá aquí con sus procesos, estado y datos de contacto.',
        actionLabel: 'Nuevo cliente',
        onAction: () async {
          final created = await context.push<bool>(Routes.clienteNuevo);
          if (created == true) {
            await ref.read(clientesControllerProvider.notifier).refresh();
          }
        },
      );
    } else if (_desktopDetailLoading) {
      detailChild = const Padding(
        padding: EdgeInsets.symmetric(vertical: 120),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (_desktopDetailError != null) {
      detailChild = _ClientesDesktopEmptyState(
        icon: Icons.error_outline,
        title: 'No se pudo cargar el detalle',
        message: _desktopDetailError!,
        actionLabel: 'Reintentar',
        onAction: () => unawaited(_loadDesktopClient(selectedClientId)),
      );
    } else if (selectedClient == null) {
      detailChild = const SizedBox.shrink();
    } else {
      final desktopClient = selectedClient;
      detailChild = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ClienteDesktopHeaderCard(cliente: desktopClient),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: _ClientesDesktopPanel(
                  title: 'Procesos del cliente',
                  subtitle:
                      'Cada servicio o proceso operativo asociado aparece aquí',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _ClienteServiceFilter.values
                            .map(
                              (filter) => ChoiceChip(
                                label: Text(filter.label),
                                selected: _desktopServiceFilter == filter,
                                onSelected: (_) => setState(
                                  () => _desktopServiceFilter = filter,
                                ),
                              ),
                            )
                            .toList(growable: false),
                      ),
                      const SizedBox(height: 14),
                      if (filteredServices.isEmpty)
                        const _ClientesDesktopServiceEmptyState()
                      else
                        ...filteredServices.map(
                          (service) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _ClienteDesktopServiceRow(service: service),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: 300,
                child: Column(
                  children: [
                    _ClientesDesktopPanel(
                      title: 'Estado del cliente',
                      subtitle: 'Lectura rápida del registro seleccionado',
                      child: Column(
                        children: [
                          _ClienteDesktopInfoTile(
                            icon: Icons.verified_user_outlined,
                            label: 'Estado',
                            value: desktopClient.isDeleted
                                ? 'Eliminado'
                                : 'Activo',
                          ),
                          _ClienteDesktopInfoTile(
                            icon: Icons.sync_outlined,
                            label: 'Sincronización',
                            value: selectedClientSyncStatus,
                          ),
                          _ClienteDesktopInfoTile(
                            icon: Icons.miscellaneous_services_outlined,
                            label: 'Procesos',
                            value: _selectedDesktopServices.length.toString(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _ClientesDesktopPanel(
                      title: 'Detalle',
                      subtitle:
                          'Datos visibles en una columna lateral compacta',
                      child: Column(
                        children: [
                          _ClienteDesktopInfoTile(
                            icon: Icons.call_outlined,
                            label: 'Teléfono',
                            value: desktopClient.telefono,
                          ),
                          _ClienteDesktopInfoTile(
                            icon: Icons.mail_outline,
                            label: 'Correo',
                            value: selectedClientCorreo,
                          ),
                          _ClienteDesktopInfoTile(
                            icon: Icons.location_on_outlined,
                            label: 'Dirección',
                            value: selectedClientDireccion,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final changed = await context.push<bool>(
                                Routes.clienteEdit(desktopClient.id),
                              );
                              if (changed == true) {
                                await ref
                                    .read(clientesControllerProvider.notifier)
                                    .refresh();
                                await _loadDesktopClient(desktopClient.id);
                              }
                            },
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('Editar'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      );
    }

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            scheme.primary.withValues(alpha: 0.10),
            scheme.primary.withValues(alpha: 0.02),
            scheme.surface,
          ],
        ),
      ),
      child: RefreshIndicator(
        onRefresh: () =>
            ref.read(clientesControllerProvider.notifier).refresh(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1520),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 520,
                    child: _ClientesDesktopPanel(
                      title: 'Clientes',
                      subtitle:
                          'Lista compacta, filtros visibles y selección directa',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              _ClientesDesktopFilterPill(
                                label:
                                    'Estado: ${_estadoFilterLabel(state.estadoFilter)}',
                                selected: true,
                              ),
                              _ClientesDesktopFilterPill(
                                label:
                                    'Correo: ${_correoFilterLabel(state.correoFilter)}',
                                selected: false,
                              ),
                              _ClientesDesktopFilterPill(
                                label:
                                    'Orden: ${state.order == ClientesOrder.az ? 'A-Z' : 'Z-A'}',
                                selected: false,
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          if (state.loading && state.items.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 80),
                              child: Center(child: CircularProgressIndicator()),
                            )
                          else if (state.error != null && state.items.isEmpty)
                            _ClientesDesktopEmptyState(
                              icon: Icons.error_outline,
                              title: 'No se pudo cargar la cartera',
                              message: state.error!,
                              actionLabel: 'Reintentar',
                              onAction: () => ref
                                  .read(clientesControllerProvider.notifier)
                                  .refresh(),
                            )
                          else if (state.items.isEmpty)
                            _ClientesDesktopEmptyState(
                              icon: Icons.group_outlined,
                              title: 'No hay clientes para mostrar',
                              message:
                                  'Ajusta los filtros o crea un cliente nuevo para comenzar.',
                              actionLabel: 'Nuevo cliente',
                              onAction: () async {
                                final created = await context.push<bool>(
                                  Routes.clienteNuevo,
                                );
                                if (created == true) {
                                  await ref
                                      .read(clientesControllerProvider.notifier)
                                      .refresh();
                                }
                              },
                            )
                          else
                            ...state.items.map(
                              (cliente) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _ClienteDesktopRow(
                                  cliente: cliente,
                                  selected:
                                      cliente.id == _selectedDesktopClientId,
                                  onTap: () => _selectDesktopClient(cliente.id),
                                  onEdit: () async {
                                    final changed = await context.push<bool>(
                                      Routes.clienteEdit(cliente.id),
                                    );
                                    if (changed == true) {
                                      await ref
                                          .read(
                                            clientesControllerProvider.notifier,
                                          )
                                          .refresh();
                                      if (_selectedDesktopClientId ==
                                          cliente.id) {
                                        await _loadDesktopClient(cliente.id);
                                      }
                                    }
                                  },
                                  onDelete: () =>
                                      _confirmDelete(context, cliente),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: _ClientesDesktopPanel(
                      title: selectedClient?.nombre ?? 'Detalle del cliente',
                      subtitle: selectedClient == null
                          ? 'Selecciona un cliente para ver su estado, datos y procesos asociados'
                          : 'Vista ejecutiva de información y procesos operativos del cliente',
                      child: detailChild,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(clientesControllerProvider);
    final user = ref.watch(authStateProvider).user;
    final theme = Theme.of(context);
    final isDesktop = MediaQuery.sizeOf(context).width >= 1240;

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
                          ref
                              .read(clientesControllerProvider.notifier)
                              .load(search: '');
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
      drawer: buildAdaptiveDrawer(context, currentUser: user),
      floatingActionButton: isDesktop
          ? null
          : FloatingActionButton.extended(
              onPressed: () async {
                final created = await context.push<bool>(Routes.clienteNuevo);
                if (created == true) {
                  await ref.read(clientesControllerProvider.notifier).refresh();
                }
              },
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Nuevo cliente'),
            ),
      body: isDesktop
          ? _buildDesktopBody(context, state)
          : RefreshIndicator(
              onRefresh: () =>
                  ref.read(clientesControllerProvider.notifier).refresh(),
              child: Builder(
                builder: (context) {
                  if (state.loading && state.items.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (state.error != null && state.items.isEmpty) {
                    return ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 56,
                          color: theme.colorScheme.error,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          state.error!,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: () => ref
                              .read(clientesControllerProvider.notifier)
                              .refresh(),
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
                            final created = await context.push<bool>(
                              Routes.clienteNuevo,
                            );
                            if (created == true) {
                              await ref
                                  .read(clientesControllerProvider.notifier)
                                  .refresh();
                            }
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('Nuevo cliente'),
                        ),
                      ],
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 90),
                    itemCount: state.items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 3),
                    itemBuilder: (context, index) {
                      final cliente = state.items[index];
                      return Align(
                        alignment: Alignment.center,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 760),
                          child: _ClienteCard(
                            cliente: cliente,
                            onTap: () async {
                              final changed = await context.push<bool>(
                                Routes.clienteDetail(cliente.id),
                              );
                              if (changed == true) {
                                await ref
                                    .read(clientesControllerProvider.notifier)
                                    .refresh();
                              }
                            },
                            onEdit: () async {
                              final changed = await context.push<bool>(
                                Routes.clienteEdit(cliente.id),
                              );
                              if (changed == true) {
                                await ref
                                    .read(clientesControllerProvider.notifier)
                                    .refresh();
                              }
                            },
                            onDelete: () => _confirmDelete(context, cliente),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    ClienteModel cliente,
  ) async {
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
      if (_selectedDesktopClientId == cliente.id) {
        setState(() {
          _selectedDesktopClientId = null;
          _selectedDesktopClient = null;
          _selectedDesktopServices = const [];
          _desktopDetailError = null;
        });
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Cliente eliminado')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo eliminar: $e')));
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
                    Text(
                      'Filtros',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Orden',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    RadioListTile<ClientesOrder>(
                      value: ClientesOrder.az,
                      groupValue: order,
                      onChanged: (value) => setModalState(
                        () => order = value ?? ClientesOrder.az,
                      ),
                      title: const Text('A-Z'),
                    ),
                    RadioListTile<ClientesOrder>(
                      value: ClientesOrder.za,
                      groupValue: order,
                      onChanged: (value) => setModalState(
                        () => order = value ?? ClientesOrder.za,
                      ),
                      title: const Text('Z-A'),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Correo',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    RadioListTile<CorreoFilter>(
                      value: CorreoFilter.todos,
                      groupValue: correo,
                      onChanged: (value) => setModalState(
                        () => correo = value ?? CorreoFilter.todos,
                      ),
                      title: const Text('Todos'),
                    ),
                    RadioListTile<CorreoFilter>(
                      value: CorreoFilter.conCorreo,
                      groupValue: correo,
                      onChanged: (value) => setModalState(
                        () => correo = value ?? CorreoFilter.conCorreo,
                      ),
                      title: const Text('Con correo'),
                    ),
                    RadioListTile<CorreoFilter>(
                      value: CorreoFilter.sinCorreo,
                      groupValue: correo,
                      onChanged: (value) => setModalState(
                        () => correo = value ?? CorreoFilter.sinCorreo,
                      ),
                      title: const Text('Sin correo'),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Estado',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    RadioListTile<EstadoFilter>(
                      value: EstadoFilter.activos,
                      groupValue: estado,
                      onChanged: (value) => setModalState(
                        () => estado = value ?? EstadoFilter.activos,
                      ),
                      title: const Text('Activos'),
                    ),
                    RadioListTile<EstadoFilter>(
                      value: EstadoFilter.eliminados,
                      groupValue: estado,
                      onChanged: (value) => setModalState(
                        () => estado = value ?? EstadoFilter.eliminados,
                      ),
                      title: const Text('Eliminados'),
                    ),
                    RadioListTile<EstadoFilter>(
                      value: EstadoFilter.todos,
                      groupValue: estado,
                      onChanged: (value) => setModalState(
                        () => estado = value ?? EstadoFilter.todos,
                      ),
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
      await ref
          .read(clientesControllerProvider.notifier)
          .applyFilters(
            order: order,
            correoFilter: correo,
            estadoFilter: estado,
          );
    }
  }

  String _estadoFilterLabel(EstadoFilter value) {
    switch (value) {
      case EstadoFilter.activos:
        return 'Activos';
      case EstadoFilter.eliminados:
        return 'Eliminados';
      case EstadoFilter.todos:
        return 'Todos';
    }
  }

  String _correoFilterLabel(CorreoFilter value) {
    switch (value) {
      case CorreoFilter.todos:
        return 'Todos';
      case CorreoFilter.conCorreo:
        return 'Con correo';
      case CorreoFilter.sinCorreo:
        return 'Sin correo';
    }
  }
}

enum _ClienteServiceFilter {
  all('Todos'),
  active('Activos'),
  completed('Completados'),
  pending('Pendientes');

  const _ClienteServiceFilter(this.label);
  final String label;
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
    final lineChunks = <String>[cliente.nombre, cliente.telefono];
    if ((cliente.direccion ?? '').trim().isNotEmpty) {
      lineChunks.add(cliente.direccion!.trim());
    }
    if ((cliente.correo ?? '').trim().isNotEmpty) {
      lineChunks.add(cliente.correo!.trim());
    }

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        onTap: onTap,
        dense: true,
        visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        leading: CircleAvatar(
          radius: 15,
          child: Text(
            cliente.nombre.trim().isEmpty
                ? '?'
                : cliente.nombre.trim().characters.first.toUpperCase(),
          ),
        ),
        title: Text(
          lineChunks.join(' · '),
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: PopupMenuButton<String>(
          splashRadius: 16,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
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

class _ClientesDesktopPanel extends StatelessWidget {
  const _ClientesDesktopPanel({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _ClientesDesktopMetric extends StatelessWidget {
  const _ClientesDesktopMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
    this.dark = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accent;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = dark ? Colors.white : theme.colorScheme.onSurface;
    final muted = dark
        ? Colors.white.withValues(alpha: 0.72)
        : theme.colorScheme.onSurfaceVariant;

    return Container(
      constraints: const BoxConstraints(minWidth: 170, maxWidth: 240),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: dark
            ? Colors.white.withValues(alpha: 0.10)
            : accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: dark
              ? Colors.white.withValues(alpha: 0.14)
              : accent.withValues(alpha: 0.20),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: dark ? 0.18 : 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: dark ? Colors.white : accent, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ClientesDesktopFilterPill extends StatelessWidget {
  const _ClientesDesktopFilterPill({
    required this.label,
    required this.selected,
  });

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: selected
            ? scheme.primary.withValues(alpha: 0.10)
            : scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: selected
              ? scheme.primary.withValues(alpha: 0.35)
              : scheme.outlineVariant,
        ),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _ClienteDesktopRow extends StatelessWidget {
  const _ClienteDesktopRow({
    required this.cliente,
    required this.selected,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final ClienteModel cliente;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final secondary = <String>[cliente.telefono];
    if ((cliente.correo ?? '').trim().isNotEmpty) {
      secondary.add(cliente.correo!.trim());
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? scheme.primary.withValues(alpha: 0.08)
                : scheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? scheme.primary.withValues(alpha: 0.45)
                  : scheme.outlineVariant.withValues(alpha: 0.7),
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: selected
                    ? scheme.primary.withValues(alpha: 0.15)
                    : scheme.surfaceContainerHigh,
                child: Text(
                  cliente.nombre.trim().isEmpty
                      ? '?'
                      : cliente.nombre.trim().characters.first.toUpperCase(),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cliente.nombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      secondary.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: cliente.isDeleted
                      ? scheme.surfaceContainerHigh
                      : const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  cliente.isDeleted ? 'Eliminado' : 'Activo',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: cliente.isDeleted
                        ? scheme.onSurfaceVariant
                        : const Color(0xFF166534),
                  ),
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') onEdit();
                  if (value == 'delete') onDelete();
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

class _ClienteDesktopHeaderCard extends StatelessWidget {
  const _ClienteDesktopHeaderCard({required this.cliente});

  final ClienteModel cliente;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.75),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: scheme.primary.withValues(alpha: 0.14),
            child: Text(
              cliente.nombre.trim().isEmpty
                  ? '?'
                  : cliente.nombre.trim().characters.first.toUpperCase(),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
                color: scheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cliente.nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    cliente.telefono,
                    if ((cliente.correo ?? '').trim().isNotEmpty)
                      cliente.correo?.trim() ?? '',
                    if ((cliente.direccion ?? '').trim().isNotEmpty)
                      cliente.direccion?.trim() ?? '',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: cliente.isDeleted
                  ? scheme.surfaceContainerHigh
                  : const Color(0xFFDCFCE7),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              cliente.isDeleted ? 'Eliminado' : 'Activo',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: cliente.isDeleted
                    ? scheme.onSurfaceVariant
                    : const Color(0xFF166534),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClienteDesktopInfoTile extends StatelessWidget {
  const _ClienteDesktopInfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.65),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: scheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
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

class _ClienteDesktopServiceRow extends StatelessWidget {
  const _ClienteDesktopServiceRow({required this.service});

  final ServiceModel service;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = parseStatus(service.status);
    final date = service.scheduledStart ?? service.completedAt;
    final dateText = date == null
        ? 'Sin fecha'
        : DateFormat('dd/MM/yyyy').format(date);

    Color badgeColor() {
      switch (status) {
        case ServiceStatus.completed:
        case ServiceStatus.closed:
          return const Color(0xFFDCFCE7);
        case ServiceStatus.inProgress:
          return const Color(0xFFDBEAFE);
        case ServiceStatus.cancelled:
          return const Color(0xFFFEE2E2);
        default:
          return const Color(0xFFFFEDD5);
      }
    }

    Color badgeTextColor() {
      switch (status) {
        case ServiceStatus.completed:
        case ServiceStatus.closed:
          return const Color(0xFF166534);
        case ServiceStatus.inProgress:
          return const Color(0xFF1D4ED8);
        case ServiceStatus.cancelled:
          return const Color(0xFF991B1B);
        default:
          return const Color(0xFF9A3412);
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.75),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  service.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${service.serviceType} · ${phaseLabel(service.currentPhase)} · P${service.priority} · $dateText',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                if (service.description.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    service.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: badgeColor(),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              service.status,
              style: theme.textTheme.labelMedium?.copyWith(
                color: badgeTextColor(),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClientesDesktopEmptyState extends StatelessWidget {
  const _ClientesDesktopEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.8)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 44, color: scheme.primary),
          const SizedBox(height: 12),
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onAction,
            icon: const Icon(Icons.arrow_forward_outlined),
            label: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}

class _ClientesDesktopServiceEmptyState extends StatelessWidget {
  const _ClientesDesktopServiceEmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.75),
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.miscellaneous_services_outlined,
            color: scheme.primary,
            size: 40,
          ),
          const SizedBox(height: 10),
          Text(
            'No hay procesos para este filtro',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Al seleccionar otro estado o registrar nuevos servicios, aparecerán aquí.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
