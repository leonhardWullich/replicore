# Quick Reference

> **Copy-paste code snippets for common tasks**

---

## 🚀 Initialization

### Complete Setup

```dart
import 'package:replicore/replicore.dart';

// 1. Initialize local storage
final database = await openDatabase('app.db');
final localStore = SqfliteLocalStore(database);
await localStore.initialize();

// 2. Create remote adapter
final firebaseAdapter = FirebaseAdapter(
  FirebaseFirestore.instance,
);

// 3. Configure sync
final config = ReplicoreConfig(
  batchSize: 25,
  maxRetries: 3,
  autoSync: true,
  syncInterval: Duration(minutes: 5),
);

// 4. Create engine
final engine = SyncEngine(
  localStore: localStore,
  remoteAdapter: firebaseAdapter,
  config: config,
);

await engine.initialize();
```

---

## 📝 CRUD Operations

### Create

```dart
await engine.writeLocal('todos', {
  'uuid': 'unique-id-here',
  'title': 'Learning Replicore',
  'completed': false,
  'updated_at': DateTime.now().toIso8601String(),
});
```

### Read Single

```dart
final todo = await engine.readLocal('todos', 'todo-id');
if (todo != null) {
  print(todo['title']);  // 'Learning Replicore'
}
```

### Read All

```dart
final todos = await engine.readLocalWhere(
  'todos',
  where: 'completed = ?',
  whereArgs: [0],
);
```

### Update

```dart
await engine.writeLocal('todos', {
  'uuid': 'todo-id',
  'title': 'Updated title',
  'completed': true,
  'updated_at': DateTime.now().toIso8601String(),
});
```

### Delete

```dart
// Hard delete
await engine.deleteLocal('todos', 'todo-id');

// Soft delete (preferred for sync)
await engine.writeLocal('todos', {
  'uuid': 'todo-id',
  'deleted_at': DateTime.now().toIso8601String(),
});
```

### Bulk Operations

```dart
// Create many
final todos = List.generate(100, (i) => {
  'uuid': 'todo-$i',
  'title': 'Todo $i',
});
await engine.bulkWrite('todos', todos);

// Delete many
await engine.bulkDelete('todos', ['id-1', 'id-2', 'id-3']);
```

---

## 🔄 Synchronization

### Manual Sync

```dart
try {
  final result = await engine.sync();
  print('✅ Synced: ${result.recordsPushed} pushed');
} on NetworkException {
  print('❌ No internet');
} catch (e) {
  print('❌ Sync error: $e');
}
```

### Sync Specific Table

```dart
await engine.sync(table: 'todos');
```

### Monitor Sync Progress

```dart
engine.onSyncStart.listen((_) {
  print('🔄 Syncing...');
  showProgressBar();
});

engine.onSyncComplete.listen((result) {
  print('✅ Done!');
  print('Pulled: ${result.recordsPulled}');
  print('Pushed: ${result.recordsPushed}');
  hideProgressBar();
});

engine.onSyncError.listen((error) {
  print('❌ Error: ${error.message}');
  showRetryButton();
});
```

### Auto-Sync Setup

```dart
// Already enabled by default
final config = ReplicoreConfig(
  autoSync: true,
  syncInterval: Duration(minutes: 5),
);

// Or manual control
if (await connectivity.checkConnectivity() != none) {
  await engine.sync();
}
```

---

## 🎯 Queries

### Simple Where Clause

```dart
final completed = await engine.readLocalWhere(
  'todos',
  where: 'completed = ?',
  whereArgs: [1],
);
```

### Multiple Conditions

```dart
final important = await engine.readLocalWhere(
  'todos',
  where: 'completed = ? AND priority = ?',
  whereArgs: [0, 'high'],
);
```

### With Ordering

```dart
final recent = await engine.readLocalWhere(
  'todos',
  orderBy: 'updated_at DESC',
  limit: 10,
);
```

### Pagination

```dart
final page1 = await engine.readLocalWhere(
  'todos',
  limit: 20,
  offset: 0,
);

final page2 = await engine.readLocalWhere(
  'todos',
  limit: 20,
  offset: 20,
);
```

---

## ⚔️ Conflict Resolution

### Last Write Wins

```dart
final config = ReplicoreConfig(
  conflictResolution: ConflictResolution.lastWriteWins,
);
```

### Server Always Wins

```dart
final config = ReplicoreConfig(
  conflictResolution: ConflictResolution.serverWins,
);
```

### Custom Merge

```dart
final config = ReplicoreConfig(
  conflictResolution: ConflictResolution.custom,
  customResolver: CustomResolver((conflict) {
    // Merge both versions
    final local = conflict.localVersion;
    final remote = conflict.remoteVersion;
    
    return {
      ...remote,
      'description': '${local['description']} + '
                     '${remote['description']}',
    };
  }),
);
```

### User Prompt

```dart
class UserPromptResolver extends CustomResolver {
  UserPromptResolver() : super((conflict) => _showDialog(conflict));

  static Future<Map> _showDialog(SyncConflict conflict) async {
    return await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Conflict detected'),
        content: Column(
          children: [
            Text('Local: ${conflict.localVersion['title']}'),
            Text('Server: ${conflict.remoteVersion['title']}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 
              conflict.localVersion),
            child: Text('Keep local'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context,
              conflict.remoteVersion),
            child: Text('Keep server'),
          ),
        ],
      ),
    );
  }
}
```

---

## 🛡️ Error Handling

### Try-Catch

```dart
try {
  await engine.sync();
} on NetworkException {
  showSnackBar('No internet connection');
} on PushException catch (e) {
  showSnackBar('Upload failed: ${e.message}');
} on PullException catch (e) {
  showSnackBar('Download failed: ${e.message}');
} catch (e) {
  showSnackBar('Unknown error');
}
```

