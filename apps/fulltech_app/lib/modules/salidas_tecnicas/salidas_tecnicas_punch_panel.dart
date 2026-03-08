import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/auth/app_role.dart';
import 'application/salidas_tecnicas_controller.dart';
import 'salidas_tecnicas_models.dart';

class SalidasTecnicasPunchPanel extends ConsumerStatefulWidget {
  const SalidasTecnicasPunchPanel({super.key});

  @override
  ConsumerState<SalidasTecnicasPunchPanel> createState() =>
      _SalidasTecnicasPunchPanelState();
}

class _SalidasTecnicasPunchPanelState
    extends ConsumerState<SalidasTecnicasPunchPanel> {
  String? _selectedServicioId;
  String? _selectedVehiculoId;
  String _observacion = '';

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider);
    final state = ref.watch(salidasTecnicasControllerProvider);
    final ctrl = ref.read(salidasTecnicasControllerProvider.notifier);

    final isTecnico = auth.user?.appRole == AppRole.tecnico;
    if (!isTecnico) return const SizedBox.shrink();

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Salidas técnicas',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              onPressed: state.loading ? null : () => ctrl.load(),
              icon: const Icon(Icons.refresh),
              tooltip: 'Actualizar',
            ),
          ],
        ),
        if (state.loadError != null && state.loadError!.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              state.loadError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (state.salidaError != null && state.salidaError!.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              state.salidaError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (state.loading)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: LinearProgressIndicator(),
            ),
          )
        else ...[
          _buildSalidaAbiertaCard(context, state, ctrl),
          const SizedBox(height: 10),
          if (state.abierta == null) ...[
            _buildIniciarCard(
              context,
              state,
              ctrl,
              vehiculos,
              selectedVehiculo,
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildSalidaAbiertaCard(
    BuildContext context,
    SalidasTecnicasState state,
    SalidasTecnicasController ctrl,
  ) {
    final salida = state.abierta;
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
              style: Theme.of(context).textTheme.titleSmall,
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
                    onPressed: state.isMarkingLlegada
                        ? null
                        : () => ctrl.marcarLlegada(salidaId: salida.id),
                    child: const Text('Marcar llegada'),
                  ),
                FilledButton(
                  onPressed: state.isFinalizingSalida
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
              'Registrar salida',
              style: Theme.of(context).textTheme.titleSmall,
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
              onChanged: state.isStartingSalida
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
              onChanged: state.isStartingSalida
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
              enabled: !state.isStartingSalida,
              onChanged: (v) => _observacion = v,
            ),
            if (state.isStartingSalida) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            const SizedBox(height: 12),
            FilledButton(
              onPressed:
                  state.isStartingSalida ||
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
              child: const Text('Registrar'),
            ),
          ],
        ),
      ),
    );
  }
}
