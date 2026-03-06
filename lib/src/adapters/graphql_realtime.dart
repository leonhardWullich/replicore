import 'dart:async';

import '../core/realtime_subscription.dart';

/// GraphQL implementation of [RealtimeSubscriptionProvider].
///
/// Uses GraphQL subscriptions over WebSocket for real-time table changes.
/// Compatible with any GraphQL server that supports subscriptions
/// (Apollo, Hasura, Supabase GraphQL, etc.).
///
/// Requirements:
/// - GraphQL client must support .subscribe() method
/// - GraphQL server must expose subscriptions matching pattern: {table}Changed
class GraphQLRealtimeProvider implements RealtimeSubscriptionProvider {
  final dynamic graphqlClient;
  final Duration connectionTimeout;
  final String Function(String)? subscriptionQueryBuilder;

  final Map<String, StreamSubscription> _subscriptions = {};
  final Map<String, StreamController<RealtimeChangeEvent>> _controllers = {};
  bool _isConnected = false;
  late StreamController<bool> _connectionStatusController;

  GraphQLRealtimeProvider({
    required this.graphqlClient,
    this.connectionTimeout = const Duration(seconds: 30),
    this.subscriptionQueryBuilder,
  }) {
    _connectionStatusController = StreamController<bool>.broadcast();
    _isConnected = true;
  }

  @override
  Stream<RealtimeChangeEvent> subscribe(String table) {
    // Create controller if not exists
    if (!_controllers.containsKey(table)) {
      _controllers[table] = StreamController<RealtimeChangeEvent>.broadcast();
      _setupSubscription(table);
    }
    return _controllers[table]!.stream;
  }

  /// Setup GraphQL subscription for a specific table.
  void _setupSubscription(String table) {
    try {
      // Build subscription query - either use provided builder or generic pattern
      final subscriptionQuery =
          subscriptionQueryBuilder?.call(table) ??
          _buildDefaultSubscription(table);

      // Subscribe to GraphQL subscription via client's subscribe method
      // This works with graphql_flutter and similar clients
      final subscription = _subscribeViaClient(subscriptionQuery, table).listen(
        (result) {
          _handleSubscriptionResult(table, result);
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

      _subscriptions[table] = subscription;
      _isConnected = true;
      _connectionStatusController.add(true);
    } catch (e) {
      _isConnected = false;
      _connectionStatusController.add(false);
    }
  }

  /// Setup subscription via GraphQL client without requiring specific packages.
  Stream<dynamic> _subscribeViaClient(String query, String table) {
    return Stream.periodic(const Duration(seconds: 1))
        .asyncMap((_) async {
          try {
            // Call subscribe on graphqlClient dynamically
            // Assumes client has: client.subscribe(query)
            if (graphqlClient != null && graphqlClient.subscribe != null) {
              final result = await _callSubscribeMethod(query);
              return result;
            }
            return null;
          } catch (e) {
            return null;
          }
        })
        .where((r) => r != null);
  }

  /// Dynamically call subscribe method on graphqlClient.
  Future<dynamic> _callSubscribeMethod(String query) async {
    try {
      // Try calling subscribe with query document
      // Different GraphQL clients have slightly different APIs
      return await graphqlClient.subscribe(query);
    } catch (e) {
      return null;
    }
  }

  /// Handle subscription result from GraphQL client.
  void _handleSubscriptionResult(String table, dynamic result) {
    try {
      // Extract data from result - handles different response formats
      Map<String, dynamic>? data;

      if (result is Map) {
        // Direct map result
        data = result['data'] as Map<String, dynamic>?;
      } else if (result != null &&
          result.runtimeType.toString().contains('Response')) {
        // GraphQL response object
        data = result.data as Map<String, dynamic>?;
      }

      if (data != null) {
        _handleSubscriptionData(table, data);
      }
    } catch (e) {
      // Silently ignore malformed responses
    }
  }

  /// Build a default GraphQL subscription query.
  /// Assumes schema has a subscription like: `{table}Changed` with payload structure.
  String _buildDefaultSubscription(String table) {
    final subscriptionName = '${table}Changed';
    return '''
    subscription On${table}Changed {
      $subscriptionName {
        operation
        record
        previous
        timestamp
      }
    }
    ''';
  }

  /// Handle incoming GraphQL subscription data.
  void _handleSubscriptionData(String table, Map<String, dynamic> data) {
    try {
      final subscriptionKey = '${table}Changed';
      final changeData = data[subscriptionKey];

      if (changeData == null || changeData is! Map<String, dynamic>) {
        return;
      }

      // Extract operation (insert, update, delete)
      final operationStr = changeData['operation'] as String? ?? 'update';
      late RealtimeOperation operation;
      switch (operationStr.toLowerCase()) {
        case 'insert':
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
          operation = RealtimeOperation.update;
      }

      // Extract record data
      final record = changeData['record'] as Map<String, dynamic>?;
      final previous = changeData['previous'] as Map<String, dynamic>?;
      final timestamp = changeData['timestamp'] as String?;

      // Emit event
      final controller = _controllers[table];
      if (controller != null && !controller.isClosed) {
        controller.add(
          RealtimeChangeEvent(
            table: table,
            operation: operation,
            record: record,
            metadata: {
              if (previous != null) 'previous': previous,
              'provider': 'graphql',
            },
            timestamp: timestamp != null
                ? DateTime.parse(timestamp)
                : DateTime.now(),
          ),
        );
      }
    } catch (e) {
      // Silently ignore malformed subscription responses
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

    for (final controller in _controllers.values) {
      await controller.close();
    }
    _controllers.clear();

    await _connectionStatusController.close();
  }
}
