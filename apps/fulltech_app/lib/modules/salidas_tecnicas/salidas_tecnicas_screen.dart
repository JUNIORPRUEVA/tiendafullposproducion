import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
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
  void initState() {
    super.initState();
    // Log y SnackBar opcional: si prefieres solo texto, quítalo.
    ref.listen<SalidasTecnicasState>(salidasTecnicasControllerProvider, (
      previous,
      next,
    ) {
      final prevMsg =
          (previous?.vehicleError ??
                  previous?.salidaError ??
                  previous?.loadError)
              ?.trim();
      final nextMsg = (next.vehicleError ?? next.salidaError ?? next.loadError)
          ?.trim();
      if (nextMsg == null || nextMsg.isEmpty) return;
      if (nextMsg == prevMsg) return;
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(nextMsg)));
    });
  }

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
                  if (state.loadError != null &&
                      state.loadError!.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        state.loadError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  if (state.isStartingSalida ||
                      state.isSavingVehicle ||
                      state.isMarkingLlegada ||
                      state.isFinalizingSalida ||
                      state.loadingVehiculos)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: LinearProgressIndicator(),
                    ),

                  if (kDebugMode &&
                      ((state.isStartingSalida ||
                              state.isSavingVehicle ||
                              state.isMarkingLlegada ||
                              state.isFinalizingSalida ||
                              state.loadingVehiculos) ||
                          (state.debugLastError != null &&
                              state.debugLastError!.trim().isNotEmpty)))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Diagnóstico: ${state.debugStage ?? '-'}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          if (state.debugLastError != null &&
                              state.debugLastError!.trim().isNotEmpty)
                            Text(
                              'Último error: ${state.debugLastError}',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color:
                                        Theme.of(context).colorScheme.error,
                                  ),
                            ),
                        ],
                      ),
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
              child: const Text('Iniciar'),
            ),
            if (state.salidaError != null &&
                state.salidaError!.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  state.salidaError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
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
                  onPressed: state.isSavingVehicle
                      ? null
                      : () async {
                          debugPrint(
                            '[SalidasTecnicasScreen] Abriendo formulario de nuevo vehículo',
                          );
                          final created = await _showCrearVehiculoDialog(
                            context,
                            ctrl,
                          );
                          if (!mounted) return;
                          if (created == null) return;
                          setState(() => _selectedVehiculoId = created.id);
                        },
                  child: const Text('Nuevo'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (state.vehicleError != null &&
                state.vehicleError!.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  state.vehicleError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
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

    final screenHeight = MediaQuery.sizeOf(context).height;
    final listHeight = (screenHeight * 0.42).clamp(220.0, 520.0);

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
              SizedBox(
                height: listHeight,
                child: ListView.separated(
                  primary: false,
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final s = items[index];
                    final title = s.servicio?.title ?? 'Servicio';
                    final vehiculo = s.vehiculo?.label ?? '';
                    final monto = s.montoCombustible;
                    return ListTile(
                      dense: true,
                      title: Text(title),
                      subtitle: Text(
                        'Estado: ${s.estado}${vehiculo.isEmpty ? '' : ' • $vehiculo'}',
                      ),
                      trailing:
                          monto > 0 ? Text(monto.toStringAsFixed(2)) : null,
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<VehiculoModel?> _showCrearVehiculoDialog(
    BuildContext context,
    SalidasTecnicasController ctrl,
  ) async {
    final formKey = GlobalKey<FormState>();
    final nombreCtrl = TextEditingController();
    final tipoCtrl = TextEditingController();
    final placaCtrl = TextEditingController();
    final combustibleCtrl = TextEditingController();
    final rendimientoCtrl = TextEditingController();

    bool esEmpresa = false;
    bool savingLocal = false;
    String? localError;

    String? validateRequired(String? v, String label) {
      if ((v ?? '').trim().isEmpty) return '$label es requerido';
      return null;
    }

    String? validateRendimiento(String? v) {
      if (esEmpresa) return null;
      final raw = (v ?? '').trim();
      if (raw.isEmpty) return 'Rendimiento km/l es requerido';
      final parsed = double.tryParse(raw.replaceAll(',', '.'));
      if (parsed == null || parsed <= 0) return 'Rendimiento km/l inválido';
      return null;
    }

    try {
      return await showDialog<VehiculoModel>(
        context: context,
        barrierDismissible: !savingLocal,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (dialogContext, setDialogState) {
              Future<void> submit() async {
                setDialogState(() => localError = null);
                final ok = formKey.currentState?.validate() ?? false;
                if (!ok) {
                  setDialogState(
                    () => localError = 'Revisa los campos marcados',
                  );
                  return;
                }

                setDialogState(() => savingLocal = true);
                final rendimiento = double.tryParse(
                  rendimientoCtrl.text.trim().replaceAll(',', '.'),
                );

                try {
                  debugPrint(
                    '[SalidasTecnicasScreen] Validación OK. Guardando vehículo...',
                  );
                  final created = await ctrl.crearVehiculo(
                    nombre: nombreCtrl.text,
                    tipo: tipoCtrl.text,
                    placa: placaCtrl.text,
                    combustibleTipo: combustibleCtrl.text,
                    rendimientoKmLitro: rendimiento,
                    esEmpresa: esEmpresa,
                  );
                  if (!dialogContext.mounted) return;
                  if (created == null) {
                    // El controller ya puso vehicleError; mostramos uno local si hace falta.
                    setDialogState(() {
                      localError =
                          localError ?? 'No se pudo guardar el vehículo';
                    });
                    return;
                  }
                  Navigator.pop(dialogContext, created);
                } catch (e, st) {
                  debugPrint(
                    '[SalidasTecnicasScreen] Error submit vehículo: $e',
                  );
                  debugPrintStack(stackTrace: st);
                  if (!dialogContext.mounted) return;
                  setDialogState(
                    () => localError = 'Error inesperado al guardar',
                  );
                } finally {
                  if (!dialogContext.mounted) return;
                  setDialogState(() => savingLocal = false);
                }
              }

              return AlertDialog(
                title: const Text('Nuevo vehículo'),
                content: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Vehículo de empresa'),
                          value: esEmpresa,
                          onChanged: savingLocal
                              ? null
                              : (v) {
                                  setDialogState(() {
                                    esEmpresa = v;
                                    localError = null;
                                  });
                                },
                        ),
                        TextFormField(
                          controller: nombreCtrl,
                          enabled: !savingLocal,
                          decoration: const InputDecoration(
                            labelText: 'Nombre',
                          ),
                          validator: (v) => validateRequired(v, 'Nombre'),
                        ),
                        TextFormField(
                          controller: tipoCtrl,
                          enabled: !savingLocal,
                          decoration: const InputDecoration(labelText: 'Tipo'),
                          validator: (v) => validateRequired(v, 'Tipo'),
                        ),
                        TextFormField(
                          controller: placaCtrl,
                          enabled: !savingLocal,
                          decoration: const InputDecoration(
                            labelText: 'Placa (opcional)',
                          ),
                        ),
                        TextFormField(
                          controller: combustibleCtrl,
                          enabled: !savingLocal,
                          decoration: const InputDecoration(
                            labelText: 'Combustible (ej: GASOLINA)',
                          ),
                          validator: (v) => validateRequired(v, 'Combustible'),
                        ),
                        TextFormField(
                          controller: rendimientoCtrl,
                          enabled: !savingLocal && !esEmpresa,
                          decoration: InputDecoration(
                            labelText:
                                'Rendimiento km/l${esEmpresa ? ' (no aplica)' : ''}',
                          ),
                          keyboardType: TextInputType.number,
                          validator: validateRendimiento,
                        ),
                        if (localError != null && localError!.trim().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(
                              localError!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        if (savingLocal)
                          const Padding(
                            padding: EdgeInsets.only(top: 12),
                            child: LinearProgressIndicator(),
                          ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: savingLocal
                        ? null
                        : () => Navigator.pop(dialogContext),
                    child: const Text('Cancelar'),
                  ),
                  FilledButton(
                    onPressed: savingLocal ? null : submit,
                    child: const Text('Guardar'),
                  ),
                ],
              );
            },
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
