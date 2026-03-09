# Testing & Quality Assurance

> **Comprehensive testing strategies for sync applications**

---

## 🎯 Testing Pyramid

```
        /\
       /  \  End-to-End Tests (10%)
      /────\
     /      \
    /        \  Integration Tests (30%)
   /──────────\
  /            \
 /              \ Unit Tests (60%)
/________________\
```

---

## ✅ Unit Testing

### Testing SyncEngine

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:replicore/replicore.dart';

class MockLocalStore extends Mock implements LocalStore {}
class MockRemoteAdapter extends Mock implements RemoteAdapter {}

void main() {
  group('SyncEngine', () {
    late SyncEngine engine;
    late MockLocalStore localStore;
    late MockRemoteAdapter remoteAdapter;

    setUp(() {
      localStore = MockLocalStore();
      remoteAdapter = MockRemoteAdapter();
      engine = SyncEngine(
        localStore: localStore,
        remoteAdapter: remoteAdapter,
      );
    });

    test('initializes successfully', () async {
      when(localStore.initialize()).thenAnswer((_) async {});
      when(remoteAdapter.ping()).thenAnswer((_) async => true);

      await engine.initialize();

      verify(localStore.initialize()).called(1);
      expect(engine.isInitialized, true);
    });

    test('tracks dirty records', () async {
      when(localStore.markDirty(any, any, any))
          .thenAnswer((_) async {});

      await engine.writeLocal('todos', {'id': '1', 'title': 'Test'});

      verify(localStore.markDirty('todos', '1', any)).called(1);
    });
  });
}
```

### Testing LocalStore

```dart
void main() {
  group('SqfliteLocalStore', () {
    late Database db;
    late SqfliteLocalStore store;

    setUp(() async {
      db = await openDatabase(
        inMemoryDatabasePath,
        version: 1,
      );
      store = SqfliteLocalStore(db);
      await store.initialize();
    });

    tearDown(() async {
      await db.close();
    });

    test('reads data correctly', () async {
      await db.insert('todos', {
        'id': '1',
        'title': 'Test',
        'updated_at': '2024-01-01',
      });

      final record = await store.read('todos', '1');

      expect(record, isNotNull);
      expect(record['title'], equals('Test'));
    });

    test('marks record as dirty', () async {
      await db.insert('todos', {
        'id': '1',
        'title': 'Test',
        'dirty': 0,
      });

      await store.markDirty('todos', '1', SyncDirection.push);

      final record = await db.query('todos', where: 'id = ?', whereArgs: ['1']);
      expect(record.first['dirty'], equals(1));
    });
  });
}
```

### Testing Adapters

```dart
void main() {
  group('FirebaseAdapter', () {
    late FirebaseAdapter adapter;
    late MockFirebaseFirestore firestore;

    setUp(() {
      firestore = MockFirebaseFirestore();
      adapter = FirebaseAdapter(firestore);
    });

    test('upserts data in batch', () async {
      final records = [
        {'id': '1', 'title': 'First'},
        {'id': '2', 'title': 'Second'},
      ];

      when(firestore.batch()).thenReturn(MockWriteBatch());

      await adapter.upsert(
        table: 'todos',
        records: records,
      );

      verify(firestore.batch()).called(1);
    });

    test('handles permission errors', () async {
      when(remoteAdapter.upsert(any)).thenThrow(
        FirebaseException(
          plugin: 'cloud_firestore',
          message: 'Permission denied',
        ),
      );

      expect(
        () => adapter.upsert(table: 'todos', records: []),
        throwsA(isA<PushException>()),
      );
    });
  });
}
```

---

## 🔗 Integration Testing

### End-to-End Sync

```dart
void main() {
  group('Integration: Full Sync Cycle', () {
    late SyncEngine engine;
    late Database localDb;
    late MockRemoteServer server;

    setUp(() async {
      localDb = await openDatabase(inMemoryDatabasePath);
      server = MockRemoteServer();
      
      engine = SyncEngine(
        localStore: SqfliteLocalStore(localDb),
        remoteAdapter: MockAdapter(),
      );
      
      await engine.initialize();
    });

    test('pull → conflict → push cycle', () async {
      // Step 1: Set up server data
      server.add('todos', {
        'id': '1',
        'title': 'Server',
        'updated_at': '2024-01-02',  // Newer
      });

      // Step 2: Set up local data
      await engine.writeLocal('todos', {
        'id': '1',
        'title': 'Local',
        'updated_at': '2024-01-01',
      });

      // Step 3: Run sync
      await engine.sync();

      // Step 4: Verify conflict resolution
      final result = await engine.readLocal('todos', '1');
      expect(result['title'], equals('Server'));  // LastWriteWins

      // Step 5: Verify no more dirty
      final dirty = await engine.getDirtyRecords('todos');
      expect(dirty, isEmpty);
    });

    test('batch operations improve performance', () async {
      // Create 100 local records
      for (int i = 0; i < 100; i++) {
        await engine.writeLocal('todos', {
          'id': 'local_$i',
          'title': 'Todo $i',
        });
      }

      final stopwatch = Stopwatch()..start();
      await engine.sync();
      stopwatch.stop();

      // Should complete in <1 second with batching
      expect(stopwatch.elapsedMilliseconds, lessThan(1000));
    });
  });
}
```

---

## ⚔️ Conflict Testing

### Testing Conflict Strategies

```dart
void main() {
  group('Conflict Resolution', () {
    late ConflictResolver resolver;

    test('ServerWins strategy', () async {
      final conflict = SyncConflict(
        localVersion: {'title': 'Local', 'version': 1},
        remoteVersion: {'title': 'Remote', 'version': 2},
        table: 'todos',
        primaryKey: '1',
      );

      final resolved = await ServerWinsResolver().resolve(conflict);

      expect(resolved, equals(conflict.remoteVersion));
    });

    test('CustomResolver with content merge', () async {
      final resolver = CustomResolver((conflict) {
        final local = conflict.localVersion;
        final remote = conflict.remoteVersion;

        // Smart merge: combine content
        return {
          ...remote,
          'merged_content': '${local['content']} + ${remote['content']}',
        };
      });

      final conflict = SyncConflict(
        localVersion: {'content': 'Local notes'},
        remoteVersion: {'content': 'Remote notes'},
        table: 'notes',
        primaryKey: '1',
      );

      final resolved = await resolver.resolve(conflict);

      expect(
        resolved['merged_content'],
        contains('Local notes'),
      );
    });

    test('UserPromptResolver', () async {
      final resolver = UserPromptResolver(
        onConflict: (conflict) async {
          // Simulate user choosing local
          return conflict.localVersion;
        },
      );

      final conflict = SyncConflict(
        localVersion: {'title': 'Local'},
        remoteVersion: {'title': 'Remote'},
        table: 'todos',
        primaryKey: '1',
      );

      final resolved = await resolver.resolve(conflict);

      expect(resolved, equals(conflict.localVersion));
    });
  });
}
```

---

## 🧩 Mock Adapters

### Create Test Doubles

```dart
class MockRemoteAdapter extends RemoteAdapter {
  final data = <String, List<Map>>{};
  int pullCount = 0;
  int pushCount = 0;

