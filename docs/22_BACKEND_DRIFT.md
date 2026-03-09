# Local Storage: Drift

> **Type-safe SQLite wrapper with reactive streams**

---

## 🎯 Why Drift?

### ✅ Strengths
- **Type-safe**: Dart code generation, no SQL
- **Reactive**: Stream-based updates
- **Powerful queries**: Full SQL capabilities
- **Performance**: Better than raw SQLite
- **Hot reload**: Automatic schema updates
- **Multi-platform**: Mobile, web, desktop

### ❌ Weaknesses
- **Code generation**: Requires build runner
- **Boilerplate**: More setup than Hive
- **Learning curve**: Different paradigm from SQLite

---

## 📦 Installation

```bash
flutter pub add drift sqlite3_flutter_libs
flutter pub add dev:drift_dev build_runner
```

---

## 🏗️ Define Schema

```dart
import 'package:drift/drift.dart';

part 'database.g.dart';

// Table definition
class Todos extends Table {
  TextColumn get uuid => text()();
  TextColumn get title => text()();
  BoolColumn get completed => boolean().withDefault(const Constant(false))();
  TextColumn get updatedAt => text()();
  IntColumn get dirty => integer().withDefault(const Constant(0))();
  
  @override
  Set<Column> get primaryKey => {uuid};
}

// Database class
@DriftDatabase(tables: [Todos])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());
  
  @override
  int get schemaVersion => 1;
  
  // Insert/Update
  Future<void> insertTodo(TodosCompanion todo) {
    return into(todos).insert(todo, mode: InsertMode.replace);
  }
  
  // Read single
  Future<Todo?> getTodo(String uuid) {
    return (select(todos)..where((t) => t.uuid.equals(uuid)))
        .getSingleOrNull();
  }
  
  // Read all
  Future<List<Todo>> getAllTodos() {
    return select(todos).get();
  }
  
  // Get dirty records
  Future<List<Todo>> getDirtyRecords() {
    return (select(todos)..where((t) => t.dirty.equals(1)))
        .get();
  }
  
  // Mark as dirty
  Future<void> markDirty(String uuid) {
    return (update(todos)..where((t) => t.uuid.equals(uuid)))
        .write(const TodosCompanion(dirty: Value(1)));
  }
  
  // Delete
  Future<void> deleteTodo(String uuid) {
    return (delete(todos)..where((t) => t.uuid.equals(uuid)))
        .go();
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final file = File(p.join(
      await getDatabasesPath(),
      'app.db',
    ));
    return NativeDatabase(file);
  });
}
```

---

## 🛠️ Generate Code

```bash
flutter pub run build_runner build
```

---

## 🚀 DriftLocalStore Implementation

```dart
class DriftLocalStore extends LocalStore {
  final AppDatabase database;
  
  DriftLocalStore(this.database);
  
  @override
  Future<void> initialize() async {
    // Database already initialized in main()
  }
  
  @override
  Future<Map?> read(String table, String primaryKey) async {
    if (table == 'todos') {
      final todo = await database.getTodo(primaryKey);
      return todo?.toJsonMap();
    }
    return null;
  }
  
  @override
  Future<List<Map>> readAll(String table) async {
    if (table == 'todos') {
      final todos = await database.getAllTodos();
      return todos.map((t) => t.toJsonMap()).toList();
    }
    return [];
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
    // Drift queries are type-safe and in Dart
    if (table == 'todos') {
      var query = select(database.todos);
      
      if (orderBy != null) {
        // Parse "columnName ASC/DESC"
        final parts = orderBy.split(' ');
        final column = parts[0];
        final isAsc = parts.length < 2 || parts[1] == 'ASC';
        
        // Apply sort
        // (Drift-specific implementation)
      }
      
      if (limit != null) {
        query = query.limit(limit, offset: offset ?? 0);
      }
      
      final results = await query.get();
      return results.map((t) => t.toJsonMap()).toList();
    }
    return [];
  }
  
  @override
  Future<void> upsert({
    required String table,
    required Map<String, Object?> data,
  }) async {
    if (table == 'todos') {
      final companion = TodosCompanion(
        uuid: Value(data['uuid'] as String),
        title: Value(data['title'] as String),
        completed: Value((data['completed'] as int?) == 1),
        updatedAt: Value(data['updated_at'] as String),
        dirty: Value((data['dirty'] as int?) ?? 0),
      );
      await database.insertTodo(companion);
    }
  }
  
  @override
  Future<void> markDirty(
    String table,
    String primaryKey,
    SyncDirection direction,
  ) async {
    if (table == 'todos') {
      await database.markDirty(primaryKey);
    }
  }
  
  @override
  Future<List<Map>> getDirtyRecords(String table) async {
    if (table == 'todos') {
      final dirty = await database.getDirtyRecords();
      return dirty.map((t) => t.toJsonMap()).toList();
    }
    return [];
  }
}
```

