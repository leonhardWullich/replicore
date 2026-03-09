# Getting Started with Replicore

> **30-minute guide to build your first offline-first Flutter app**

---

## 📋 Prerequisites

Before starting, ensure you have:

- ✅ Flutter SDK (3.0+)
- ✅ Dart 3.0+
- ✅ A backend (Supabase/Firebase/Appwrite/GraphQL or REST API)
- ✅ 30 minutes of focused time

---

## 🚀 Step 1: Installation

### 1.1 Add Dependencies

**For Supabase + Sqflite (recommended for beginners):**

```bash
flutter pub add replicore sqflite supabase_flutter
```

**Or manually in `pubspec.yaml`:**

```yaml
dependencies:
  flutter:
    sdk: flutter
  replicore: ^0.5.1           # Core framework
  sqflite: ^2.4.2             # Local database
  supabase_flutter: ^2.12.0   # Backend
```

### 1.2 Get Packages

```bash
flutter pub get
```

---

## ✨ Step 2: Setup Your Backend

### Option A: Using Supabase (Recommended)

1. Create a free account at [supabase.com](https://supabase.com)
2. New project → choose region
3. Create a simple table:

```sql
CREATE TABLE todos (
  uuid UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  title TEXT NOT NULL,
  description TEXT,
  completed BOOLEAN DEFAULT false,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  deleted_at TIMESTAMP WITH TIME ZONE NULL
);
```

4. Copy your project URL and anon key from Settings → API

### Option B: Using Firebase

1. Create Firebase project at [firebase.google.com](https://firebase.google.com)
2. Enable Firestore
3. Create collection: `todos`
4. Enable anonymous authentication (for testing)

### Option C: Your Own REST API

If using your own backend, just ensure endpoints:
- `GET /api/todos?updated_after=2024-01-01`
- `POST /api/todos` (upsert)
- Return data with: `uuid`, `updated_at`, `deleted_at`

---

## 🔧 Step 3: Initialize Replicore

Create `lib/sync_engine.dart`:

```dart
import 'package:replicore/replicore.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Initialize Replicore with Sqflite + Supabase
Future<SyncEngine> initializeReplicore() async {
  // 1. Initialize local storage (Sqflite)
  final dbPath = await getDatabasesPath();
  final db = await openDatabase(
    '${dbPath}/app.db',
    version: 1,
    onCreate: (db, version) {
      // Tables created automatically by Replicore
    },
  );

  final localStore = SqfliteStore(db);

  // 2. Initialize remote adapter (Supabase)
  await Supabase.initialize(
    url: 'YOUR_SUPABASE_URL',
    anonKey: 'YOUR_SUPABASE_KEY',
  );

  final remoteAdapter = SupabaseAdapter(
    client: Supabase.instance.client,
  );

  // 3. Create SyncEngine
  final engine = SyncEngine(
    localStore: localStore,
    remoteAdapter: remoteAdapter,
    config: ReplicoreConfig.production(),
  );

  // 4. Register tables
  engine.registerTable(
    TableConfig(
      name: 'todos',
      primaryKey: 'uuid',
      updatedAtColumn: 'updated_at',
      deletedAtColumn: 'deleted_at',
      columns: ['uuid', 'title', 'description', 'completed', 'updated_at', 'deleted_at'],
      strategy: SyncStrategy.serverWins, // Resolve conflicts: server version wins
    ),
  );

  // 5. Initialize
  await engine.init();

  return engine;
}
```

---

## 📱 Step 4: Create Data Model

Create `lib/models/todo.dart`:

```dart
class Todo {
  final String uuid;
  final String title;
  final String? description;
  final bool completed;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  Todo({
    required this.uuid,
    required this.title,
    this.description,
    this.completed = false,
    required this.updatedAt,
    this.deletedAt,
  });

  bool get isDeleted => deletedAt != null;

  // Convert to Map for database storage
  Map<String, dynamic> toMap() => {
    'uuid': uuid,
    'title': title,
    'description': description,
    'completed': completed,
    'updated_at': updatedAt.toIso8601String(),
    'deleted_at': deletedAt?.toIso8601String(),
  };

  // Convert from database Map
  factory Todo.fromMap(Map<String, dynamic> map) => Todo(
    uuid: map['uuid'] as String,
    title: map['title'] as String,
    description: map['description'] as String?,
    completed: map['completed'] as bool? ?? false,
    updatedAt: DateTime.tryParse(map['updated_at'] as String? ?? '') ?? DateTime.now(),
    deletedAt: map['deleted_at'] != null ? DateTime.tryParse(map['deleted_at'] as String) : null,
  );
}
```

---

## 🏗️ Step 5: Create Repository

Create `lib/repositories/todo_repository.dart`:

```dart
import 'package:replicore/replicore.dart';
import 'models/todo.dart';

class TodoRepository {
  final SyncEngine syncEngine;

  TodoRepository({required this.syncEngine});

  // Get all non-deleted todos
  Future<List<Todo>> getTodos() async {
    // Read from local store (works offline!)
    final records = await syncEngine.getRecords('todos');
    
    return records
      .where((r) => r['deleted_at'] == null)
      .map((r) => Todo.fromMap(r))
      .toList();
  }

  // Create a new todo
  Future<void> createTodo(String title, {String? description}) async {
    final uuid = _generateUuid();
    
    // Write to local store immediately (optimistic update)
    await syncEngine.writeLocal(
      'todos',
      {
        'uuid': uuid,
        'title': title,
        'description': description,
        'completed': false,
        'updated_at': DateTime.now().toIso8601String(),
        'deleted_at': null,
      },
    );

    // Sync when network available (automatic)
  }

  // Update a todo
  Future<void> updateTodo(String uuid, {String? title, bool? completed}) async {
    final existing = await syncEngine.getSingleRecord('todos', uuid);
    if (existing == null) return;

    await syncEngine.writeLocal('todos', {
      ...existing,
      if (title != null) 'title': title,
      if (completed != null) 'completed': completed,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  // Soft delete (mark as deleted, preserve data)
  Future<void> deleteTodo(String uuid) async {
    await syncEngine.writeLocal('todos', {
      'uuid': uuid,
      'updated_at': DateTime.now().toIso8601String(),
      'deleted_at': DateTime.now().toIso8601String(),
    });
  }

  // Manually sync (optional - automatic by default)
  Future<void> sync() async {
    await syncEngine.sync();
  }

  String _generateUuid() => const Uuid().v4();
}
```

---

## 🎨 Step 6: Build UI

Create `lib/screens/todos_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'repositories/todo_repository.dart';
import 'models/todo.dart';

class TodosScreen extends StatefulWidget {
  final TodoRepository repository;

  const TodosScreen({required this.repository});

  @override
  State<TodosScreen> createState() => _TodosScreenState();
}

class _TodosScreenState extends State<TodosScreen> {
  late Future<List<Todo>> _todosFuture;
  final _titleController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadTodos();
  }

  void _loadTodos() {
    _todosFuture = widget.repository.getTodos();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Todos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(_loadTodos),
          ),
        ],
      ),
      body: FutureBuilder<List<Todo>>(
        future: _todosFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Error: ${snapshot.error}'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => setState(_loadTodos),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final todos = snapshot.data ?? [];

          return Column(
            children: [
              // Input field
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _titleController,
                        decoration: InputDecoration(
                          hintText: 'Add a new todo...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _addTodo,
                      child: const Icon(Icons.add),
                    ),
                  ],
                ),
              ),

              // Todos list
              Expanded(
                child: todos.isEmpty
                  ? const Center(child: Text('No todos yet'))
                  : ListView.builder(
                      itemCount: todos.length,
                      itemBuilder: (context, index) {
                        final todo = todos[index];
                        return ListTile(
                          leading: Checkbox(
                            value: todo.completed,
                            onChanged: (_) =>
                              widget.repository.updateTodo(
                                todo.uuid,
                                completed: !todo.completed,
                              ),
                          ),
                          title: Text(
                            todo.title,
                            style: TextStyle(
                              decoration: todo.completed
                                ? TextDecoration.lineThrough
                                : null,
                            ),
                          ),
                          subtitle: todo.description != null
                            ? Text(todo.description!)
                            : null,
                          trailing: IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () =>
                              widget.repository.deleteTodo(todo.uuid),
                          ),
                        );
                      },
                    ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _addTodo() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    _titleController.clear();
    await widget.repository.createTodo(title);
    setState(_loadTodos);
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }
}
```

---

## 🎯 Step 7: Update main.dart

```dart
import 'package:flutter/material.dart';
import 'sync_engine.dart';
import 'repositories/todo_repository.dart';
import 'screens/todos_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Replicore
  final syncEngine = await initializeReplicore();
  
  // Start automatic syncing
  syncEngine.startAutoSync(
    interval: Duration(seconds: 30), // Sync every 30 seconds
  );

  runApp(MyApp(
    syncEngine: syncEngine,
  ));
}

class MyApp extends StatelessWidget {
  final SyncEngine syncEngine;

  const MyApp({required this.syncEngine});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Todo App',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: TodosScreen(
        repository: TodoRepository(syncEngine: syncEngine),
      ),
    );
  }
}
```

---

## ✅ Step 8: Test It!

1. **Run the app:**
   ```bash
   flutter run
   ```

2. **Add a todo** - it appears immediately (optimistic update)

3. **Go offline** - edit or add todos, they persist locally

4. **Go back online** - changes sync automatically to server

5. **Check Supabase Console** - see your data in the database

---

## 🎉 You Did It!

Your first offline-first app is working! Here's what just happened:

✅ **Immediate response**: Changes appear instantly in the UI
✅ **Works offline**: Changes persist even without network
✅ **Auto-sync**: Background sync pushes changes when online
✅ **Conflict resolution**: Server version wins (configurable)
✅ **Soft deletes**: Deletions preserved, not permanently lost

---

## 🚀 Next Steps

Now that basics are working, explore:

### Learn More
- [Architecture Overview](./02_ARCHITECTURE.md) - How it all works
- [Conflict Resolution](./04_CONFLICT_RESOLUTION.md) - Custom strategies
- [Real-Time Sync](./REALTIME_SUBSCRIPTIONS.md) - Live updates

### Add Features
- **Real-time updates**: Add WebSocket sync
- **Authentication**: Protect with RLS policies
- **Logging**: Monitor what's happening
- **Error handling**: Graceful failure recovery
- **Custom resolver**: Smart conflict handling

### Optimize
- [Performance Guide](./10_PERFORMANCE_OPTIMIZATION.md) - Scale to millions
- Local store tuning
- Batch operations
- Monitoring and metrics

---

## 🐛 Troubleshooting

### "Column not found" error
**Solution**: Make sure `updated_at` and `deleted_at` exist in your table

### Sync not working
**Solution**: Check network connection and backend credentials

### Data not appearing
**Solution**: Call `syncEngine.sync()` manually to trigger sync

### "Table doesn't exist"
**Solution**: Replicore creates the table automatically on first sync

---

## 📚 Learn by Example

Full working example: [../example/lib/main.dart](../example/lib/main.dart)

---

**Congratulations!** 🎊 You've built your first Replicore app!

For questions: Check [FAQ](./18_FAQ.md) or the example app.
