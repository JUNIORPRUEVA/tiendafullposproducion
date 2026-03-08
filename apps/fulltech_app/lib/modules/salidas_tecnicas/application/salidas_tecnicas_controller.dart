import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/auth/app_role.dart';
import '../../../core/errors/api_exception.dart';
import '../../../features/operaciones/data/operations_repository.dart';
import '../../../features/operaciones/operations_models.dart';
import '../salidas_tecnicas_models.dart';
import '../data/salidas_tecnicas_repository.dart';

class SalidasTecnicasState {
  final bool loading;
  final bool loadingVehiculos;
  final bool isSavingVehicle;
  final bool isStartingSalida;
  final bool isMarkingLlegada;
  final bool isFinalizingSalida;
  final String? loadError;
  final String? vehicleError;
  final String? salidaError;
  final List<VehiculoModel> vehiculos;
  final SalidaTecnicaModel? abierta;
  final List<SalidaTecnicaModel> historial;
  final List<ServiceMiniModel> servicios;

  const SalidasTecnicasState({
    required this.loading,
    required this.loadingVehiculos,
    required this.isSavingVehicle,
    required this.isStartingSalida,
    required this.isMarkingLlegada,
    required this.isFinalizingSalida,
    required this.loadError,
    required this.vehicleError,
    required this.salidaError,
    required this.vehiculos,
    required this.abierta,
    required this.historial,
    required this.servicios,
  });

  factory SalidasTecnicasState.initial() => const SalidasTecnicasState(
    loading: true,
    loadingVehiculos: false,
    isSavingVehicle: false,
    isStartingSalida: false,
    isMarkingLlegada: false,
    isFinalizingSalida: false,
    loadError: null,
    vehicleError: null,
    salidaError: null,
    vehiculos: [],
    abierta: null,
    historial: [],
    servicios: [],
  );

  SalidasTecnicasState copyWith({
    bool? loading,
    bool? loadingVehiculos,
    bool? isSavingVehicle,
    bool? isStartingSalida,
    bool? isMarkingLlegada,
    bool? isFinalizingSalida,
    String? loadError,
    String? vehicleError,
    String? salidaError,
    List<VehiculoModel>? vehiculos,
    SalidaTecnicaModel? abierta,
    List<SalidaTecnicaModel>? historial,
    List<ServiceMiniModel>? servicios,
  }) {
    return SalidasTecnicasState(
      loading: loading ?? this.loading,
      loadingVehiculos: loadingVehiculos ?? this.loadingVehiculos,
      isSavingVehicle: isSavingVehicle ?? this.isSavingVehicle,
      isStartingSalida: isStartingSalida ?? this.isStartingSalida,
      isMarkingLlegada: isMarkingLlegada ?? this.isMarkingLlegada,
      isFinalizingSalida: isFinalizingSalida ?? this.isFinalizingSalida,
      loadError: loadError,
      vehicleError: vehicleError,
      salidaError: salidaError,
      vehiculos: vehiculos ?? this.vehiculos,
      abierta: abierta ?? this.abierta,
      historial: historial ?? this.historial,
      servicios: servicios ?? this.servicios,
    );
  }
}