---

## 📖 Queries with Drift

### Simple Select

```dart
// Single item
final todo = await db.getTodo('id-1');

// All items
final all = await db.getAllTodos();

// With stream (reactive)
final stream = select(db.todos).watch();
stream.listen((todos) {
  print('Updated: $todos');
});
```

### Complex Queries

```dart
// Where clause
var query = select(db.todos)
  ..where((t) => t.completed.equals(false));
final incomplete = await query.get();

// Order and limit
query = select(db.todos)
  ..where((t) => t.completed.equals(false))
  ..orderBy([(t) => OrderingTerm(expression: t.updatedAt)])
  ..limit(10);

// Count
final count = await (select(db.todos)
  ..where((t) => t.dirty.equals(1)))
  .get()
  .then((list) => list.length);
```

---

## ✍️ Insert/Update

```dart
// Single insert
await db.insertTodo(TodosCompanion(
  uuid: const Value('new-id'),
  title: const Value('New Todo'),
  completed: const Value(false),
  updatedAt: Value(DateTime.now().toIso8601String()),
));

// Batch insert
await db.batch((batch) {
  batch.insertAll(
    db.todos,
    [
      TodosCompanion(uuid: ... ),
      TodosCompanion(uuid: ... ),
    ],
  );
});

// Update
await (update(db.todos)
  ..where((t) => t.uuid.equals('id-1')))
  .write(TodosCompanion(
    title: const Value('Updated Title'),
    completed: const Value(true),
  ));
```

---

## 🗑️ Delete

```dart
// Single
await (delete(db.todos)
  ..where((t) => t.uuid.equals('id-1')))
  .go();

// Batch
await db.batch((batch) {
  batch.deleteWhere(
    db.todos,
    (t) => t.uuid.isIn(['id-1', 'id-2', 'id-3']),
  );
});
```

---

## 📊 Transactions

```dart
await db.transaction(() async {
  // All queries here are atomic
  final todo = await db.getTodo('id');
  if (todo != null) {
    await db.deleteTodo('id');
  }
});
```

---

## ⏰ Sync Metadata

```dart
class SyncMetadata extends Table {
  TextColumn get table => text()();
  TextColumn get lastSync => text()();
}

// Get last sync
final metadata = await (select(db.syncMetadata)
  ..where((m) => m.table.equals('todos')))
  .getSingleOrNull();

final lastSync = DateTime.parse(
  metadata?.lastSync ?? DateTime(2000).toIso8601String(),
);
```

---

## 💡 Reactive Streams

```dart
// Watch for changes
final stream = select(db.todos).watch();

stream.listen((todos) {
  print('Todos changed: $todos');
  setState(() {});  // Rebuild UI
});

// Specific column
final completedStream = (select(db.todos)
  ..where((t) => t.completed.equals(true)))
  .watch();
```

---

## ⚡ Performance Tips

### ✅ DO

- ✅ Use batch operations for bulk inserts
- ✅ Create indexes on frequently queried columns
- ✅ Use transactions for consistency
- ✅ Watch streams for reactive updates

### ❌ DON'T

- ❌ Load entire table for small queries
- ❌ Ignore transactions
- ❌ Create unnecessary indexes

---

## 🏃 Drift vs SQLite vs Hive

| Feature | Drift | SQLite | Hive |
|---------|-------|--------|------|
| Type-safety | ✅✅ | ❌ | ✅ |
| Reactive | ✅✅ | ❌ | ❌ |
| Query power | ✅✅ | ✅✅ | ❌ |
| Simplicity | ❌ | ✅ | ✅✅ |
| Setup | Medium | Easy | Easy |
| Large datasets | ✅ | ✅✅ | ❌ |

**Choose Drift if**: Need type-safety, reactive streams, large datasets

---

## 🚀 Replicore with Drift

```dart
void setupDriftStore() async {
  final database = AppDatabase();
  final store = DriftLocalStore(database);
  
  final engine = SyncEngine(
    localStore: store,
    remoteAdapter: firebaseAdapter,
  );
  
  await engine.initialize();
  
  // Subscribe to changes
  select(database.todos).watch().listen((todos) {
    print('Todos updated: ${todos.length}');
  });
}
```

---

## 🧪 Testing

```dart
test('drift store works', () async {
  final db = AppDatabase();
  
  // Insert
  await db.insertTodo(TodosCompanion(
    uuid: const Value('1'),
    title: const Value('Test'),
  ));
  
  // Read and verify
  final todo = await db.getTodo('1');
  expect(todo?.title, 'Test');
});
```

---

**Drift is perfect for type-safe, reactive mobile apps!** ✨
