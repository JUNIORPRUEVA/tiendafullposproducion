import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/routes.dart';
import '../../features/operaciones/application/operations_controller.dart';
import '../../features/operaciones/operations_models.dart';
import 'application/clientes_controller.dart';
import 'cliente_model.dart';

class ClienteDetailScreen extends ConsumerStatefulWidget {
  final String clienteId;

  const ClienteDetailScreen({super.key, required this.clienteId});

  @override
  ConsumerState<ClienteDetailScreen> createState() => _ClienteDetailScreenState();
}

class _ClienteDetailScreenState extends ConsumerState<ClienteDetailScreen> {
  bool _loading = true;
  String? _error;
  ClienteModel? _cliente;
  List<ServiceModel> _services = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final item = await ref.read(clientesControllerProvider.notifier).getById(widget.clienteId);
      final services = await ref
          .read(operationsControllerProvider.notifier)
          .customerServices(widget.clienteId);
      if (!mounted) return;
      setState(() {
        _cliente = item;
        _services = services;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo cargar el cliente';
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _delete() async {
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
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed != true || _cliente == null) return;

    try {
      await ref.read(clientesControllerProvider.notifier).remove(_cliente!.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cliente eliminado')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo eliminar: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle del cliente'),
        actions: [
          IconButton(
            tooltip: 'Editar',
            onPressed: _cliente == null
                ? null
                : () async {
                    final changed = await context.push<bool>(Routes.clienteEdit(_cliente!.id));
                    if (changed == true) {
                      await _load();
                    }
                  },
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Eliminar',
            onPressed: _cliente == null ? null : _delete,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline, size: 56, color: theme.colorScheme.error),
                        const SizedBox(height: 10),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                )
              : _cliente == null
                  ? const SizedBox.shrink()
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 30,
                                    child: Text(
                                      _cliente!.nombre.trim().isEmpty
                                          ? '?'
                                          : _cliente!.nombre.trim().characters.first.toUpperCase(),
                                      style: theme.textTheme.titleLarge,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _cliente!.nombre,
                                          style: theme.textTheme.titleLarge?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _cliente!.telefono,
                                          style: theme.textTheme.bodyMedium,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          _InfoCard(
                            icon: Icons.call_outlined,
                            title: 'Teléfono',
                            value: _cliente!.telefono,
                            trailing: IconButton(
                              tooltip: 'Copiar teléfono',
                              onPressed: () async {
                                final messenger = ScaffoldMessenger.of(context);
                                await Clipboard.setData(ClipboardData(text: _cliente!.telefono));
                                if (!mounted) return;
                                messenger.showSnackBar(
                                  const SnackBar(content: Text('Teléfono copiado')),
                                );
                              },
                              icon: const Icon(Icons.copy_outlined),
                            ),
                          ),
                          const SizedBox(height: 10),
                          _InfoCard(
                            icon: Icons.mail_outline,
                            title: 'Correo',
                            value: (_cliente!.correo ?? '').trim().isEmpty
                                ? 'Sin correo registrado'
                                : _cliente!.correo!,
                          ),
                          const SizedBox(height: 10),
                          _InfoCard(
                            icon: Icons.location_on_outlined,
                            title: 'Dirección',
                            value: (_cliente!.direccion ?? '').trim().isEmpty
                                ? 'Sin dirección registrada'
                                : _cliente!.direccion!,
                          ),
                          const SizedBox(height: 18),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Expanded(
                                        child: Text(
                                          'Historial de servicios',
                                          style: TextStyle(fontWeight: FontWeight.w700),
                                        ),
                                      ),
                                      TextButton.icon(
                                        onPressed: () => context.go(Routes.operaciones),
                                        icon: const Icon(Icons.add),
                                        label: const Text('Nuevo servicio'),
                                      ),
                                    ],
                                  ),
                                  if (_services.isEmpty)
                                    const Padding(
                                      padding: EdgeInsets.only(top: 6),
                                      child: Text('Este cliente no tiene servicios registrados'),
                                    )
                                  else
                                    ..._services.take(8).map(
                                          (service) => ListTile(
                                            dense: true,
                                            contentPadding: EdgeInsets.zero,
                                            title: Text(service.title),
                                            subtitle: Text(
                                              '${service.serviceType} · ${service.status} · ${service.scheduledStart?.toIso8601String().substring(0, 10) ?? 'Sin fecha'}',
                                            ),
                                            trailing: Text('P${service.priority}'),
                                          ),
                                        ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    final changed = await context.push<bool>(Routes.clienteEdit(_cliente!.id));
                                    if (changed == true) {
                                      await _load();
                                    }
                                  },
                                  icon: const Icon(Icons.edit_outlined),
                                  label: const Text('Editar'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: _delete,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: theme.colorScheme.error,
                                  ),
                                  icon: const Icon(Icons.delete_outline),
                                  label: const Text('Eliminar'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final Widget? trailing;

  const _InfoCard({
    required this.icon,
    required this.title,
    required this.value,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: ListTile(
        leading: Icon(icon, color: theme.colorScheme.primary),
        title: Text(title, style: theme.textTheme.titleSmall),
        subtitle: Text(value),
        trailing: trailing,
      ),
    );
  }
}
