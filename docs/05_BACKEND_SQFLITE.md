# Backend Integration: SQLite (Sqflite) ⭐ Recommended

> **Setup guide for Sqflite. Battle-tested, zero-config, production-ready**

---

## 🎯 Why Sqflite?

**Best for**: 95% of Flutter apps

| Aspect | Rating | Notes |
|--------|--------|-------|
| **Setup** | ⭐⭐⭐⭐⭐ | Zero dependencies, works everywhere |
| **Performance** | ⭐⭐⭐⭐⭐ | Native SQLite, blazing fast |
| **Reliability** | ⭐⭐⭐⭐⭐ | Battle-tested by millions |
| **Features** | ⭐⭐⭐⭐ | Full SQL, transactions, indexing |
| **Learning Curve** | ⭐⭐⭐⭐⭐ | Simple API, great docs |
| **Production Ready** | ⭐⭐⭐⭐⭐ | Used in thousands of apps |

---

## 📦 Installation

### 1. Add Dependency

```bash
flutter pub add sqflite
```

Or in `pubspec.yaml`:
```yaml
dependencies:
  sqflite: ^2.4.2
  path: ^1.9.0
```

### 2. Get Packages

```bash
flutter pub get
```

**That's it!** No native setup needed. Works on iOS, Android, macOS.

---

## 🔧 Basic Setup

### Creating Database

```dart
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

Future<Database> openAppDatabase() async {
  final dbPath = await getDatabasesPath();
  final path = join(dbPath, 'myapp.db');
  
  return openDatabase(
    path,
    version: 1,
    onCreate: (db, version) async {
      // Tables created automatically by Replicore
      // But you can create custom indexes here
    },
  );
}
```

### Initialize with Replicore

```dart
Future<SyncEngine> initializeReplicore() async {
  final db = await openAppDatabase();
  
  final localStore = SqfliteStore(db);
  final remoteAdapter = SupabaseAdapter(...);
  
  final engine = SyncEngine(
    localStore: localStore,
    remoteAdapter: remoteAdapter,
  );
  
  await engine.init();
  return engine;
}
```

---

## 📊 Creating Tables

### Automatic Table Creation

Replicore creates tables automatically with required columns:

```dart
engine.registerTable(
  TableConfig(
    name: 'todos',
    primaryKey: 'uuid',
    updatedAtColumn: 'updated_at',
    deletedAtColumn: 'deleted_at',
    columns: ['uuid', 'title', 'description', 'completed', 'updated_at', 'deleted_at'],
  ),
);

await engine.init(); // Creates table if not exists
```

**Generated SQL**:
```sql
CREATE TABLE IF NOT EXISTS todos (
  uuid TEXT PRIMARY KEY,
  title TEXT,
  description TEXT,
  completed INTEGER DEFAULT 0,
  updated_at TEXT,
  deleted_at TEXT,
  is_synced INTEGER DEFAULT 0,  -- Local tracking
  _operation_id TEXT             -- Local idempotency
);

-- Plus auto-created indexes for performance
CREATE INDEX idx_todos_updated_at 
  ON todos(updated_at, uuid);
CREATE INDEX idx_todos_is_synced 
  ON todos(is_synced);
```

### Custom Indexes for Performance

Add custom indexes in `onCreate`:

```dart
openDatabase(
  path,
  version: 1,
  onCreate: (db, version) async {
    // Replicore creates needed indexes, but add extras:
    
    // Index for queries
    await db.execute(
      'CREATE INDEX idx_todos_completed ON todos(completed)'
    );
    
    // Composite index for filtering
    await db.execute('''
      CREATE INDEX idx_todos_active ON todos(completed, updated_at)
      WHERE deleted_at IS NULL
    ''');
  },
);
```

---

## 📖 Reading Data

### Get All Records

```dart
final todos = await engine.getRecords('todos');

// Result:
// [{uuid: '1', title: 'Buy milk', ...}, ...]
```

### Read with Filtering

```dart
// Sqflite's raw SQL queries
final completed = await db.query(
  'todos',
  where: 'completed = ? AND deleted_at IS NULL',
  whereArgs: [1],
  orderBy: 'updated_at DESC',
);
```

### Read Single Record

```dart
final todo = await engine.getSingleRecord('todos', 'uuid-123');
```

---

## ✍️ Writing Data

### Insert New Record

```dart
await engine.writeLocal('todos', {
  'uuid': 'generated-uuid',
  'title': 'New Todo',
  'description': '',
  'completed': 0,
  'updated_at': DateTime.now().toIso8601String(),
  'deleted_at': null,
});
```

### Update Existing

```dart
await engine.writeLocal('todos', {
  'uuid': 'existing-uuid',
  'title': 'Updated Title',
  'updated_at': DateTime.now().toIso8601String(),
});
```

