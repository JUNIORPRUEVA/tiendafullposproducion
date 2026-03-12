import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/utils/app_feedback.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../operaciones/data/operations_repository.dart';
import '../operaciones/operations_models.dart';
import 'data/salidas_tecnicas_repository.dart';
import 'salidas_tecnicas_models.dart';

class TecnicoSalidasScreen extends ConsumerStatefulWidget {
  const TecnicoSalidasScreen({super.key});

  @override
  ConsumerState<TecnicoSalidasScreen> createState() =>
      _TecnicoSalidasScreenState();
}

class _TecnicoSalidasScreenState extends ConsumerState<TecnicoSalidasScreen> {
  final TextEditingController _noteController = TextEditingController();

  bool _loading = true;
  bool _submitting = false;
  List<TechVehicle> _vehicles = const [];
  List<TechnicalDeparture> _history = const [];
  List<ServiceModel> _services = const [];
  TechnicalDeparture? _openDeparture;
  String? _selectedVehicleId;
  String? _selectedServiceId;

  SalidasTecnicasRepository get _repo =>
      ref.read(salidasTecnicasRepositoryProvider);

  OperationsRepository get _operationsRepo =>
      ref.read(operationsRepositoryProvider);

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final authUser = ref.read(authStateProvider).user;
    final userId = (authUser?.id ?? '').trim();
    final isTech = (authUser?.role ?? '').toUpperCase() == 'TECNICO';

    if (!isTech) {
      if (!mounted) return;
      setState(() {
        _vehicles = const [];
        _history = const [];
        _services = const [];
        _openDeparture = null;
        _selectedVehicleId = null;
        _selectedServiceId = null;
        _loading = false;
      });
      return;
    }

    if (userId.isEmpty) {
      if (mounted) {
        setState(() => _loading = false);
      }
      return;
    }

