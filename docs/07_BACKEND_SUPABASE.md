# Backend Integration: Supabase (PostgreSQL)

> **Setup guide for Supabase with PostgreSQL, real-time, and RLS**

---

## 🎯 When to Use Supabase

**Best for**:
- PostgreSQL expertise
- Need SQL power
- Real-time + authentication
- Self-hosted options available

| Aspect | Rating | Notes |
|--------|--------|-------|
| **Setup** | ⭐⭐⭐⭐ | Create project online |
| **Real-Time** | ⭐⭐⭐⭐⭐ | Native PostgreSQL triggers |
| **Batch Ops** | ⭐⭐⭐⭐⭐ | True SQL UPSERT (best!) |
| **SQL Power** | ⭐⭐⭐⭐⭐ | Full PostgreSQL |
| **RLS** | ⭐⭐⭐⭐⭐ | Row-level security |

---

## 📦 Installation

```bash
flutter pub add supabase_flutter
```

---

## 🔧 Setup

### Initialize Supabase

```dart
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Supabase.initialize(
    url: 'YOUR_SUPABASE_URL',
    anonKey: 'YOUR_ANON_KEY',
  );
  
  runApp(const MyApp());
}
```

### Create Table in PostgreSQL

```sql
CREATE TABLE todos (
  uuid uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  title text NOT NULL,
  description text,
  completed boolean DEFAULT false,
  user_id uuid REFERENCES auth.users(id),
  updated_at timestamp with time zone DEFAULT now(),
  deleted_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now()
);

-- Enable RLS
ALTER TABLE todos ENABLE ROW LEVEL SECURITY;

-- User can only access their own
CREATE POLICY "User access" ON todos
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- Indexes
CREATE INDEX idx_todos_user ON todos(user_id);
CREATE INDEX idx_todos_updated ON todos(updated_at, uuid);
```

### Setup with Replicore

```dart
Future<SyncEngine> initializeReplicore() async {
  final db = await openAppDatabase();
  final localStore = SqfliteStore(db);
  
  final remoteAdapter = SupabaseAdapter(
    client: Supabase.instance.client,
  );
  
  final engine = SyncEngine(
    localStore: localStore,
    remoteAdapter: remoteAdapter,
  );
  
  await engine.init();
  return engine;
}
```

---

## ✍️ Reading & Writing

### Query Records

```dart
final response = await Supabase.instance.client
  .from('todos')
  .select()
  .eq('user_id', userId)
  .is_('deleted_at', null)
  .order('updated_at', ascending: false);

final todos = response as List;
```

### Insert Record

```dart
await Supabase.instance.client
  .from('todos')
  .insert({
    'title': 'New Todo',
    'user_id': userId,
    'updated_at': DateTime.now().toIso8601String(),
  });
```

### Batch Upsert (OPTIMAL!)

```dart
// Supabase does true SQL UPSERT in single call
await Supabase.instance.client
  .from('todos')
  .upsert(
    [
      {'uuid': '1', 'title': 'Todo 1'},
      {'uuid': '2', 'title': 'Todo 2'},
      {'uuid': '3', 'title': 'Todo 3'},
    ],
    onConflict: 'uuid',  // Use UUID as key
  );

// ✅ Benefits:
// - Single network request
// - Atomic transaction
// - Batch operations (v0.5.1+)
// - 100x faster than sequential!
```

---

## 🔄 Real-Time Subscriptions

### Listen to Changes

```dart
Supabase.instance.client
  .from('todos')
  .on(RealtimeListenTypes.all, (payload) {
    print('Change received: ${payload.eventType}');
    // AutoSync triggered
  })
  .subscribe();
```

### With Replicore

```dart
// Automatic through RealtimeSubscriptionProvider
await engine.startAutoSync(
  realTime: true,
  interval: Duration(seconds: 30),
);
```

---

## 🔐 Row-Level Security (RLS)

### Enable RLS

```sql
ALTER TABLE todos ENABLE ROW LEVEL SECURITY;

CREATE POLICY "user_todos" ON todos
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
```

### Verify in App

```dart
// Supabase auth automatically used
final user = Supabase.instance.client.auth.currentUser;
print('Authenticated as: ${user?.id}');

// Queries automatically filtered by RLS
// User only sees their own todos
```

---

## ⚡ Performance Tips

### Use Prepared Statements

```dart
// ✅ Parameterized
await client
  .from('todos')
  .select()
  .eq('user_id', userId)  // Parameter
  .ilike('title', '%$search%');  // Escaped

// ❌ Don't concatenate
await client.from('todos').select().filter('title', 'like', '%$search%');
```

### Indexes

```sql
-- Query by user
CREATE INDEX idx_todos_user_updated 
  ON todos(user_id, updated_at DESC);

-- Filter soft deletes efficiently
CREATE INDEX idx_todos_active 
  ON todos(user_id) 
  WHERE deleted_at IS NULL;
```

### Pagination

```dart
const limit = 20;

final first = await client
  .from('todos')
  .select()
  .eq('user_id', userId)
  .order('updated_at', ascending: false)
  .range(0, limit - 1);

// Next page
final second = await client
  .from('todos')
  .select()
  .eq('user_id', userId)
  .order('updated_at', ascending: false)
  .range(limit, limit * 2 - 1);
```

---

## 🐛 Common Issues

### Issue: No rows returned

```
Error: no rows returned
```

**Solution**: Check RLS policies

```sql
-- Verify current user
SELECT auth.uid();

-- Check policies
SELECT * FROM pg_policies WHERE tablename = 'todos';
```

### Issue: Slow Queries

**Solution**: Add indexes

```sql
EXPLAIN ANALYZE
SELECT * FROM todos 
WHERE user_id = $1 
AND deleted_at IS NULL
ORDER BY updated_at DESC;

-- Then create index if needed
CREATE INDEX idx_todos_query 
  ON todos(user_id, updated_at DESC) 
  WHERE deleted_at IS NULL;
```

---

## 📈 Scaling

### Partitioning Large Tables

```sql
-- Partition by user_id for multi-tenant
CREATE TABLE todos_partitioned (
  uuid uuid,
  user_id uuid,
  -- ... columns ...
) PARTITION BY HASH (user_id);

CREATE TABLE todos_partitioned_1 PARTITION OF todos_partitioned
  FOR VALUES WITH (MODULUS 10, REMAINDER 0);
```

### Archiving Old Data

```sql
-- Move old records to archive
INSERT INTO todos_archive
SELECT * FROM todos 
WHERE deleted_at < NOW() - INTERVAL '90 days';

DELETE FROM todos 
WHERE deleted_at < NOW() - INTERVAL '90 days';

VACUUM ANALYZE todos;
```

---

## 🧪 Testing

### Local Development

```bash
# Start Supabase locally
supabase start

# Reset database
supabase db reset
```

---

## 🚀 Production Checklist

- [ ] User Authentication required
- [ ] RLS policies enabled
- [ ] Indexes created for common queries
- [ ] Batch operations tested
- [ ] Real-time subscriptions active
- [ ] Backup strategy documented
- [ ] Production secrets secured
- [ ] Query performance monitored

---

**Supabase is the best for batch operations and PostgreSQL power!** 💜
