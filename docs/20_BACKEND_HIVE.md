# Local Storage: Hive

> **Fast, lightweight NoSQL local database for Flutter**

---

## 🎯 Why Hive?

### ✅ Strengths
- **Ultra-fast**: 5-10x faster than SQLite for small objects
- **Type-safe**: Dart-native, no SQL needed
- **Lightweight**: Minimal overhead
- **Multi-platform**: Web, mobile, desktop
- **Offline-first ready**: Perfect for sync apps
- **No boilerplate**: Minimal configuration

### ❌ Weaknesses
- **No complex queries**: Limited WHERE/ORDER BY
- **Memory usage**: Loads entire box into memory
- **Large datasets**: Not ideal for 100K+ records
- **Manual indexing**: No automatic indexes
- **Limited relationships**: No foreign key support

---

## 📦 Installation

```bash
flutter pub add hive hive_flutter
flutter pub add dev:hive_generator build_runner
```

---

## 🚀 Setup with Replicore

### 1. Define Models

```dart
import 'package:hive/hive.dart';

part 'todo.g.dart';

@HiveType(typeId: 0)
class Todo extends HiveObject {
  @HiveField(0)
  late String uuid;
  
  @HiveField(1)
  late String title;
  
  @HiveField(2)
  late bool completed;
  
  @HiveField(3)
  late String updatedAt;
  
  @HiveField(4)
  late int dirty = 0;  // For sync tracking
}
```

### 2. Generate Code

```bash
flutter pub run build_runner build
```

---

## 💾 HiveLocalStore Implementation

```dart
class HiveLocalStore extends LocalStore {
  late Box<Todo> todosBox;
  late Box<SyncMetadata> metadataBox;
  
  @override
  Future<void> initialize() async {
    await Hive.initFlutter();
    
    Hive.registerAdapter(TodoAdapter());
    Hive.registerAdapter(SyncMetadataAdapter());
    
    todosBox = await Hive.openBox<Todo>('todos');
    metadataBox = await Hive.openBox<SyncMetadata>('metadata');
  }
  
  @override
  Future<Map?> read(String table, String primaryKey) async {
    final todo = todosBox.get(primaryKey);
    return todo?.toMap();
  }
  
  @override
  Future<List<Map>> readAll(String table) async {
    return todosBox.values
        .map((t) => t.toMap())
        .toList();
  }
  
  @override
  Future<void> upsert({
    required String table,
    required Map<String, Object?> data,
  }) async {
    final todo = Todo()
      ..uuid = data['uuid'] as String
      ..title = data['title'] as String
      ..completed = (data['completed'] as int?) == 1
      ..updatedAt = data['updated_at'] as String;
    
    await todosBox.put(todo.uuid, todo);
  }
  
  @override
  Future<void> markDirty(
    String table,
    String primaryKey,
    SyncDirection direction,
  ) async {
    final todo = todosBox.get(primaryKey);
    if (todo != null) {
      todo.dirty = 1;
      await todo.save();
    }
  }
}
```

---

## 📖 Reading Data

### Single Record

```dart
final todo = todosBox.get('todo-id');
if (todo != null) {
  print('Title: ${todo.title}');
}
```

### All Records

```dart
final todos = todosBox.values.toList();
for (var todo in todos) {
  print(todo.title);
}
```

### Filtered Query

```dart
// Filter in memory
final completed = todosBox.values
    .where((t) => t.completed)
    .toList();

// Sort
final sorted = completed
    .toList()
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
```

### Pagination

```dart
final allTodos = todosBox.values.toList();
const pageSize = 10;

final page1 = allTodos.skip(0).take(pageSize).toList();
final page2 = allTodos.skip(pageSize).take(pageSize).toList();
```

---

## ✍️ Writing Data

### Insert/Update

```dart
final todo = Todo()
  ..uuid = 'unique-id'
  ..title = 'Buy milk'
  ..completed = false
  ..updatedAt = DateTime.now().toIso8601String();

await todosBox.put(todo.uuid, todo);
```

### Batch Operations

```dart
// Multiple inserts efficiently
await todosBox.addAll([
  Todo()..uuid = '1'..title = 'Task 1',
  Todo()..uuid = '2'..title = 'Task 2',
  Todo()..uuid = '3'..title = 'Task 3',
]);

// Batch update
for (var todo in todos) {
  todo.completed = true;
  await todo.save();
}
```

---

## 🗑️ Deleting Data

### Single Delete

```dart
await todosBox.delete('todo-id');
```

### Batch Delete

```dart
final ids = ['id-1', 'id-2', 'id-3'];
for (var id in ids) {
  await todosBox.delete(id);
}
```

### Soft Delete

