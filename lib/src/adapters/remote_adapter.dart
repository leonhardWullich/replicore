import '../core/models.dart';
import '../core/realtime_subscription.dart';

abstract class RemoteAdapter {
  Future<PullResult> pull(PullRequest request);

  Future<void> upsert({
    required String table,
    required Map<String, dynamic> data,
    String? idempotencyKey,
  });

  Future<void> softDelete({
    required String table,
    required String primaryKeyColumn,
    required dynamic id,
    required Map<String, dynamic> payload,
    String? idempotencyKey,
  });

  /// Batch upsert multiple records at once (improves performance).
  /// Returns list of successfully upserted primary keys.
  /// If not overridden, falls back to individual upserts.
  Future<List<dynamic>> batchUpsert({
    required String table,
    required List<Map<String, dynamic>> records,
    required String primaryKeyColumn,
    Map<String, String>? idempotencyKeys,
  }) async {
    final successfulIds = <dynamic>[];
    for (final record in records) {
      try {
        final pkValue = record[primaryKeyColumn];
        await upsert(
          table: table,
          data: record,
          idempotencyKey: idempotencyKeys?[pkValue?.toString()],
        );
        if (pkValue != null) successfulIds.add(pkValue);
      } catch (e) {
        // Continue processing other records
      }
    }
    return successfulIds;
  }

  /// Batch soft delete multiple records at once (improves performance).
  /// Returns list of successfully deleted primary keys.
  /// If not overridden, falls back to individual deletes.
  Future<List<dynamic>> batchSoftDelete({
    required String table,
    required String primaryKeyColumn,
    required List<Map<String, dynamic>> records,
    required String deletedAtColumn,
    required String updatedAtColumn,
    Map<String, String>? idempotencyKeys,
  }) async {
    final successfulIds = <dynamic>[];
    for (final record in records) {
      try {
        final pkValue = record[primaryKeyColumn];
        if (pkValue == null) continue;
        await softDelete(
          table: table,
          primaryKeyColumn: primaryKeyColumn,
          id: pkValue,
          payload: {
            deletedAtColumn: record[deletedAtColumn],
            updatedAtColumn:
                record[updatedAtColumn] ??
                DateTime.now().toUtc().toIso8601String(),
          },
          idempotencyKey: idempotencyKeys?[pkValue?.toString()],
        );
        successfulIds.add(pkValue);
      } catch (e) {
        // Continue processing other records
      }
    }
    return successfulIds;
  }

  /// Optional real-time subscription provider.
  /// Return null if this adapter doesn't support real-time updates.
  RealtimeSubscriptionProvider? getRealtimeProvider() => null;
}