### Batch Operations

Replicore v0.5.1+ batches automatically:

```dart
// Push 1000 records
// Internally: Single batch operation (not 1000!
await engine.sync();
```

---

## 🔄 Transactions

For atomicity (either all succeed or all fail):

```dart
await db.transaction((txn) async {
  // Multiple operations happen together
  
  await txn.insert('todos', record1);
  await txn.insert('todos', record2);
  await txn.insert('todos', record3);
  
  // Either all three insert, or none
  // Automatic rollback on error
});
```

---

## ⚡ Performance Optimization

### 1. Use Prepared Statements

```dart
// ✅ GOOD - Uses parameter binding
await db.query(
  'todos',
  where: 'uuid = ?',
  whereArgs: ['123'],
);

// ❌ WRONG - String concatenation = SQL injection risk
await db.rawQuery("SELECT * FROM todos WHERE uuid = '$uuid'");
```

### 2. Add Strategic Indexes

```dart
// For frequent queries
await db.execute(
  'CREATE INDEX idx_by_status ON todos(completed, updated_at)'
);
```

### 3. Batch Inserts

```dart
// ❌ SLOW
for (final record in records) {
  await db.insert('todos', record);  // 1000 individual calls!
}

// ✅ FAST
await db.transaction((txn) async {
  for (final record in records) {
    await txn.insert('todos', record);  // Single transaction
  }
});
```

### 4. Limit Queries

```dart
// ❌ Load all data
final all = await db.query('todos');  // 100K records into memory!

// ✅ Paginate
final page = await db.query(
  'todos',
  limit: 100,
  offset: 0,
  orderBy: 'updated_at DESC',
);
```

---

## 🐛 Common Issues & Solutions

### Issue: Database Locked

```
Error: database is locked
```

**Causes**: Multiple writes at same time

**Solution**:
```dart
// Use transaction for write operations
await db.transaction((txn) async {
  await txn.insert('todos', record);
  await txn.insert('logs', logRecord);
});
```

### Issue: Column Not Found

```
Error: no such column: updated_at
```

**Solution**: Make sure table has all required columns:
```dart
// Check required columns
columns: ['uuid', 'title', 'updated_at', 'deleted_at']
```

### Issue: Out of Memory

```
Error: Out of memory (loading 1M records)
```

**Solution**: Paginate queries:
```dart
const pageSize = 1000;
for (int i = 0; i < totalRecords; i += pageSize) {
  final page = await db.query(
    'todos',
    limit: pageSize,
    offset: i,
  );
  processPage(page);
}
```

---

## 🔒 Security

### Prevent SQL Injection

```dart
// ✅ SAFE - Use whereArgs
await db.query(
  'todos',
  where: 'user_id = ?',
  whereArgs: [userId],
);

// ❌ UNSAFE - Don't concatenate
await db.rawQuery("WHERE user_id = '$userId'");
```

### Encrypt Sensitive Data

```dart
import 'package:sqflite_common_ffi_web_web/sqflite_ffi_web.dart';

// Enable SQLCipher for encryption
final db = await openDatabase(
  path,
  password: 'your-secure-password',  // Encrypts DB file
);
```

---

## 📈 Scaling

### With Million+ Records

1. **Use Pagination** - Never load all data
2. **Add Indexes** - For filter columns
3. **Archive Old Data** - Move to separate table
4. **Vacuum Periodically** - Clean up space

```dart
// Periodic maintenance
Future<void> optimizeDatabase(Database db) async {
  // Remove old deleted records
  await db.delete(
    'todos',
    where: 'deleted_at IS NOT NULL AND deleted_at < ?',
    whereArgs: [DateTime.now()
      .subtract(Duration(days: 30))
      .toIso8601String()],
  );
  
  // Reclaim space
  await db.execute('VACUUM');
}
```

---

## 🧪 Testing

### Mock Database

```dart
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  
  test('todo operations', () async {
    final db = await openDatabase(
      inMemoryDatabasePath,
      version: 1,
    );
    
    // Acts like real SQLite, but in memory
    // Fast, no cleanup needed
  });
}
```

---

## 🚀 Production Checklist

- [ ] Database path is platform-specific
- [ ] All required columns created
- [ ] Indexes created for queries  
- [ ] Error handling for locked DB
- [ ] Backup strategy planned
- [ ] Pagination for large data
- [ ] SQL injection prevention
- [ ] Tests with in-memory DB
- [ ] Version migration strategy

---

## 📚 Further Reading

- [Sqflite Documentation](https://github.com/tekartik/sqflite)
- [SQLite Best Practices](https://www.sqlite.org/bestpractice.html)
- [Replicore Architecture](./02_ARCHITECTURE.md)

---

**Sqflite is battle-tested and production-ready. Use it!** ⭐