### Retry Logic

```dart
Future<void> syncWithRetry() async {
  for (int i = 0; i < 3; i++) {
    try {
      await engine.sync();
      return;  // Success
    } catch (e) {
      if (i < 2) {
        await Future.delayed(Duration(seconds: 2 * (i + 1)));
      }
    }
  }
  throw Exception('Sync failed');
}
```

### Error Monitoring

```dart
engine.onSyncError.listen((error) {
  // Send to analytics
  analytics.logEvent(
    name: 'sync_error',
    parameters: {
      'type': error.runtimeType.toString(),
      'message': error.message,
      'table': error.table,
    },
  );
});
```

---

## 📊 Metrics & Monitoring

### Get Sync Statistics

```dart
final metrics = engine.getMetrics();

print('Total syncs: ${metrics.totalSyncs}');
print('Success rate: ${((metrics.successfulSyncs / metrics.totalSyncs) * 100).toStringAsFixed(1)}%');
print('Avg sync time: ${metrics.avgDuration.inMilliseconds}ms');
print('Total data moved: ${metrics.totalRecordsPushed} records');
```

### Track Dirty Records

```dart
final dirty = await engine.getDirtyRecords('todos');
print('${dirty.length} todos pending sync');

if (dirty.isNotEmpty) {
  debugPrint('Pending: $dirty');
}
```

### Monitor Data Changes

```dart
engine.onDataChanged.listen((change) {
  print('${change.table}: ${change.operation}');
  
  switch (change.operation) {
    case ChangeType.insert:
      onTodoAdded(change.data);
      break;
    case ChangeType.update:
      onTodoUpdated(change.data);
      break;
    case ChangeType.delete:
      onTodoDeleted(change.data['uuid']);
      break;
  }
});
```

---

## 🎯 UI Integration

### Display Sync Status

```dart
class SyncStatusBadge extends StatefulWidget {
  @override
  State<SyncStatusBadge> createState() => _SyncStatusBadgeState();
}

class _SyncStatusBadgeState extends State<SyncStatusBadge> {
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    
    engine.onSyncStart.listen((_) {
      setState(() => _syncing = true);
    });
    
    engine.onSyncComplete.listen((_) {
      setState(() => _syncing = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: _syncing 
        ? Text('Syncing...')
        : Text('Synced'),
      backgroundColor: _syncing 
        ? Colors.blue
        : Colors.green,
    );
  }
}
```

### Pull-to-Refresh

```dart
RefreshIndicator(
  onRefresh: () => engine.sync(),
  child: ListView(
    children: todos.map((todo) => 
      ListTile(title: Text(todo['title']))
    ).toList(),
  ),
)
```

### Real-time List Updates

```dart
StreamBuilder(
  stream: engine.onDataChanged,
  builder: (context, snapshot) {
    return FutureBuilder(
      future: engine.readLocalWhere('todos'),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return CircularProgressIndicator();
        
        final todos = snapshot.data!;
        return ListView.builder(
          itemCount: todos.length,
          itemBuilder: (context, index) => ListTile(
            title: Text(todos[index]['title']),
          ),
        );
      },
    );
  },
)
```

---

## ⚙️ Configuration Presets

### Development

```dart
final devConfig = ReplicoreConfig(
  showLogs: true,
  logLevel: 'debug',
  autoSync: false,  // Manual control
  maxRetries: 1,
  batchSize: 10,
);
```

### Testing

```dart
final testConfig = ReplicoreConfig(
  showLogs: false,
  autoSync: false,
  maxRetries: 0,
  batchSize: 1,  // No batching
);
```

### Production

```dart
final prodConfig = ReplicoreConfig(
  showLogs: false,
  autoSync: true,
  syncInterval: Duration(minutes: 5),
  maxRetries: 3,
  retryDelay: Duration(seconds: 2),
  batchSize: 50,
);
```

---

## 🧪 Testing Snippets

### Mock Adapter

```dart
class MockAdapter extends RemoteAdapter {
  @override
  Future<bool> ping() async => true;
  
  @override
  Future<List<Map>> pull({
    required String table,
    required DateTime since,
  }) async => [];
  
  @override
  Future<void> upsert({
    required String table,
    required List<Map> records,
  }) async {}
  
  @override
  Future<void> delete({
    required String table,
    required List<String> ids,
  }) async {}
}
```

### Test Sync

```dart
test('sync completes', () async {
  final engine = SyncEngine(
    localStore: mockStore,
    remoteAdapter: MockAdapter(),
  );
  
  await engine.initialize();
  final result = await engine.sync();
  
  expect(result.success, true);
});
```

---

## 🔗 Common Patterns

### Offline-First Add

```dart
Future<void> addTodo(String title) async {
  // Save locally first
  await engine.writeLocal('todos', {
    'uuid': uuid.v4(),
    'title': title,
    'completed': false,
  });
  
  // Try to sync if online
  if (await connectivity.check() != none) {
    await engine.sync();
  }
  // Otherwise syncs automatically later
}
```

### Check Sync Status

```dart
Future<bool> isSynced() async {
  final dirty = await engine.getDirtyRecords('todos');
  return dirty.isEmpty;
}

if (await isSynced()) {
  // All data synced with server
} else {
  // Still pending changes
}
```

### Safe Table Operations

```dart
Future<void> safeDelete(String id) async {
  try {
    // Soft delete (preferred)
    await engine.writeLocal('todos', {
      'uuid': id,
      'deleted_at': DateTime.now().toIso8601String(),
    });
  } catch (e) {
    // Hard delete fallback
    await engine.deleteLocal('todos', id);
  }
}
```

---

**Copy, paste, and customize!** 🚀
