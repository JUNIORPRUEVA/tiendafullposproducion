import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/errors/api_exception.dart';
import '../data/salidas_tecnicas_repository.dart';
import '../salidas_tecnicas_models.dart';

class AdminSalidasTecnicasScreen extends ConsumerStatefulWidget {
  const AdminSalidasTecnicasScreen({super.key});

  @override
  ConsumerState<AdminSalidasTecnicasScreen> createState() =>
      _AdminSalidasTecnicasScreenState();
}

class _AdminSalidasTecnicasScreenState
    extends ConsumerState<AdminSalidasTecnicasScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<AdminSalidaTecnicaModel> _items = const [];

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
      final repo = ref.read(salidasTecnicasRepositoryProvider);
      final items = await repo.adminListSalidas();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Ocurrió un error';
      });
    }
  }

  Future<void> _aprobar(AdminSalidaTecnicaModel item) async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final repo = ref.read(salidasTecnicasRepositoryProvider);
      await repo.adminAprobarSalida(salidaId: item.salida.id);
      if (!mounted) return;
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'No se pudo aprobar';
      });
    }
  }

  Future<void> _rechazar(AdminSalidaTecnicaModel item) async {
    final obs = await _askObservacion(
      context,
      title: 'Rechazar salida',
      hint: 'Motivo (requerido)',
      requiredText: true,
    );
    if (obs == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final repo = ref.read(salidasTecnicasRepositoryProvider);
      await repo.adminRechazarSalida(salidaId: item.salida.id, observacion: obs);
      if (!mounted) return;
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'No se pudo rechazar';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider);
    final isAdmin = (auth.user?.role ?? '').toUpperCase() == 'ADMIN';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Salidas técnicas (Admin)'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: !isAdmin
          ? const Center(child: Text('Solo disponible para administradores'))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null && _error!.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  if (_loading)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: LinearProgressIndicator(),
                      ),
                    )
                  else if (_items.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('No hay registros.'),
                      ),
                    )
                  else
                    ..._items.map((item) {
                      final salida = item.salida;
                      final tecnicoName = item.tecnico?.nombreCompleto.trim().isNotEmpty == true
                          ? item.tecnico!.nombreCompleto
                          : 'Técnico';
                      final servicioTitle = salida.servicio?.title.trim().isNotEmpty == true
                          ? salida.servicio!.title
                          : (salida.servicio?.id ?? 'Servicio');

                      final subtitle = [
                        tecnicoName,
                        'Estado: ${salida.estado}',
                        if (salida.montoCombustible > 0)
                          'Combustible: ${salida.montoCombustible.toStringAsFixed(2)}',
                      ].join(' · ');

                      final canDecide = salida.estado == 'FINALIZADA';

                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: ListTile(
                            title: Text(servicioTitle),
                            subtitle: Text(subtitle),
                            trailing: canDecide
                                ? Wrap(
                                    spacing: 8,
                                    children: [
                                      IconButton(
                                        onPressed: _busy ? null : () => _aprobar(item),
                                        tooltip: 'Aprobar',
                                        icon: const Icon(Icons.check_circle_outline),
                                      ),
                                      IconButton(
                                        onPressed: _busy ? null : () => _rechazar(item),
                                        tooltip: 'Rechazar',
                                        icon: const Icon(Icons.cancel_outlined),
                                      ),
                                    ],
                                  )
                                : null,
                            onTap: () => _showDetalle(context, item),
                          ),
                        ),
                      );
                    }),
                  const SizedBox(height: 28),
                ],
              ),
            ),
    );
  }

  void _showDetalle(BuildContext context, AdminSalidaTecnicaModel item) {
    final salida = item.salida;

    final tecnicoName = item.tecnico?.nombreCompleto.trim().isNotEmpty == true
        ? item.tecnico!.nombreCompleto
        : 'Técnico';

    final servicioTitle = salida.servicio?.title.trim().isNotEmpty == true
        ? salida.servicio!.title
        : (salida.servicio?.id ?? 'Servicio');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.65,
          minChildSize: 0.45,
          maxChildSize: 0.92,
          builder: (context, controller) {
            return SafeArea(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    servicioTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text('Técnico: $tecnicoName'),
                  const SizedBox(height: 4),
                  Text('Estado: ${salida.estado}'),
                  const SizedBox(height: 4),
                  Text('Vehículo: ${salida.vehiculo?.label ?? '—'}'),
                  const SizedBox(height: 4),
                  Text('KM estimados: ${salida.kmEstimados.toStringAsFixed(2)}'),
                  const SizedBox(height: 4),
                  Text('Litros: ${salida.litrosEstimados.toStringAsFixed(2)}'),
                  const SizedBox(height: 4),
                  Text('Monto combustible: ${salida.montoCombustible.toStringAsFixed(2)}'),
                  if ((salida.observacion ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('Observación: ${salida.observacion}'),
                  ],
                  const SizedBox(height: 16),
                  if (salida.estado == 'FINALIZADA')
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            onPressed: _busy
                                ? null
                                : () {
                                    Navigator.pop(context);
                                    _aprobar(item);
                                  },
                            child: const Text('Aprobar'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _busy
                                ? null
                                : () {
                                    Navigator.pop(context);
                                    _rechazar(item);
                                  },
                            child: const Text('Rechazar'),
                          ),
                        ),
                      ],
                    )
                  else
                    FilledButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cerrar'),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

Future<String?> _askObservacion(
  BuildContext context, {
  required String title,
  required String hint,
  bool requiredText = false,
}) async {
  final ctrl = TextEditingController();
  try {
    return await showDialog<String?>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: ctrl,
            decoration: InputDecoration(hintText: hint),
            minLines: 1,
            maxLines: 4,
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                final v = ctrl.text.trim();
                if (requiredText && v.isEmpty) return;
                Navigator.pop(context, v.isEmpty ? null : v);
              },
              child: const Text('Aceptar'),
            ),
          ],
        );
      },
    );
  } finally {
    ctrl.dispose();
  }
}