    try {
      final results = await Future.wait([
        _repo.listVehicles(),
        _repo.getOpenDeparture(),
        _repo.listHistory(),
        _operationsRepo.listServices(assignedTo: userId, page: 1, pageSize: 80),
      ]);

      if (!mounted) return;

      final vehicles = results[0] as List<TechVehicle>;
      final openDeparture = results[1] as TechnicalDeparture?;
      final history = results[2] as List<TechnicalDeparture>;
      final servicesPage = results[3] as ServicesPageModel;
      final availableServices = servicesPage.items
          .where(_isServiceEligibleForDeparture)
          .toList(growable: false);

      setState(() {
        _vehicles = vehicles;
        _openDeparture = openDeparture;
        _history = history;
        _services = availableServices;
        _selectedVehicleId = _resolveSelectedVehicleId(vehicles);
        _selectedServiceId = _resolveSelectedServiceId(availableServices);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      await AppFeedback.showError(
        context,
        'No se pudo cargar salidas técnicas: $e',
      );
    }
  }

  bool _isServiceEligibleForDeparture(ServiceModel service) {
    final status = service.status.trim().toLowerCase();
    return status != 'completed' && status != 'closed' && status != 'cancelled';
  }

  String? _resolveSelectedVehicleId(List<TechVehicle> vehicles) {
    if (_selectedVehicleId != null &&
        vehicles.any((vehicle) => vehicle.id == _selectedVehicleId)) {
      return _selectedVehicleId;
    }

    if (_openDeparture?.vehiculo != null) {
      return _openDeparture!.vehiculo!.id;
    }

    final preferred = vehicles.cast<TechVehicle?>().firstWhere(
      (vehicle) => vehicle?.esEmpresa == false,
      orElse: () => vehicles.isEmpty ? null : vehicles.first,
    );
    return preferred?.id;
  }

  String? _resolveSelectedServiceId(List<ServiceModel> services) {
    final openServiceId = _openDeparture?.servicio?.id;
    if (openServiceId != null) {
      return openServiceId;
    }
    if (_selectedServiceId != null &&
        services.any((service) => service.id == _selectedServiceId)) {
      return _selectedServiceId;
    }
    return services.isEmpty ? null : services.first.id;
  }

  Future<void> _startDeparture() async {
    final vehicle = _vehicles.cast<TechVehicle?>().firstWhere(
      (item) => item?.id == _selectedVehicleId,
      orElse: () => null,
    );
    final service = _services.cast<ServiceModel?>().firstWhere(
      (item) => item?.id == _selectedServiceId,
      orElse: () => null,
    );

    if (vehicle == null) {
      await AppFeedback.showError(
        context,
        'Selecciona un vehículo para iniciar la salida.',
      );
      return;
    }
    if (service == null) {
      await AppFeedback.showError(context, 'Selecciona un servicio asignado.');
      return;
    }

    final position = await _capturePosition();
    if (position == null) return;

    await _runAction(() async {
      await _repo.startDeparture(
        servicioId: service.id,
        vehiculoId: vehicle.id,
        esVehiculoPropio: !vehicle.esEmpresa,
        latSalida: position.latitude,
        lngSalida: position.longitude,
        observacion: _noteController.text,
      );
      _noteController.clear();
      await _load();
      if (!mounted) return;
      await AppFeedback.showInfo(
        context,
        'Salida técnica iniciada correctamente.',
      );
    });
  }

  Future<void> _markArrival() async {
    final openDeparture = _openDeparture;
    if (openDeparture == null) return;
    final position = await _capturePosition();
    if (position == null) return;

    await _runAction(() async {
      await _repo.markArrival(
        salidaId: openDeparture.id,
        latLlegada: position.latitude,
        lngLlegada: position.longitude,
        observacion: _noteController.text,
      );
      _noteController.clear();
      await _load();
      if (!mounted) return;
      await AppFeedback.showInfo(context, 'Llegada registrada.');
    });
  }

  Future<void> _finishDeparture() async {
    final openDeparture = _openDeparture;
    if (openDeparture == null) return;
    final position = await _capturePosition();
    if (position == null) return;

    await _runAction(() async {
      await _repo.finishDeparture(
        salidaId: openDeparture.id,
        latFinal: position.latitude,
        lngFinal: position.longitude,
        observacion: _noteController.text,
      );
      _noteController.clear();
      await _load();
      if (!mounted) return;
      await AppFeedback.showInfo(context, 'Salida técnica finalizada.');
    });
  }

  Future<void> _openVehicleDialog({TechVehicle? vehicle}) async {
    final result = await showDialog<_VehicleFormValue>(
      context: context,
      builder: (context) => _VehicleDialog(vehicle: vehicle),
    );

    if (result == null) return;

    await _runAction(() async {
      if (vehicle == null) {
        await _repo.createVehicle(result.toPayload());
      } else {
        await _repo.updateVehicle(vehicle.id, result.toPayload());
      }
      await _load();
      if (!mounted) return;
      await AppFeedback.showInfo(
        context,
        vehicle == null
            ? 'Vehículo guardado correctamente.'
            : 'Vehículo actualizado correctamente.',
      );
    });
  }

  Future<void> _runAction(Future<void> Function() action) async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      await action();
    } catch (e) {
      if (!mounted) return;
      await AppFeedback.showError(context, e.toString());
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<Position?> _capturePosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return null;
      await AppFeedback.showError(
        context,
        'Activa la ubicación del dispositivo para continuar.',
      );
      return null;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (!mounted) return null;
      await AppFeedback.showError(
        context,
        'La app necesita permiso de ubicación para registrar la salida.',
      );
      return null;
    }

    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 12),
      );
    } catch (e) {
      if (!mounted) return null;
      await AppFeedback.showError(
        context,
        'No se pudo obtener la ubicación actual: $e',
      );
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider);
    final currentUser = auth.user;
    final isTech = (currentUser?.role ?? '').toUpperCase() == 'TECNICO';

    return Scaffold(
      appBar: const CustomAppBar(title: 'Salidas técnicas', showLogo: false),
      drawer: buildAdaptiveDrawer(context, currentUser: currentUser),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : !isTech
          ? ListView(
              padding: const EdgeInsets.all(16),
              children: const [
                Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Acceso solo para técnicos',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Esta pantalla usa endpoints exclusivos del rol técnico para gestionar vehículos propios y salidas de campo. Si entras con un usuario administrador o de otro rol, la app no debe intentar consumir esas rutas.',
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Si necesitas una vista administrativa de salidas técnicas, esa debe conectarse a los endpoints admin del backend, no a los endpoints de técnico autenticado.',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildSummaryCard(context),
                  const SizedBox(height: 16),
                  _buildActiveDepartureCard(context),
                  const SizedBox(height: 16),
                  _buildVehiclesCard(context),
                  const SizedBox(height: 16),
                  _buildHistoryCard(context),
                ],
              ),
            ),
    );
  }

  Widget _buildSummaryCard(BuildContext context) {
    final ownVehicles = _vehicles.where((vehicle) => !vehicle.esEmpresa).length;
    final companyVehicles = _vehicles
        .where((vehicle) => vehicle.esEmpresa)
        .length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _MetricChip(
              icon: Icons.directions_car_outlined,
              label: 'Vehículos propios',
              value: '$ownVehicles',
            ),
            _MetricChip(
              icon: Icons.business_outlined,
              label: 'Vehículos empresa',
              value: '$companyVehicles',
            ),
            _MetricChip(
              icon: Icons.engineering_outlined,
              label: 'Servicios disponibles',
              value: '${_services.length}',
            ),
            _MetricChip(
              icon: Icons.local_gas_station_outlined,
              label: 'Reembolso actual',
              value: _openDeparture == null
                  ? 'RD\$0'
                  : 'RD\$' +
                        _openDeparture!.montoCombustible.toStringAsFixed(2),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveDepartureCard(BuildContext context) {
    final theme = Theme.of(context);
    final openDeparture = _openDeparture;

    if (openDeparture != null) {
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
                      'Salida abierta',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  _StateBadge(label: openDeparture.estado),
                ],
              ),
              const SizedBox(height: 12),
              _InfoLine(
                'Servicio',
                openDeparture.servicio?.title ?? 'Sin servicio',
              ),
              _InfoLine(
                'Vehículo',
                openDeparture.vehiculo?.displayName ?? 'Sin vehículo',
              ),
              _InfoLine(
                'Reembolso estimado',
                'RD\$' + openDeparture.montoCombustible.toStringAsFixed(2),
              ),
              if ((openDeparture.kmEstimados ?? 0) > 0)
                _InfoLine(
                  'Distancia estimada',
                  '${openDeparture.kmEstimados!.toStringAsFixed(2)} km',
                ),
              if ((openDeparture.observacion ?? '').trim().isNotEmpty)
                _InfoLine('Observación', openDeparture.observacion!.trim()),
              const SizedBox(height: 16),
              TextField(
                controller: _noteController,
                minLines: 2,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Nota opcional',
                  hintText: 'Ej. Llegada al local, regreso a base...',
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  if (openDeparture.canMarkArrival)
                    FilledButton.icon(
                      onPressed: _submitting ? null : _markArrival,
                      icon: const Icon(Icons.location_on_outlined),
                      label: const Text('Marcar llegada'),
                    ),
                  FilledButton.icon(
                    onPressed: _submitting ? null : _finishDeparture,
                    icon: const Icon(Icons.flag_outlined),
                    label: const Text('Finalizar salida'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Iniciar salida técnica',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Selecciona el servicio asignado y el vehículo. Si el vehículo es propio, el combustible se calculará para nómina cuando la salida sea aprobada y pagada.',
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _selectedServiceId,
              decoration: const InputDecoration(labelText: 'Servicio asignado'),
              items: _services
                  .map(
                    (service) => DropdownMenuItem<String>(
                      value: service.id,
                      child: Text(service.title),
                    ),
                  )
                  .toList(growable: false),
              onChanged: _services.isEmpty
                  ? null
                  : (value) => setState(() => _selectedServiceId = value),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _selectedVehicleId,
              decoration: const InputDecoration(labelText: 'Vehículo'),
              items: _vehicles
                  .map(
                    (vehicle) => DropdownMenuItem<String>(
                      value: vehicle.id,
                      child: Text(
                        vehicle.esEmpresa
                            ? '${vehicle.displayName} · Empresa'
                            : '${vehicle.displayName} · Propio',
                      ),
                    ),
                  )
                  .toList(growable: false),
              onChanged: _vehicles.isEmpty
                  ? null
                  : (value) => setState(() => _selectedVehicleId = value),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteController,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Observación',
                hintText: 'Opcional, para registrar contexto de la salida',
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _submitting || _vehicles.isEmpty || _services.isEmpty
                    ? null
                    : _startDeparture,
                icon: const Icon(Icons.play_arrow_outlined),
                label: const Text('Iniciar salida'),
              ),
            ),
            if (_vehicles.isEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Debes registrar al menos un vehículo antes de iniciar una salida.',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildVehiclesCard(BuildContext context) {
    final ownVehicles = _vehicles
        .where((vehicle) => !vehicle.esEmpresa)
        .toList();
    final companyVehicles = _vehicles
        .where((vehicle) => vehicle.esEmpresa)
        .toList();

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
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _submitting ? null : () => _openVehicleDialog(),
                  icon: const Icon(Icons.add),
                  label: const Text('Agregar propio'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Solo los vehículos propios generan reembolso de combustible. Los de empresa se pueden usar para la salida, pero no generan pago.',
            ),
            const SizedBox(height: 16),
            if (ownVehicles.isNotEmpty) ...[
              const Text(
                'Vehículos propios',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              ...ownVehicles.map(
                (vehicle) => _VehicleTile(
                  vehicle: vehicle,
                  trailing: IconButton(
                    tooltip: 'Editar vehículo',
                    onPressed: _submitting
                        ? null
                        : () => _openVehicleDialog(vehicle: vehicle),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                ),
              ),
            ] else
              const Text('Aún no has registrado vehículos propios.'),
            if (companyVehicles.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text(
                'Vehículos de empresa',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              ...companyVehicles.map(
                (vehicle) => _VehicleTile(vehicle: vehicle),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Historial reciente',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            if (_history.isEmpty)
              const Text('Todavía no hay salidas registradas.')
            else
              ..._history
                  .take(15)
                  .map(
                    (departure) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.route_outlined),
                      title: Text(departure.servicio?.title ?? 'Servicio'),
                      subtitle: Text(
                        [
                          departure.vehiculo?.displayName,
                          departure.fecha == null
                              ? null
                              : DateFormat(
                                  'dd/MM/yyyy HH:mm',
                                ).format(departure.fecha!.toLocal()),
                        ].whereType<String>().join(' · '),
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _StateBadge(label: departure.estado),
                          const SizedBox(height: 6),
                          Text(
                            'RD\$' +
                                departure.montoCombustible.toStringAsFixed(2),
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

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 170),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodySmall),
                Text(
                  value,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
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

class _StateBadge extends StatelessWidget {
  const _StateBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final upper = label.toUpperCase();
    final color = switch (upper) {
      'INICIADA' => Colors.orange,
      'LLEGADA' => Colors.blue,
      'FINALIZADA' => Colors.grey,
      'APROBADA' => Colors.green,
      'PAGADA' => Colors.teal,
      'RECHAZADA' => Colors.red,
      _ => Theme.of(context).colorScheme.primary,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        upper,
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RichText(
        text: TextSpan(
          style: Theme.of(context).textTheme.bodyMedium,
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}

class _VehicleTile extends StatelessWidget {
  const _VehicleTile({required this.vehicle, this.trailing});

  final TechVehicle vehicle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final fuel = vehicle.rendimientoKmLitro == null
        ? 'Sin rendimiento'
        : '${vehicle.rendimientoKmLitro!.toStringAsFixed(2)} km/L';
    final tank = vehicle.capacidadTanqueLitros == null
        ? null
        : '${vehicle.capacidadTanqueLitros!.toStringAsFixed(2)} L tanque';

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        vehicle.esEmpresa
            ? Icons.business_outlined
            : Icons.two_wheeler_outlined,
      ),
      title: Text(vehicle.displayName),
      subtitle: Text(
        [vehicle.tipo, vehicle.combustibleTipo, fuel, tank]
            .whereType<String>()
            .where((value) => value.trim().isNotEmpty)
            .join(' · '),
      ),
      trailing: trailing,
    );
  }
}

class _VehicleDialog extends StatefulWidget {
  const _VehicleDialog({this.vehicle});

  final TechVehicle? vehicle;

  @override
  State<_VehicleDialog> createState() => _VehicleDialogState();
}

class _VehicleDialogState extends State<_VehicleDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _typeController;
  late final TextEditingController _brandController;
  late final TextEditingController _modelController;
  late final TextEditingController _plateController;
  late final TextEditingController _fuelTypeController;
  late final TextEditingController _performanceController;
  late final TextEditingController _tankController;
  bool _active = true;

  @override
  void initState() {
    super.initState();
    final vehicle = widget.vehicle;
    _nameController = TextEditingController(text: vehicle?.nombre ?? '');
    _typeController = TextEditingController(text: vehicle?.tipo ?? 'motor');
    _brandController = TextEditingController(text: vehicle?.marca ?? '');
    _modelController = TextEditingController(text: vehicle?.modelo ?? '');
    _plateController = TextEditingController(text: vehicle?.placa ?? '');
    _fuelTypeController = TextEditingController(
      text: vehicle?.combustibleTipo ?? 'gasolina_regular',
    );
    _performanceController = TextEditingController(
      text: vehicle?.rendimientoKmLitro?.toString() ?? '',
    );
    _tankController = TextEditingController(
      text: vehicle?.capacidadTanqueLitros?.toString() ?? '',
    );
    _active = vehicle?.activo ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _typeController.dispose();
    _brandController.dispose();
    _modelController.dispose();
    _plateController.dispose();
    _fuelTypeController.dispose();
    _performanceController.dispose();
    _tankController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.vehicle == null ? 'Agregar vehículo propio' : 'Editar vehículo',
      ),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Nombre o alias'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _typeController,
                decoration: const InputDecoration(
                  labelText: 'Tipo',
                  hintText: 'motor, carro, jeepeta, guagua...',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _brandController,
                decoration: const InputDecoration(labelText: 'Marca'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _modelController,
                decoration: const InputDecoration(labelText: 'Modelo'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _plateController,
                decoration: const InputDecoration(
                  labelText: 'Placa o identificación',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _fuelTypeController,
                decoration: const InputDecoration(
                  labelText: 'Tipo de combustible',
                  hintText: 'gasolina_regular, gasolina_premium, diesel...',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _performanceController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Rendimiento km/L',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _tankController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Capacidad tanque (L)',
                ),
              ),
              if (widget.vehicle != null) ...[
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  value: _active,
                  title: const Text('Vehículo activo'),
                  contentPadding: EdgeInsets.zero,
                  onChanged: (value) => setState(() => _active = value),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final value = _VehicleFormValue(
              nombre: _nameController.text,
              tipo: _typeController.text,
              marca: _brandController.text,
              modelo: _modelController.text,
              placa: _plateController.text,
              combustibleTipo: _fuelTypeController.text,
              rendimientoKmLitro: _performanceController.text,
              capacidadTanqueLitros: _tankController.text,
              activo: _active,
            );
            if (!value.isValid) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Completa nombre, tipo, combustible y rendimiento.',
                  ),
                ),
              );
              return;
            }
            Navigator.pop(context, value);
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

class _VehicleFormValue {
  const _VehicleFormValue({
    required this.nombre,
    required this.tipo,
    required this.marca,
    required this.modelo,
    required this.placa,
    required this.combustibleTipo,
    required this.rendimientoKmLitro,
    required this.capacidadTanqueLitros,
    required this.activo,
  });

  final String nombre;
  final String tipo;
  final String marca;
  final String modelo;
  final String placa;
  final String combustibleTipo;
  final String rendimientoKmLitro;
  final String capacidadTanqueLitros;
  final bool activo;

  bool get isValid {
    return nombre.trim().isNotEmpty &&
        tipo.trim().isNotEmpty &&
        combustibleTipo.trim().isNotEmpty &&
        (double.tryParse(rendimientoKmLitro.trim()) ?? 0) > 0;
  }

  Map<String, dynamic> toPayload() {
    final payload = <String, dynamic>{
      'nombre': nombre.trim(),
      'tipo': tipo.trim(),
      'combustibleTipo': combustibleTipo.trim(),
      'rendimientoKmLitro': double.tryParse(rendimientoKmLitro.trim()),
      'activo': activo,
    };

    if (marca.trim().isNotEmpty) payload['marca'] = marca.trim();
    if (modelo.trim().isNotEmpty) payload['modelo'] = modelo.trim();
    if (placa.trim().isNotEmpty) payload['placa'] = placa.trim();
    final tank = double.tryParse(capacidadTanqueLitros.trim());
    if (tank != null && tank > 0) payload['capacidadTanqueLitros'] = tank;
    return payload;
  }
}