  @override
  Future<List<Map>> pull({
    required String table,
    required DateTime since,
  }) async {
    pullCount++;
    return data[table] ?? [];
  }

  @override
  Future<void> upsert({
    required String table,
    required List<Map> records,
  }) async {
    pushCount++;
    data[table] = records;
  }

  @override
  Future<void> delete({
    required String table,
    required List<String> ids,
  }) async {
    data[table]?.removeWhere((r) => ids.contains(r['id']));
  }

  // Simulate network delay
  Future<void> simulateNetworkDelay(Duration delay) async {
    await Future.delayed(delay);
  }

  // Simulate failures
  void simulateFailure(Exception error) {
    throw error;
  }
}

test('retries on timeout', () async {
  int attempts = 0;
  final adapter = MockRemoteAdapter();

  adapter.pullCount = 0;

  // First attempt fails
  when(adapter.pull(table: any, since: any))
    .thenAnswer((_) {
      attempts++;
      if (attempts < 3) {
        throw TimeoutException('Network timeout');
      }
      return [];
    });

  await engine.sync();  // Should retry and succeed

  expect(attempts, equals(3));
});
```

---

## 🎬 Scenario Testing

### Test Real-World Scenarios

```dart
void main() {
  group('Real-World Scenarios', () {
    test('offline-first todo app', () async {
      // Simulate user offline
      when(connectivity.checkConnectivity())
          .thenAnswer((_) async => ConnectivityResult.none);

      // User can still create todos
      await engine.writeLocal('todos', {
        'id': '1',
        'title': 'Buy groceries',
      });

      // Records tracked as dirty
      expect(await engine.getDirtyRecords('todos'), hasLength(1));

      // Simulate network restored
      when(connectivity.checkConnectivity())
          .thenAnswer((_) async => ConnectivityResult.wifi);

      // Sync happens automatically
      await engine.sync();

      // No more dirty
      expect(await engine.getDirtyRecords('todos'), isEmpty);
    });

    test('concurrent edits with merge', () async {
      // Remote has edit at 12:00
      server.add('notes', {
        'id': '1',
        'content': 'Remote edit',
        'updated_at': '2024-01-01T12:00:00Z',
      });

      // Local has edit at 12:01
      await engine.writeLocal('notes', {
        'id': '1',
        'content': 'Local edit',
        'updated_at': '2024-01-01T12:01:00Z',
      });

      // Custom resolver merges both
      engine.setConflictResolver(CustomResolver((c) {
        return {
          ...c.remoteVersion,
          'content': '${c.remoteVersion['content']} + '
                     '${c.localVersion['content']}',
        };
      }));

      await engine.sync();

      final result = await engine.readLocal('notes', '1');
      expect(result['content'], contains('Remote edit'));
      expect(result['content'], contains('Local edit'));
    });

    test('soft delete handling', () async {
      // Create and sync record
      await engine.writeLocal('todos', {
        'id': '1',
        'title': 'Delete me',
        'deleted_at': null,
      });
      await engine.sync();

      // Soft delete
      await engine.writeLocal('todos', {
        'id': '1',
        'title': 'Delete me',
        'deleted_at': '2024-01-01T12:00:00Z',
      });

      // Should push deletion
      await engine.sync();

      // Local filtering
      final active = await engine.readLocal('todos', '1');
      expect(active, isNull);  // Filtered out
    });
  });
}
```

---

## 📊 Performance Testing

```dart
void main() {
  group('Performance Benchmarks', () {
    late SyncEngine engine;

    test('benchmark: 100 record sync', () async {
      final stopwatch = Stopwatch()..start();

      // Create 100 dirty records
      for (int i = 0; i < 100; i++) {
        await engine.writeLocal('todos', {
          'id': 'benchmark_$i',
          'title': 'Todo $i',
        });
      }

      // Sync with batching
      await engine.sync();
      stopwatch.stop();

      final elapsed = stopwatch.elapsedMilliseconds;

      // Should be fast with batching
      expect(elapsed, lessThan(500));

      print('✅ 100 records: ${elapsed}ms');
    });

    test('benchmark: 5000 record sync', () async {
      final stopwatch = Stopwatch()..start();

      for (int i = 0; i < 5000; i++) {
        await engine.writeLocal('todos', {
          'id': 'perf_$i',
          'title': 'Todo $i',
        });
      }

      await engine.sync();
      stopwatch.stop();

      final elapsed = stopwatch.elapsedMilliseconds;

      // v0.5.1 with batching: ~3000-4000ms
      // v0.4.0 without batching: ~120000ms+
      expect(elapsed, lessThan(5000));

      print('✅ 5000 records: ${elapsed}ms');
    });
  });
}
```

---

## 🚀 CI/CD Integration

### GitHub Actions Example

```yaml
name: Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.16.0'
      
      - run: flutter pub get
      
      - run: flutter test --coverage
      
      - uses: codecov/codecov-action@v3
        with:
          files: ./coverage/lcov.info
          flags: unittests
```

---

## ✨ Best Practices

### ✅ DO

- ✅ Test both happy path and error cases
- ✅ Use mock adapters for isolation
- ✅ Test conflict scenarios explicitly
- ✅ Benchmark performance changes
- ✅ Test offline scenarios
- ✅ Use in-memory databases for speed

### ❌ DON'T

- ❌ Test against real backend in unit tests
- ❌ Use actual network calls in tests
- ❌ Skip conflict testing
- ❌ Ignore performance regressions
- ❌ Write tests without mocks

---

**Well-tested sync code is production-ready code!** 🚀
