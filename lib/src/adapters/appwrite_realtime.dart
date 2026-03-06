import 'dart:async';

import '../core/realtime_subscription.dart';

/// Appwrite implementation of [RealtimeSubscriptionProvider].
///
/// Uses Appwrite's WebSocket-based real-time updates for
/// document change notifications.
class AppwriteRealtimeProvider implements RealtimeSubscriptionProvider {
  final dynamic client;
  final String databaseId;
  final Duration connectionTimeout;

  final Map<String, StreamSubscription> _subscriptions = {};
  final Map<String, StreamController<RealtimeChangeEvent>> _controllers = {};
  bool _isConnected = false;
  late StreamController<bool> _connectionStatusController;
  StreamSubscription? _realtimeSubscription;

  AppwriteRealtimeProvider({
    required this.client,
    required this.databaseId,
    this.connectionTimeout = const Duration(seconds: 30),
  }) {
    _connectionStatusController = StreamController<bool>.broadcast();
    _setupRealtimeConnection();
  }

  /// Setup the main Appwrite realtime connection.
  void _setupRealtimeConnection() {
    try {
      // Subscribe to all document events in the database
      _realtimeSubscription = client.realtime
          .subscribe(['databases.$databaseId.collections.*'])
          .listen(
            (event) {
              _handleRealtimeMessage(event);
            },
            onError: (error) {
              _isConnected = false;
              _connectionStatusController.add(false);
            },
            onDone: () {
              _isConnected = false;
              _connectionStatusController.add(false);
            },
          );
      _isConnected = true;
      _connectionStatusController.add(true);
    } catch (e) {
      _isConnected = false;
      _connectionStatusController.add(false);
    }
  }

  /// Handle incoming Appwrite realtime message.
  void _handleRealtimeMessage(dynamic message) {
    try {
      // Appwrite sends messages with structure:
      // {
      //   'type': 'databases.*.collections.*.documents.*.create|update|delete',
      //   'payload': { document data }
      // }
      final type = message['type'] as String? ?? '';
      final payload = message['payload'] as Map<String, dynamic>? ?? {};

      // Extract collection ID from message type
      // Format: databases.{databaseId}.collections.{collectionId}.documents.{documentId}.{action}
      final parts = type.split('.');
      if (parts.length < 6) return;

      final collectionId = parts[3];
      final action = parts.last;

      // Determine operation type
      late RealtimeOperation operation;
      switch (action) {
        case 'create':
          operation = RealtimeOperation.insert;
          break;
        case 'update':
          operation = RealtimeOperation.update;
          break;
        case 'delete':
          operation = RealtimeOperation.delete;
          break;
        default:
          return;
      }

      // Emit event to appropriate table's controller
      final controller = _controllers[collectionId];
      if (controller != null && !controller.isClosed) {
        controller.add(
          RealtimeChangeEvent(
            table: collectionId,
            operation: operation,
            record: action != 'delete' ? payload : null,
            metadata: {
              'appwriteType': type,
              'documentId': parts.length > 4 ? parts[5] : null,
            },
            timestamp: DateTime.now(),
          ),
        );
      }
    } catch (e) {
      // Silently ignore malformed messages
    }
  }

  @override
  Stream<RealtimeChangeEvent> subscribe(String table) {
    // Create controller if not exists
    if (!_controllers.containsKey(table)) {
      _controllers[table] = StreamController<RealtimeChangeEvent>.broadcast();
    }
    return _controllers[table]!.stream;
  }

  @override
  bool get isConnected => _isConnected;

  @override
  Stream<bool> get connectionStatusStream => _connectionStatusController.stream;

  @override
  Future<void> close() async {
    await _realtimeSubscription?.cancel();
    for (final sub in _subscriptions.values) {
      await sub.cancel();
    }
    _subscriptions.clear();

    for (final controller in _controllers.values) {
      await controller.close();
    }
    _controllers.clear();

    await _connectionStatusController.close();
  }
}
