# Local Storage: Isar

> **Ultra-fast, encrypted, embedded database for Flutter**

---

## 🎯 Why Isar?

### ✅ Strengths
- **Ultra-fast**: Fastest NoSQL for Flutter
- **Encrypted**: Built-in encryption support
- **Reactive**: Real-time streams
- **Compound indexes**: Complex queries fast
- **Multi-instance**: Parallel databases
- **Auto-increment**: Automatic ID generation
- **Large datasets**: Handles 100K+ efficiently

### ❌ Weaknesses
- **NoSQL only**: No SQL syntax
- **Learning curve**: Different paradigm
- **Single platform**: Mostly Flutter

---

## 📦 Installation

```bash
flutter pub add isar isar_flutter_libs
flutter pub add dev:isar_generator build_runner
```

---

## 🏗️ Define Collections

```dart
import 'package:isar/isar.dart';

part 'todo.g.dart';

@collection
class Todo {
  Id? id;  // Isar-generated ID
  
  @Index()  // Create index for faster queries
  late String uuid;
  
  late String title;
  late bool completed = false;
  late String updatedAt;
  late int dirty = 0;
  
  DateTime? deletedAt;  // For soft deletes
}

@collection
class SyncMetadata {
  Id? id;
  
  @Index()
  late String table;
  
  late DateTime lastSync;
}
```

---

## 🛠️ Generate Code

```bash
flutter pub run build_runner build
```

---

## 🚀 IsarLocalStore Implementation

```dart
class IsarLocalStore extends LocalStore {
  late Isar isar;
  
  @override
  Future<void> initialize() async {
    isar = await Isar.open(
      [TodoSchema, SyncMetadataSchema],
      directory: (await getApplicationDocumentsDirectory()).path,
      inspector: true,  // Dev tool
    );
  }
  
  @override
  Future<Map?> read(String table, String primaryKey) async {
    final todo = await isar.todos
        .filter()
        .uuidEqualTo(primaryKey)
        .findFirst();
    
    return todo?.toMap();
  }
  
  @override
  Future<List<Map>> readAll(String table) async {
    final todos = await isar.todos.where().findAll();
    return todos.map((t) => t.toMap()).toList();
  }
  
  @override
  Future<List<Map>> readWhere({
    required String table,
    String? where,
    List<Object?>? whereArgs,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    var query = isar.todos.where();
    
    // Filter
    if (where == 'completed = ?') {
      final completed = whereArgs?[0] as int? ?? 0;
      query = query.completedEqualTo(completed == 1);
    }
    
    // Sort
    if (orderBy?.contains('DESC') ?? false) {
      query = query.sortByUpdatedAtDesc();
    }
    
    // Limit
    if (limit != null) {
      return (await query.findAll())
          .skip(offset ?? 0)
          .take(limit)
          .map((t) => t.toMap())
          .toList();
    }
    
    final todos = await query.findAll();
    return todos.map((t) => t.toMap()).toList();
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
      ..updatedAt = data['updated_at'] as String
      ..dirty = (data['dirty'] as int?) ?? 0;
    
    await isar.writeTxn(() async {
      await isar.todos.put(todo);
    });
  }
  
  @override
  Future<void> markDirty(
    String table,
    String primaryKey,
    SyncDirection direction,
  ) async {
    final todo = await isar.todos
        .filter()
        .uuidEqualTo(primaryKey)
        .findFirst();
    
    if (todo != null) {
      todo.dirty = 1;
      await isar.writeTxn(() async {
        await isar.todos.put(todo);
      });
    }
  }
  
  @override
  Future<List<Map>> getDirtyRecords(String table) async {
    final dirty = await isar.todos
        .filter()
        .dirtyEqualTo(1)
        .findAll();
    
    return dirty.map((t) => t.toMap()).toList();
  }
  
  @override
  Future<void> delete(String table, String primaryKey) async {
    final todo = await isar.todos
        .filter()
        .uuidEqualTo(primaryKey)
        .findFirst();
    
    if (todo != null) {
      await isar.writeTxn(() async {
        await isar.todos.delete(todo.id!);
      });
    }
  }
}
```

---

## 📖 Reading Data

### Single Record

```dart
final todo = await isar.todos
    .filter()
    .uuidEqualTo('todo-id')
    .findFirst();

if (todo != null) {
  print('Title: ${todo.title}');
}
```

### All Records

```dart
final todos = await isar.todos.where().findAll();
for (var todo in todos) {
  print(todo.title);
}
```

### Filtered Query

```dart
// Filter completed
final completed = await isar.todos
    .filter()
    .completedEqualTo(true)
    .findAll();

// Multiple conditions
final important = await isar.todos
    .filter()
    .completedEqualTo(false)
    .and()
    .deletedAtIsNull()
    .findAll();
```

### Sorted Query

```dart
// Sort by updated time (newest first)
final recent = await isar.todos
    .where()
    .sortByUpdatedAtDesc()
    .findAll();

// Limit results
final topFive = await isar.todos
    .where()
    .limit(5)
    .findAll();
```

