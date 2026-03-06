import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/realtime_subscription.dart';

/// Supabase implementation of [RealtimeSubscriptionProvider].
///
/// Uses Supabase's native PostgreSQL LISTEN/NOTIFY mechanism via WebSocket
/// for efficient real-time change notifications.
class SupabaseRealtimeProvider implements RealtimeSubscriptionProvider {
  final SupabaseClient client;
  final Duration connectionTimeout;

  final Map<String, StreamSubscription> _subscriptions = {};
  bool _isConnected = false;
  late StreamController<bool> _connectionStatusController;

  SupabaseRealtimeProvider({
    required this.client,
    this.connectionTimeout = const Duration(seconds: 30),
  }) {
    _connectionStatusController = StreamController<bool>.broadcast();
    _isConnected = true;
  }

  @override
  Stream<RealtimeChangeEvent> subscribe(String table) {
    return _createRealtimeStream(table);
  }

  /// Create a stream of real-time changes for a Postgres table via Supabase.
  ///
  /// Listens to PostgreSQL INSERT, UPDATE, DELETE events for the specified table.
  Stream<RealtimeChangeEvent> _createRealtimeStream(String table) async* {
    try {
      // Create a StreamController for real-time events
      final eventStreamController =
          StreamController<RealtimeChangeEvent>.broadcast();

      // Create channel for this table
      final channel = client.channel('public:$table');

      // Setup listener for database changes
      channel
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: table,
            callback: (payload) {
              try {
                final eventType = payload.eventType.name.toUpperCase();
                final newRecord = payload.newRecord;
                final oldRecord = payload.oldRecord;

                final operation = switch (eventType) {
                  'INSERT' => RealtimeOperation.insert,
                  'UPDATE' => RealtimeOperation.update,
                  'DELETE' => RealtimeOperation.delete,
                  _ => RealtimeOperation.update,
                };

                final event = RealtimeChangeEvent(
                  table: table,
                  operation: operation,
                  record: operation == RealtimeOperation.delete
                      ? null
                      : newRecord,
                  metadata: {'eventType': eventType, 'previous': oldRecord},
                  timestamp: DateTime.now(),
                );

                eventStreamController.add(event);
              } catch (e) {
                // Silent fail for individual events
              }
            },
          )
          .subscribe();

      _subscriptions[table] = eventStreamController.stream.listen(
        (_) {},
      ); // Keep stream alive

      // Monitor connection status
      _isConnected = true;
      _connectionStatusController.add(true);

      // Yield events from the controller
      yield* eventStreamController.stream;
    } catch (e) {
      _isConnected = false;
      _connectionStatusController.add(false);
      yield* Stream.error(e);
    }
  }

  @override
  bool get isConnected => _isConnected;

  @override
  Stream<bool> get connectionStatusStream => _connectionStatusController.stream;

  @override
  Future<void> close() async {
    for (final sub in _subscriptions.values) {
      await sub.cancel();
    }
    _subscriptions.clear();
    await _connectionStatusController.close();
  }
}