final salidasTecnicasControllerProvider =
    StateNotifierProvider<SalidasTecnicasController, SalidasTecnicasState>((
      ref,
    ) {
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
    final isTecnico = auth.user?.appRole == AppRole.tecnico;
    if (!auth.isAuthenticated || !isTecnico) {
      state = state.copyWith(
        loading: false,
        loadError: 'Solo disponible para técnicos',
        vehicleError: null,
        salidaError: null,
      );
      return;
    }

    state = state.copyWith(
      loading: true,
      loadError: null,
      // No tocar isSavingVehicle/isStartingSalida aquí: son flujos separados.
    );
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
        loadError: null,
        vehiculos: vehiculos,
        abierta: abierta,
        historial: historial,
        servicios: servicios,
      );
    } on ApiException catch (e) {
      state = state.copyWith(loading: false, loadError: e.message);
    } catch (_) {
      state = state.copyWith(loading: false, loadError: 'Ocurrió un error');
    }
  }

  Future<void> refreshVehiculos({bool silent = false}) async {
    if (!silent) {
      state = state.copyWith(loadingVehiculos: true, vehicleError: null);
    }

    try {
      final vehiculos = await _repo.listVehiculos();
      state = state.copyWith(
        loadingVehiculos: false,
        vehicleError: null,
        vehiculos: vehiculos,
      );
    } on ApiException catch (e, st) {
      debugPrint('[SalidasTecnicas] Error cargando vehículos: ${e.message}');
      debugPrintStack(stackTrace: st);
      state = state.copyWith(loadingVehiculos: false, vehicleError: e.message);
    } catch (e, st) {
      debugPrint('[SalidasTecnicas] Error inesperado cargando vehículos: $e');
      debugPrintStack(stackTrace: st);
      state = state.copyWith(
        loadingVehiculos: false,
        vehicleError: 'No se pudieron cargar vehículos',
      );
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
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw ApiException('Permiso de ubicación denegado');
    }

    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 12),
      ).timeout(
        const Duration(seconds: 13),
        onTimeout: () =>
            throw ApiException('No se pudo obtener la ubicación (timeout).'),
      );
    } on TimeoutException {
      throw ApiException('No se pudo obtener la ubicación (timeout).');
    }
  }

  Future<VehiculoModel?> crearVehiculo({
    required String nombre,
    required String tipo,
    String? placa,
    required String combustibleTipo,
    double? rendimientoKmLitro,
    required bool esEmpresa,
  }) async {
    debugPrint(
      '[SalidasTecnicas] Guardando vehículo (esEmpresa=$esEmpresa)...',
    );

    final normalizedNombre = nombre.trim();
    final normalizedTipo = tipo.trim();
    final normalizedCombustible = combustibleTipo.trim();
    final normalizedPlaca = (placa ?? '').trim();

    if (normalizedNombre.isEmpty) {
      state = state.copyWith(vehicleError: 'El nombre es requerido');
      return null;
    }
    if (normalizedTipo.isEmpty) {
      state = state.copyWith(vehicleError: 'El tipo es requerido');
      return null;
    }
    if (normalizedCombustible.isEmpty) {
      state = state.copyWith(vehicleError: 'El combustible es requerido');
      return null;
    }

    if (!esEmpresa) {
      final v = rendimientoKmLitro;
      if (v == null || v.isNaN || v <= 0) {
        state = state.copyWith(vehicleError: 'Rendimiento km/l inválido');
        return null;
      }
    }

    state = state.copyWith(isSavingVehicle: true, vehicleError: null);
    try {
      debugPrint('[SalidasTecnicas] Validación OK. Enviando a API...');
      final created = await _repo.createVehiculo(
        nombre: normalizedNombre,
        tipo: normalizedTipo,
        placa: normalizedPlaca.isEmpty ? null : normalizedPlaca,
        combustibleTipo: normalizedCombustible,
        rendimientoKmLitro: esEmpresa ? null : rendimientoKmLitro,
        esEmpresa: esEmpresa,
      );
      debugPrint('[SalidasTecnicas] Vehículo guardado: id=${created.id}');

      // Crítico: al guardar vehículo NO recargamos historial/servicios para
      // evitar congelamientos (especialmente en Web). Solo refrescamos vehículos.
      await refreshVehiculos(silent: true);
      return created;
    } on ApiException catch (e, st) {
      debugPrint('[SalidasTecnicas] Error al guardar vehículo: ${e.message}');
      debugPrintStack(stackTrace: st);
      state = state.copyWith(vehicleError: e.message);
      return null;
    } catch (e, st) {
      debugPrint('[SalidasTecnicas] Error inesperado al guardar vehículo: $e');
      debugPrintStack(stackTrace: st);
      state = state.copyWith(vehicleError: 'No se pudo crear el vehículo');
      return null;
    } finally {
      state = state.copyWith(isSavingVehicle: false);
    }
  }

  Future<void> iniciarSalida({
    required String servicioId,
    required VehiculoModel vehiculo,
    String? observacion,
  }) async {
    state = state.copyWith(isStartingSalida: true, salidaError: null);
    try {
      final pos = await _getCurrentPosition();
      final started = await _repo.iniciar(
        servicioId: servicioId,
        vehiculoId: vehiculo.id,
        esVehiculoPropio: !vehiculo.esEmpresa,
        latSalida: pos.latitude,
        lngSalida: pos.longitude,
        observacion: observacion,
      );

      // Importante: NO hacemos load() aquí porque recargar historial/servicios
      // puede congelar la UI (especialmente en Web). La API ya retorna la salida.
      state = state.copyWith(
        salidaError: null,
        abierta: started,
      );
    } on ApiException catch (e) {
      state = state.copyWith(salidaError: e.message);
    } catch (e, st) {
      debugPrint('[SalidasTecnicas] Error inesperado iniciando salida: $e');
      debugPrintStack(stackTrace: st);
      state = state.copyWith(salidaError: 'No se pudo iniciar la salida');
    } finally {
      state = state.copyWith(isStartingSalida: false);
    }
  }

  Future<void> marcarLlegada({
    required String salidaId,
    String? observacion,
  }) async {
    state = state.copyWith(isMarkingLlegada: true, salidaError: null);
    try {
      final pos = await _getCurrentPosition();
      final updated = await _repo.marcarLlegada(
        salidaId: salidaId,
        latLlegada: pos.latitude,
        lngLlegada: pos.longitude,
        observacion: observacion,
      );

      // Evitar load() pesado; actualizamos el estado de la salida abierta.
      state = state.copyWith(
        salidaError: null,
        abierta: updated,
      );
    } on ApiException catch (e) {
      state = state.copyWith(salidaError: e.message);
    } catch (e, st) {
      debugPrint('[SalidasTecnicas] Error inesperado marcando llegada: $e');
      debugPrintStack(stackTrace: st);
      state = state.copyWith(salidaError: 'No se pudo marcar llegada');
    } finally {
      state = state.copyWith(isMarkingLlegada: false);
    }
  }

  Future<void> finalizar({
    required String salidaId,
    String? observacion,
  }) async {
    state = state.copyWith(isFinalizingSalida: true, salidaError: null);
    try {
      final pos = await _getCurrentPosition();
      final finalized = await _repo.finalizar(
        salidaId: salidaId,
        latFinal: pos.latitude,
        lngFinal: pos.longitude,
        observacion: observacion,
      );

      // Evitar recarga completa (historial puede ser grande). Actualizamos localmente:
      // - ya no hay salida abierta
      // - insertamos/actualizamos el item en historial
      final nextHistorial = <SalidaTecnicaModel>[
        finalized,
        ...state.historial.where((s) => s.id != finalized.id),
      ];

      state = state.copyWith(
        salidaError: null,
        abierta: null,
        historial: nextHistorial,
      );
    } on ApiException catch (e) {
      state = state.copyWith(salidaError: e.message);
    } catch (e, st) {
      debugPrint('[SalidasTecnicas] Error inesperado finalizando salida: $e');
      debugPrintStack(stackTrace: st);
      state = state.copyWith(salidaError: 'No se pudo finalizar la salida');
    } finally {
      state = state.copyWith(isFinalizingSalida: false);
    }
  }
}
