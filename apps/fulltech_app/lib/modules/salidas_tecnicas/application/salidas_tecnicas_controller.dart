import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/errors/api_exception.dart';
import '../../../features/operaciones/data/operations_repository.dart';
import '../../../features/operaciones/operations_models.dart';
import '../salidas_tecnicas_models.dart';
import '../data/salidas_tecnicas_repository.dart';

class SalidasTecnicasState {
  final bool loading;
  final bool busy;
  final String? error;
  final List<VehiculoModel> vehiculos;
  final SalidaTecnicaModel? abierta;
  final List<SalidaTecnicaModel> historial;
  final List<ServiceMiniModel> servicios;

  const SalidasTecnicasState({
    required this.loading,
    required this.busy,
    required this.error,
    required this.vehiculos,
    required this.abierta,
    required this.historial,
    required this.servicios,
  });

  factory SalidasTecnicasState.initial() => const SalidasTecnicasState(
        loading: true,
        busy: false,
        error: null,
        vehiculos: [],
        abierta: null,
        historial: [],
        servicios: [],
      );

  SalidasTecnicasState copyWith({
    bool? loading,
    bool? busy,
    String? error,
    List<VehiculoModel>? vehiculos,
    SalidaTecnicaModel? abierta,
    List<SalidaTecnicaModel>? historial,
    List<ServiceMiniModel>? servicios,
  }) {
    return SalidasTecnicasState(
      loading: loading ?? this.loading,
      busy: busy ?? this.busy,
      error: error,
      vehiculos: vehiculos ?? this.vehiculos,
      abierta: abierta ?? this.abierta,
      historial: historial ?? this.historial,
      servicios: servicios ?? this.servicios,
    );
  }
}

final salidasTecnicasControllerProvider =
    StateNotifierProvider<SalidasTecnicasController, SalidasTecnicasState>((ref) {
  return SalidasTecnicasController(
    ref,
    ref.watch(salidasTecnicasRepositoryProvider),
    ref.watch(operationsRepositoryProvider),
  );
});

class SalidasTecnicasController extends StateNotifier<SalidasTecnicasState> {
  final Ref _ref;
  final SalidasTecnicasRepository _repo;
  final OperationsRepository _ops;

  SalidasTecnicasController(this._ref, this._repo, this._ops)
      : super(SalidasTecnicasState.initial()) {
    load();
  }

  Future<void> load() async {
    final auth = _ref.read(authStateProvider);
    final role = (auth.user?.role ?? '').toUpperCase();
    if (!auth.isAuthenticated || role != 'TECNICO') {
      state = state.copyWith(loading: false, error: 'Solo disponible para técnicos');
      return;
    }

    state = state.copyWith(loading: true, error: null);
    try {
      final results = await Future.wait([
        _repo.listVehiculos(),
        _repo.getSalidaAbierta(),
        _repo.listHistorial(),
        _ops.listServices(pageSize: 50),
      ]);

      final vehiculos = results[0] as List<VehiculoModel>;
      final abierta = results[1] as SalidaTecnicaModel?;
      final historial = results[2] as List<SalidaTecnicaModel>;
      final servicesPage = results[3] as ServicesPageModel;

      final servicios = servicesPage.items
          .map(
            (s) => ServiceMiniModel(
              id: s.id,
              title: s.title,
              status: s.status,
              orderState: s.orderState,
              scheduledStart: s.scheduledStart,
            ),
          )
          .where((s) => s.id.trim().isNotEmpty)
          .toList();

      state = state.copyWith(
        loading: false,
        error: null,
        vehiculos: vehiculos,
        abierta: abierta,
        historial: historial,
        servicios: servicios,
      );
    } on ApiException catch (e) {
      state = state.copyWith(loading: false, error: e.message);
    } catch (_) {
      state = state.copyWith(loading: false, error: 'Ocurrió un error');
    }
  }

  Future<Position> _getCurrentPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw ApiException('Activa el GPS para continuar');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      throw ApiException('Permiso de ubicación denegado');
    }

    return Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      timeLimit: const Duration(seconds: 12),
    );
  }

  Future<void> crearVehiculoPropio({
    required String nombre,
    required String tipo,
    String? placa,
    required String combustibleTipo,
    required double rendimientoKmLitro,
  }) async {
    state = state.copyWith(busy: true, error: null);
    try {
      await _repo.createVehiculoPropio(
        nombre: nombre,
        tipo: tipo,
        placa: placa,
        combustibleTipo: combustibleTipo,
        rendimientoKmLitro: rendimientoKmLitro,
      );
      await load();
    } on ApiException catch (e) {
      state = state.copyWith(busy: false, error: e.message);
    } catch (_) {
      state = state.copyWith(busy: false, error: 'No se pudo crear el vehículo');
    }
  }

  Future<void> iniciarSalida({
    required String servicioId,
    required VehiculoModel vehiculo,
    String? observacion,
  }) async {
    state = state.copyWith(busy: true, error: null);
    try {
      final pos = await _getCurrentPosition();
      await _repo.iniciar(
        servicioId: servicioId,
        vehiculoId: vehiculo.id,
        esVehiculoPropio: !vehiculo.esEmpresa,
        latSalida: pos.latitude,
        lngSalida: pos.longitude,
        observacion: observacion,
      );
      await load();
    } on ApiException catch (e) {
      state = state.copyWith(busy: false, error: e.message);
    } catch (_) {
      state = state.copyWith(busy: false, error: 'No se pudo iniciar la salida');
    }
  }

  Future<void> marcarLlegada({required String salidaId, String? observacion}) async {
    state = state.copyWith(busy: true, error: null);
    try {
      final pos = await _getCurrentPosition();
      await _repo.marcarLlegada(
        salidaId: salidaId,
        latLlegada: pos.latitude,
        lngLlegada: pos.longitude,
        observacion: observacion,
      );
      await load();
    } on ApiException catch (e) {
      state = state.copyWith(busy: false, error: e.message);
    } catch (_) {
      state = state.copyWith(busy: false, error: 'No se pudo marcar llegada');
    }
  }

  Future<void> finalizar({required String salidaId, String? observacion}) async {
    state = state.copyWith(busy: true, error: null);
    try {
      final pos = await _getCurrentPosition();
      await _repo.finalizar(
        salidaId: salidaId,
        latFinal: pos.latitude,
        lngFinal: pos.longitude,
        observacion: observacion,
      );
      await load();
    } on ApiException catch (e) {
      state = state.copyWith(busy: false, error: e.message);
    } catch (_) {
      state = state.copyWith(busy: false, error: 'No se pudo finalizar la salida');
    }
  }
}
