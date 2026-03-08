import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/auth/app_role.dart';
import '../../core/widgets/app_drawer.dart';
import 'application/salidas_tecnicas_controller.dart';
import 'salidas_tecnicas_models.dart';

class SalidasTecnicasScreen extends ConsumerStatefulWidget {
  const SalidasTecnicasScreen({super.key});

  @override
  ConsumerState<SalidasTecnicasScreen> createState() =>
      _SalidasTecnicasScreenState();
}

class _SalidasTecnicasScreenState extends ConsumerState<SalidasTecnicasScreen> {
  String? _selectedServicioId;
  String? _selectedVehiculoId;
  String _observacion = '';

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider);
    final state = ref.watch(salidasTecnicasControllerProvider);
    final ctrl = ref.read(salidasTecnicasControllerProvider.notifier);

    final user = auth.user;
    final isTecnico = user?.appRole == AppRole.tecnico;

    final vehiculos = state.vehiculos.where((v) => v.activo).toList();

    VehiculoModel? selectedVehiculo;
    if (_selectedVehiculoId != null) {
      for (final v in vehiculos) {
        if (v.id == _selectedVehiculoId) {
          selectedVehiculo = v;
          break;
        }
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Salidas técnicas'),
        actions: [
          IconButton(
            onPressed: state.loading ? null : () => ctrl.load(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      drawer: AppDrawer(currentUser: user),
      body: !isTecnico
          ? const Center(child: Text('Solo disponible para técnicos'))
          : RefreshIndicator(
              onRefresh: () => ctrl.load(),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (state.error != null && state.error!.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        state.error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  if (state.busy)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: LinearProgressIndicator(),
                    ),

                  _buildSalidaAbiertaCard(context, state, ctrl),
                  const SizedBox(height: 12),

                  if (state.abierta == null) ...[
                    _buildIniciarCard(
                      context,
                      state,
                      ctrl,
                      vehiculos,
                      selectedVehiculo,
                    ),
                    const SizedBox(height: 12),
                  ],

                  _buildVehiculosCard(context, state, ctrl, vehiculos),
                  const SizedBox(height: 12),

                  _buildHistorial(context, state),
                  const SizedBox(height: 48),
                ],
              ),
            ),
    );
  }

  Widget _buildSalidaAbiertaCard(
    BuildContext context,
    SalidasTecnicasState state,
    SalidasTecnicasController ctrl,
  ) {
    final salida = state.abierta;
    if (state.loading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: LinearProgressIndicator(),
        ),
      );
    }

    if (salida == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('No tienes salida abierta.'),
        ),
      );
    }

    final servicioTitle = salida.servicio?.title ?? 'Servicio';
    final vehiculoLabel = salida.vehiculo?.label ?? 'Vehículo';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Salida abierta',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(servicioTitle, style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 4),
            Text('Vehículo: $vehiculoLabel'),
            const SizedBox(height: 4),
            Text('Estado: ${salida.estado}'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                if (salida.estado == 'INICIADA')
                  FilledButton(
                    onPressed: state.busy
                        ? null
                        : () => ctrl.marcarLlegada(salidaId: salida.id),
                    child: const Text('Marcar llegada'),
                  ),
                FilledButton(
                  onPressed: state.busy
                      ? null
                      : () => ctrl.finalizar(salidaId: salida.id),
                  child: const Text('Finalizar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIniciarCard(
    BuildContext context,
    SalidasTecnicasState state,
    SalidasTecnicasController ctrl,
    List<VehiculoModel> vehiculos,
    VehiculoModel? selectedVehiculo,
  ) {
    final servicios = state.servicios;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Iniciar salida',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _selectedServicioId,
              items: servicios
                  .map(
                    (s) => DropdownMenuItem(
                      value: s.id,
                      child: Text(s.title.isEmpty ? s.id : s.title),
                    ),
                  )
                  .toList(),
              onChanged: state.busy
                  ? null
                  : (v) => setState(() => _selectedServicioId = v),
              decoration: const InputDecoration(labelText: 'Servicio asignado'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _selectedVehiculoId,
              items: vehiculos
                  .map(
                    (v) => DropdownMenuItem(value: v.id, child: Text(v.label)),
                  )
                  .toList(),
              onChanged: state.busy
                  ? null
                  : (v) => setState(() => _selectedVehiculoId = v),
              decoration: const InputDecoration(labelText: 'Vehículo'),
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Observación (opcional)',
              ),
              minLines: 1,
              maxLines: 3,
              enabled: !state.busy,
              onChanged: (v) => _observacion = v,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed:
                  state.busy ||
                      _selectedServicioId == null ||
                      selectedVehiculo == null
                  ? null
                  : () => ctrl.iniciarSalida(
                      servicioId: _selectedServicioId!,
                      vehiculo: selectedVehiculo,
                      observacion: _observacion.trim().isEmpty
                          ? null
                          : _observacion.trim(),
                    ),
              child: const Text('Iniciar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVehiculosCard(
    BuildContext context,
    SalidasTecnicasState state,
    SalidasTecnicasController ctrl,
    List<VehiculoModel> vehiculos,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Vehículos',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton(
                  onPressed: state.busy
                      ? null
                      : () async {
                          final created = await _showCrearVehiculoDialog(
                            context,
                          );
                          if (created == null) return;
                          await ctrl.crearVehiculoPropio(
                            nombre: created.nombre,
                            tipo: created.tipo,
                            placa: created.placa,
                            combustibleTipo: created.combustibleTipo,
                            rendimientoKmLitro: created.rendimientoKmLitro,
                          );
                        },
                  child: const Text('Nuevo'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (vehiculos.isEmpty)
              const Text('No hay vehículos disponibles.')
            else
              ...vehiculos.map(
                (v) => ListTile(
                  dense: true,
                  title: Text(v.label),
                  subtitle: Text(v.esEmpresa ? 'Empresa' : 'Propio'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistorial(BuildContext context, SalidasTecnicasState state) {
    final items = state.historial;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Historial', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (items.isEmpty)
              const Text('Sin registros.')
            else
              ...items.map((s) {
                final title = s.servicio?.title ?? 'Servicio';
                final vehiculo = s.vehiculo?.label ?? '';
                final monto = s.montoCombustible;
                return ListTile(
                  dense: true,
                  title: Text(title),
                  subtitle: Text(
                    'Estado: ${s.estado}${vehiculo.isEmpty ? '' : ' • $vehiculo'}',
                  ),
                  trailing: monto > 0 ? Text(monto.toStringAsFixed(2)) : null,
                );
              }),
          ],
        ),
      ),
    );
  }

  Future<_VehiculoDraft?> _showCrearVehiculoDialog(BuildContext context) async {
    final nombreCtrl = TextEditingController();
    final tipoCtrl = TextEditingController();
    final placaCtrl = TextEditingController();
    final combustibleCtrl = TextEditingController();
    final rendimientoCtrl = TextEditingController();

    try {
      return showDialog<_VehiculoDraft>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: const Text('Nuevo vehículo propio'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nombreCtrl,
                    decoration: const InputDecoration(labelText: 'Nombre'),
                  ),
                  TextField(
                    controller: tipoCtrl,
                    decoration: const InputDecoration(labelText: 'Tipo'),
                  ),
                  TextField(
                    controller: placaCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Placa (opcional)',
                    ),
                  ),
                  TextField(
                    controller: combustibleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Combustible (ej: GASOLINA)',
                    ),
                  ),
                  TextField(
                    controller: rendimientoCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Rendimiento km/l',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () {
                  final rendimiento = double.tryParse(
                    rendimientoCtrl.text.trim(),
                  );
                  if (nombreCtrl.text.trim().isEmpty ||
                      tipoCtrl.text.trim().isEmpty ||
                      combustibleCtrl.text.trim().isEmpty ||
                      rendimiento == null ||
                      rendimiento <= 0) {
                    return;
                  }
                  Navigator.pop(
                    ctx,
                    _VehiculoDraft(
                      nombre: nombreCtrl.text.trim(),
                      tipo: tipoCtrl.text.trim(),
                      placa: placaCtrl.text.trim().isEmpty
                          ? null
                          : placaCtrl.text.trim(),
                      combustibleTipo: combustibleCtrl.text.trim(),
                      rendimientoKmLitro: rendimiento,
                    ),
                  );
                },
                child: const Text('Crear'),
              ),
            ],
          );
        },
      );
    } finally {
      nombreCtrl.dispose();
      tipoCtrl.dispose();
      placaCtrl.dispose();
      combustibleCtrl.dispose();
      rendimientoCtrl.dispose();
    }
  }
}

class _VehiculoDraft {
  final String nombre;
  final String tipo;
  final String? placa;
  final String combustibleTipo;
  final double rendimientoKmLitro;

  const _VehiculoDraft({
    required this.nombre,
    required this.tipo,
    required this.placa,
    required this.combustibleTipo,
    required this.rendimientoKmLitro,
  });
}
