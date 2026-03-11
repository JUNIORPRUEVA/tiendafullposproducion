import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../api/env.dart';
import '../auth/auth_provider.dart';
import '../auth/auth_repository.dart';
import '../auth/token_storage.dart';

class CatalogRealtimeMessage {
  const CatalogRealtimeMessage({
    required this.eventId,
    required this.type,
    required this.product,
  });

  final String eventId;
  final String type;
  final Map<String, dynamic> product;
}

class CatalogRealtimeService {
  CatalogRealtimeService(this._storage);

  final TokenStorage _storage;
  final StreamController<CatalogRealtimeMessage> _controller =
      StreamController<CatalogRealtimeMessage>.broadcast();
  final Set<String> _seenEventIds = <String>{};

  io.Socket? _socket;

  Stream<CatalogRealtimeMessage> get stream => _controller.stream;

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

    socket.on('product.event', (data) {
      if (data is! Map) return;
      final payload = Map<String, dynamic>.from(data);
      final eventId = payload['eventId']?.toString() ?? '';
      if (eventId.isNotEmpty && !_seenEventIds.add(eventId)) {
        return;
      }
      if (_seenEventIds.length > 200) {
        _seenEventIds.remove(_seenEventIds.first);
      }

      final productJson = payload['product'];
      if (productJson is! Map) return;
      _controller.add(
        CatalogRealtimeMessage(
          eventId: eventId,
          type: payload['type']?.toString() ?? 'product.updated',
          product: Map<String, dynamic>.from(productJson),
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

final catalogRealtimeServiceProvider = Provider<CatalogRealtimeService>((ref) {
  final storage = ref.read(tokenStorageProvider);
  return CatalogRealtimeService(storage);
});
