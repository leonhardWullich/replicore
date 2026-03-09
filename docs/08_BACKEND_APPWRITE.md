# Backend Integration: Appwrite

> **Setup guide for self-hosted Appwrite BaaS platform**

---

## 🎯 When to Use Appwrite

**Best for**:
- Self-hosted backends
- No vendor lock-in
- Open-source preference
- Enterprise control

| Aspect | Rating | Notes |
|--------|--------|-------|
| **Setup** | ⭐⭐⭐⭐ | Docker installation |
| **Self-Hosted** | ⭐⭐⭐⭐⭐ | Full control |
| **Real-Time** | ⭐⭐⭐⭐ | WebSocket support |
| **Batch Ops** | ⭐⭐⭐ | Parallel execution |
| **Cost** | ⭐⭐⭐⭐⭐ | Your infrastructure |

---

## 📦 Installation

```bash
flutter pub add appwrite
```

---

## 🚀 Setup Appwrite Server

### Docker Installation

```bash
git clone https://github.com/appwrite/appwrite.git
cd appwrite
docker compose up

# Access at http://localhost
```

### Create Project

1. Visit http://localhost
2. Create account
3. New project
4. Copy project ID

---

## 🔧 Setup with Replicore

### Initialize Client

```dart
import 'package:appwrite/appwrite.dart';

final client = Client()
  .setEndpoint('http://YOUR_APPWRITE_URL')
  .setProject('YOUR_PROJECT_ID')
  .setSelfSigned(enableSelfSigned: true);

final databases = Databases(client);
```

### Setup with Replicore

```dart
Future<SyncEngine> initializeReplicore() async {
  final db = await openAppDatabase();
  final localStore = SqfliteStore(db);
  
  final remoteAdapter = AppwriteAdapter(
    client: client,
    databases: databases,
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

## 📊 Create Collection

### Via Appwrite Console

1. Database → New Database
2. Create collection: `todos`
3. Add attributes:
   - `uuid` (String, Required)
   - `title` (String, Required)
   - `completed` (Boolean)
   - `updated_at` (DateTime)
   - `deleted_at` (DateTime, optional)

### Via API

```dart
await databases.createCollection(
  databaseId: 'DATABASE_ID',
  collectionId: 'todos',
  name: 'Todos',
  permissions: [
    Permission.read(Role.user('USER_ID')),
    Permission.write(Role.user('USER_ID')),
  ],
);

await databases.createStringAttribute(
  databaseId: 'DATABASE_ID',
  collectionId: 'todos',
  key: 'uuid',
  size: 36,
  required: true,
);

// ... add other attributes
```

---

## ✍️ Reading & Writing

### Read Records

```dart
final response = await databases.listDocuments(
  databaseId: 'DATABASE_ID',
  collectionId: 'todos',
  queries: [
    Query.equal('user_id', userId),
    Query.isNull('deleted_at'),
    Query.orderDesc('updated_at'),
    Query.limit(20),
  ],
);

final todos = response.documents;
```

### Insert Document

```dart
await databases.createDocument(
  databaseId: 'DATABASE_ID',
  collectionId: 'todos',
  documentId: 'uuid-123',
  data: {
    'uuid': 'uuid-123',
    'title': 'New Todo',
    'user_id': userId,
    'updated_at': DateTime.now().toIso8601String(),
  },
  permissions: [
    Permission.read(Role.user(userId)),
    Permission.write(Role.user(userId)),
  ],
);
```

### Batch Operations

```dart
// Appwrite doesn't have true batch
// Replicore uses parallel execution (5-10x faster)
final futures = records.map((record) async {
  return await databases.createDocument(
    databaseId: DATABASE_ID,
    collectionId: 'todos',
    documentId: record['uuid'],
    data: record,
  );
});

final results = await Future.wait(futures);
```

---

## 🔄 Real-Time Subscriptions

### Subscribe

```dart
final realtime = Realtime(client);

realtime
  .subscribe(['databases.DATABASE_ID.collections.todos.documents'])
  .stream
  .listen((response) {
    print('Event: ${response.events}');
    // Trigger auto-sync
  });
```

---

## 🔒 Permissions

### Document-Level Security

```dart
await databases.updateDocument(
  databaseId: 'DATABASE_ID',
  collectionId: 'todos',
  documentId: 'doc-id',
  data: {'title': 'Updated'},
  permissions: [
    Permission.read(Role.user(userId)),
    Permission.write(Role.user(userId)),
  ],
);
```

---

## ⚡ Performance Tips

### Indexes

```dart
await databases.createIndex(
  databaseId: 'DATABASE_ID',
  collectionId: 'todos',
  key: 'user_id_updated_at',
  type: 'unique', // or 'key'
  attributes: ['user_id', 'updated_at'],
  orders: ['ASC', 'DESC'],
);
```

### Query Limits

```dart
// Always paginate
final response = await databases.listDocuments(
  databaseId: 'DATABASE_ID',
  collectionId: 'todos',
  queries: [
    Query.limit(50),
    Query.offset(0), // Second page: offset(50)
  ],
);
```

---

## 🧪 Testing

### Local Testing

```dart
final client = Client()
  .setEndpoint('http://localhost/v1')
  .setProject('YOUR_PROJECT_ID')
  .setSelfSigned(enableSelfSigned: true);
```

---

## 🚀 Production Checklist

- [ ] Appwrite server deployed
- [ ] Backup strategy documented
- [ ] Permissions reviewed
- [ ] Real-time subscriptions managed
- [ ] Error handling implemented
- [ ] Query limits enforced

---

**Appwrite gives you full control over your backend!** 🚀