### Pagination

```dart
final pageSize = 20;
final page = 2;

final todos = await isar.todos
    .where()
    .offset(page * pageSize)
    .limit(pageSize)
    .findAll();
```

---

## ✍️ Writing Data

### Single Insert/Update

```dart
final todo = Todo()
  ..uuid = 'id-1'
  ..title = 'Buy milk'
  ..updatedAt = DateTime.now().toIso8601String();

await isar.writeTxn(() async {
  await isar.todos.put(todo);
});
```

### Batch Operations

```dart
final todos = [
  Todo()..uuid = '1'..title = 'Task 1',
  Todo()..uuid = '2'..title = 'Task 2',
  Todo()..uuid = '3'..title = 'Task 3',
];

await isar.writeTxn(() async {
  await isar.todos.putAll(todos);
});
```

### Update Specific Fields

```dart
final todo = await isar.todos
    .filter()
    .uuidEqualTo('id-1')
    .findFirst();

if (todo != null) {
  todo.completed = true;
  todo.updatedAt = DateTime.now().toIso8601String();
  
  await isar.writeTxn(() async {
    await isar.todos.put(todo);
  });
}
```

---

## 🗑️ Deleting Data

### Single Delete

```dart
final todo = await isar.todos
    .filter()
    .uuidEqualTo('id-1')
    .findFirst();

if (todo != null) {
  await isar.writeTxn(() async {
    await isar.todos.delete(todo.id!);
  });
}
```

### Batch Delete

```dart
await isar.writeTxn(() async {
  final toDelete = await isar.todos
      .filter()
      .completedEqualTo(true)
      .findAll();
  
  for (var todo in toDelete) {
    await isar.todos.delete(todo.id!);
  }
});
```

### Soft Delete

```dart
final todo = await isar.todos
    .filter()
    .uuidEqualTo('id-1')
    .findFirst();

if (todo != null) {
  todo.deletedAt = DateTime.now();
  
  await isar.writeTxn(() async {
    await isar.todos.put(todo);
  });
}
```

---

## 📊 Dirty Tracking

```dart
Future<List<Todo>> getDirtyRecords() async {
  return await isar.todos
      .filter()
      .dirtyEqualTo(1)
      .findAll();
}

Future<void> markClean(String uuid) async {
  final todo = await isar.todos
      .filter()
      .uuidEqualTo(uuid)
      .findFirst();
  
  if (todo != null) {
    todo.dirty = 0;
    await isar.writeTxn(() async {
      await isar.todos.put(todo);
    });
  }
}
```

---

## 📡 Reactive Streams

```dart
// Watch all todos
final stream = isar.todos.watchLazy();

stream.listen((todos) {
  print('Todos changed!');
  setState(() {});
});

// Watch specific query
final completedStream = isar.todos
    .filter()
    .completedEqualTo(true)
    .watch();

completedStream.listen((todos) {
  print('Completed todos: ${todos.length}');
});
```

---

## 🔐 Encryption

```dart
final isar = await Isar.open(
  [TodoSchema],
  directory: dir.path,
  encryptionKey: Isar.randomHash(),  // Or your key
);
```

---

## ⚡ Performance Tips

### ✅ DO

- ✅ Use `.writeTxn()` for batch operations
- ✅ Create indexes on filter/sort fields
- ✅ Use `.watch()` for reactive updates
- ✅ Use `.offset()` and `.limit()` for pagination
- ✅ Close Isar on app shutdown

### ❌ DON'T

- ❌ Do writes outside `.writeTxn()`
- ❌ Load entire large collections at once
- ❌ Ignore encryption for sensitive data

---

## 🎯 Isar vs Hive vs SQLite

| Feature | Isar | Hive | SQLite |
|---------|------|------|---------|
| Speed | ⚡⚡⚡ | ⚡⚡ | ⚡ |
| Size | 100K+ | 10K | 100K+ |
| Encryption | ✅ | ❌ | ❌ |
| Reactive | ✅ | ❌ | ❌ |
| Indexes | ✅✅ | ❌ | ✅ |
| Memory | Optimized | High | Low |
| Learning | Medium | Easy | Easy |

**Choose Isar if**: Speed, encryption, reactive, large datasets

---

## 🚀 Replicore with Isar

```dart
void setupIsarStore() async {
  final store = IsarLocalStore();
  await store.initialize();
  
  final engine = SyncEngine(
    localStore: store,
    remoteAdapter: firebaseAdapter,
  );
  
  await engine.initialize();
  
  // Watch for real-time updates
  isar.todos.watchLazy().listen((_) {
    setState(() {});
  });
}
```

---

## 🧪 Testing

```dart
test('isar store works', () async {
  final store = IsarLocalStore();
  await store.initialize();
  
  await store.upsert(table: 'todos', data: {
    'uuid': '1',
    'title': 'Test',
  });
  
  final todo = await store.read('todos', '1');
  expect(todo?['title'], 'Test');
});
```

---

**Isar is the fastest, most feature-rich local database for Flutter!** 🚀
