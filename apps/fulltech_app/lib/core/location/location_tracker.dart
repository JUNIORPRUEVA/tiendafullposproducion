import 'dart:async';

import 'package:dio/dio.dart';
import 'package:geolocator/geolocator.dart';

import '../api/api_routes.dart';

class LocationTracker {
  final Dio _dio;
  final Duration interval;

  Timer? _timer;
  bool _running = false;
  bool _inFlight = false;

  LocationTracker({
    required Dio dio,
    this.interval = const Duration(seconds: 15),
  }) : _dio = dio;

  bool get isRunning => _running;

  Future<void> start() async {
    if (_running) return;
    _running = true;

    await _ensurePermission();

    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) {
      unawaited(_tick());
    });

    unawaited(_tick());
  }

  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    stop();
  }

  Future<void> _ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
  }

  Future<void> _tick() async {
    if (!_running || _inFlight) return;

    if (!await Geolocator.isLocationServiceEnabled()) return;

    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }

    _inFlight = true;
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      await _dio.post(
        ApiRoutes.locationsReport,
        data: {
          'latitude': pos.latitude,
          'longitude': pos.longitude,
          'accuracyMeters': pos.accuracy,
          'altitudeMeters': pos.altitude,
          'headingDegrees': pos.heading,
          'speedMps': pos.speed,
          'recordedAt': pos.timestamp.toUtc().toIso8601String(),
        },
      );
    } catch (_) {
      // Silencioso: no debe romper la app si no se puede leer/enviar ubicación.
    } finally {
      _inFlight = false;
    }
  }
}