```dart
final todo = todosBox.get('id-1');
if (todo != null) {
  todo.deletedAt = DateTime.now().toIso8601String();
  await todo.save();
}
```

---

## 📊 Dirty Tracking

```dart
Future<List<Todo>> getDirtyRecords() async {
  return todosBox.values
      .where((t) => t.dirty == 1)
      .toList();
}

Future<void> markClean(String id) async {
  final todo = todosBox.get(id);
  if (todo != null) {
    todo.dirty = 0;
    await todo.save();
  }
}
```

---

## ⏰ Sync Metadata

```dart
@HiveType(typeId: 1)
class SyncMetadata extends HiveObject {
  @HiveField(0)
  late String table;
  
  @HiveField(1)
  late DateTime lastSyncTime;
}

// Get last sync
final metadata = metadataBox.get('todos');
final lastSync = metadata?.lastSyncTime ?? DateTime(2000);

// Update after sync
await metadataBox.put('todos', SyncMetadata()
  ..table = 'todos'
  ..lastSyncTime = DateTime.now());
```

---

## ⚡ Performance Tips

### ✅ DO

- ✅ Use `.get()` for single items (O(1))
- ✅ Use `.values` to iterate (memory efficient)
- ✅ Use multiple boxes for different tables
- ✅ Separate read-heavy data into own box
- ✅ Use adapters for custom types

### ❌ DON'T

- ❌ Store very large objects (>1MB each)
- ❌ Keep extremely large boxes in memory
- ❌ Do complex calculations in box iteration
- ❌ Use unbounded queries

---

## 🎯 Hive vs SQLite

| Feature | Hive | SQLite |
|---------|------|---------|
| Speed | Ultra-fast ⚡ | Very fast 🚀 |
| Query complexity | Simple (in-memory) | Complex (SQL) |
| Memory | Higher | Lower |
| Large datasets | Not ideal | Ideal (100K+) |
| Type-safety | High | Lower |
| Mobile | ✅ | ✅✅ |
| Web | ✅ | ✅ |

**Choose Hive if**: Small-medium datasets, fast object storage, mobile/web
**Choose SQLite if**: Large datasets (100K+), complex queries, lower memory

---

## 🚀 Replicore with Hive

### Complete Setup

```dart
void setupHiveStore() async {
  // Initialize Hive
  final store = HiveLocalStore();
  await store.initialize();
  
  // Configure Firebase adapter
  final adapter = FirebaseAdapter(
    FirebaseFirestore.instance,
  );
  
  // Create engine
  final engine = SyncEngine(
    localStore: store,
    remoteAdapter: adapter,
    config: ReplicoreConfig(
      batchSize: 25,
      usesBatching: true,
    ),
  );
  
  await engine.initialize();
  
  // Use engine
  await engine.sync();
}
```

---

## 🧪 Testing with Hive

```dart
test('hive store works', () async {
  // Use in-memory test box
  Hive.registerAdapter(TodoAdapter());
  final box = await Hive.openBox<Todo>('test');
  
  // Create and save
  final todo = Todo()
    ..uuid = '1'
    ..title = 'Test'
    ..completed = false;
  
  await box.put('1', todo);
  
  // Read and verify
  final stored = box.get('1');
  expect(stored?.title, equals('Test'));
  
  await box.clear();
});
```

---

## ⚠️ Common Issues

### Issue 1: "TypeId already exists"

One adapter registered twice.

```dart
// ❌ WRONG
Hive.registerAdapter(TodoAdapter());
Hive.registerAdapter(TodoAdapter());  // ERROR!

// ✅ CORRECT
Hive.registerAdapter(TodoAdapter());  // Once only
```

### Issue 2: Memory Bloat

Hive loads entire box into memory.

**Solution**: Limit box size or use multiple smaller boxes.

```dart
// Split into separate boxes
final todosBox = await Hive.openBox<Todo>('todos');
final notesBox = await Hive.openBox<Note>('notes');
```

### Issue 3: Slow Queries

Hive filters in-memory, slow for large datasets.

**Solution**: Use Sqflite or Drift for 100K+ records.

---

## 📱 Best For

- ✅ Small-medium apps (<10K records)
- ✅ Mobile first
- ✅ Fast synchronization needed
- ✅ Simple data models
- ✅ Dart-native development

---

## 🔄 Migration from SQLite

```dart
Future<void> migrateToHive() async {
  // Read from SQLite
  final db = await openDatabase('app.db');
  final todos = await db.query('todos');
  
  // Write to Hive
  final box = await Hive.openBox<Todo>('todos');
  for (var row in todos) {
    final todo = Todo()..uuid = row['uuid']...;
    await box.put(todo.uuid, todo);
  }
  
  await db.close();
}
```

---

**Hive is perfect for small-to-medium offline-first apps!** ⚡
