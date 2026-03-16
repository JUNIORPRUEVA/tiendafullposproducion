import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../api/env.dart';
import '../auth/auth_provider.dart';
import '../auth/auth_repository.dart';
import '../auth/token_storage.dart';

class OperationsRealtimeMessage {
  const OperationsRealtimeMessage({
    required this.eventId,
    required this.type,
    this.serviceId,
    this.service,
  });

  final String eventId;
  final String type;
  final String? serviceId;
  final Map<String, dynamic>? service;
}

class OperationsRealtimeService {
  OperationsRealtimeService(this._storage);

  final TokenStorage _storage;
  final StreamController<OperationsRealtimeMessage> _controller =
      StreamController<OperationsRealtimeMessage>.broadcast();
  final Set<String> _seenEventIds = <String>{};

  io.Socket? _socket;

  Stream<OperationsRealtimeMessage> get stream => _controller.stream;

  Future<void> connect(AuthState authState) async {
    if (!authState.isAuthenticated) {
      disconnect();
      return;
    }

    final token = await _storage.getAccessToken();
    if (token == null || token.trim().isEmpty) {
      disconnect();
      return;
    }

    final existing = _socket;
    if (existing != null && (existing.connected || existing.active)) {
      return;
    }

    final socket = io.io(
      Env.apiBaseUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(999999)
          .setReconnectionDelay(1500)
          .setAuth({'token': token})
          .build(),
    );

    socket.on('service.event', (data) {
      if (data is! Map) return;
      final payload = Map<String, dynamic>.from(data);
      final eventId = payload['eventId']?.toString() ?? '';
      if (eventId.isNotEmpty && !_seenEventIds.add(eventId)) {
        return;
      }
      if (_seenEventIds.length > 300) {
        _seenEventIds.remove(_seenEventIds.first);
      }

      final serviceId = payload['serviceId']?.toString().trim();
      final serviceJson = payload['service'];
      Map<String, dynamic>? service;
      if (serviceJson is Map) {
        service = Map<String, dynamic>.from(serviceJson);
      }

      // If there's no service snapshot, we still forward the message so
      // listeners can trigger a refresh by id.
      if (service == null && (serviceId == null || serviceId.isEmpty)) {
        return;
      }

      final resolvedId =
          (serviceId != null && serviceId.isNotEmpty)
              ? serviceId
              : (service?['id']?.toString().trim());

      _controller.add(
        OperationsRealtimeMessage(
          eventId: eventId,
          type: payload['type']?.toString() ?? 'service.updated',
          serviceId: (resolvedId != null && resolvedId.isNotEmpty)
              ? resolvedId
              : null,
          service: service,
        ),
      );
    });

    socket.connect();
    _socket = socket;
  }

  void disconnect() {
    _socket?.dispose();
    _socket = null;
  }
}

final operationsRealtimeServiceProvider = Provider<OperationsRealtimeService>((ref) {
  final storage = ref.read(tokenStorageProvider);
  return OperationsRealtimeService(storage);
});
