# Backend Integration: Firebase Firestore

> **Setup guide for Firestore with real-time capabilities and native offline support**

---

## 🎯 When to Use Firebase

**Best for**:
- Real-time collaborative apps
- Mobile-first apps with native offline
- Apps needing Firebase ecosystem

| Aspect | Rating | Notes |
|--------|--------|-------|
| **Setup** | ⭐⭐⭐⭐ | Firebase project required |
| **Real-Time** | ⭐⭐⭐⭐⭐ | Native, built-in |
| **Batch Ops** | ⭐⭐⭐⭐ | Batch API (500 ops max) |
| **Cost** | ⭐⭐⭐⭐ | Pay per operation |
| **Offline** | ⭐⭐⭐⭐⭐ | Native offline persistence |

---

## 📦 Installation

### 1. Add Dependencies

```bash
flutter pub add firebase_core cloud_firestore firebase_auth
```

### 2. Initialize Firebase

```dart
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  runApp(const MyApp());
}
```

### 3. Run Firebase CLI

```bash
flutterfire configure
```

This creates `firebase_options.dart` automatically.

---

## 🔧 Setup with Replicore

### Create Firestore Adapter

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:replicore/adapters/firebase_adapter.dart';

Future<SyncEngine> initializeReplicore() async {
  // Initialize local store
  final db = await openAppDatabase();
  final localStore = SqfliteStore(db);
  
  // Setup Firestore adapter
  final firestore = FirebaseFirestore.instance;
  
  // Enable offline persistence (recommended)
  await firestore.disableNetwork();
  await firestore.enableNetwork();
  
  final remoteAdapter = FirebaseAdapter(
    firestore: firestore,
    userId: FirebaseAuth.instance.currentUser!.uid,
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

## 📊 Firestore Structure

### Create Collections

```dart
// Create todos collection with documents
final todosCollectionRef = FirebaseFirestore.instance.collection('todos');

// Each document structure:
{
  'uuid': 'auto-generated-by-firestore',
  'title': 'Buy Milk',
  'completed': false,
  'updated_at': Timestamp.now(),
  'deleted_at': null,
  'user_id': 'current_user_uid'
}
```

### Security Rules

```firestore
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /todos/{document=**} {
      allow read, write: if request.auth != null && 
        request.auth.uid == resource.data.user_id;
    }
  }
}
```

---

## ✍️ Reading & Writing

### Read Records

```dart
final todosSnapshot = await FirebaseFirestore.instance
  .collection('todos')
  .where('user_id', isEqualTo: userId)
  .where('deleted_at', isNull: true)
  .orderBy('updated_at', descending: true)
  .get();

final todos = todosSnapshot.docs
  .map((doc) => Todo.fromMap(doc.data()))
  .toList();
```

### Write Record

```dart
await FirebaseFirestore.instance
  .collection('todos')
  .doc('uuid-123')
  .set({
    'uuid': 'uuid-123',
    'title': 'My Todo',
    'updated_at': FieldValue.serverTimestamp(),
    'user_id': userId,
  });
```

### Batch Operations

```dart
// Firestore batch (max 500 operations)
final batch = FirebaseFirestore.instance.batch();

batch.set(
  FirebaseFirestore.instance.collection('todos').doc('1'),
  todoData1,
);
batch.set(
  FirebaseFirestore.instance.collection('todos').doc('2'),
  todoData2,
);

await batch.commit(); // Atomic
```

---

## 🔄 Real-Time Subscriptions

### Listen to Changes

```dart
FirebaseFirestore.instance
  .collection('todos')
  .where('user_id', isEqualTo: userId)
  .snapshots()
  .listen((snapshot) {
    for (final change in snapshot.docChanges) {
      switch (change.type) {
        case DocumentChangeType.added:
          print('Added: ${change.doc.data()}');
          break;
        case DocumentChangeType.modified:
          print('Modified: ${change.doc.data()}');
          break;
        case DocumentChangeType.removed:
          print('Removed: ${change.doc.data()}');
          break;
      }
    }
  });
```

### Setup Real-Time with Replicore

```dart
// Firestore adapter automatically handles real-time
final provider = remoteAdapter.getRealtimeProvider();

if (provider != null) {
  await provider.subscribe(
    table: 'todos',
    onUpdate: (record) {
      // Auto-sync on change
      engine.sync();
    },
  );
}
```

---

## ⚡ Performance Tips

### 1. Use Indexes for Queries

```firestore
// Firestore creates composite index automatically for:
db.collection('todos')
  .where('user_id', '==', userId)
  .where('completed', '==', true)
  .orderBy('updated_at', descending: true)
```

### 2. Paginate with Cursors

```dart
Query firstPage = FirebaseFirestore.instance
  .collection('todos')
  .orderBy('updated_at', descending: true)
  .limit(20);

final firstSnapshot = await firstPage.get();
final lastDocument = firstSnapshot.docs.last;

// Next page
Query nextPage = FirebaseFirestore.instance
  .collection('todos')
  .orderBy('updated_at', descending: true)
  .startAfterDocument(lastDocument)
  .limit(20);
```

### 3. Field Deletion

```dart
// Remove field instead of null
await doc.update({
  'field_name': FieldValue.delete(),
});
```

---

## 🐛 Common Issues

### Issue: Permission Denied

```
Error: Permission denied
```

**Solution**: Check security rules and user authentication

```dart
final user = FirebaseAuth.instance.currentUser;
if (user == null) {
  // User not authenticated
  await FirebaseAuth.instance.signInAnonymously();
}
```

### Issue: Document Not Found

**Solution**: Document exists check

```dart
final doc = await FirebaseFirestore.instance
  .collection('todos')
  .doc('uuid-123')
  .get();

if (doc.exists) {
  print(doc.data());
} else {
  print('Document not found');
}
```

---

## 🔒 Security Best Practices

### Validate User Access

```firestore
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /todos/{document=**} {
      // User can only access their own
      allow read, write: if 
        request.auth.uid == resource.data.user_id;
      
      // Validate data on write
      allow create: if
        request.data.user_id == request.auth.uid &&
        request.data.title is string &&
        request.data.title.size() > 0;
    }
  }
}
```

---

## 📈 Scaling to Millions

### Collection Sharding

For high write volume, shard data:

```dart
// Instead of single /stats document
// Shard across random buckets
final bucket = Random().nextInt(10);
await db.collection('stats_$bucket').doc('summary').update({
  'count': FieldValue.increment(1),
});
```

### Offline Persistence

```dart
await FirebaseFirestore.instance.settings = const Settings(
  persistenceEnabled: true,
  cacheSizeBytes: 100 * 1024 * 1024, // 100 MB
);
```

---

## 🧪 Testing

### Emulator Setup

```bash
firebase emulators:start
```

### Test with Emulator

```dart
void setupEmulator() {
  if (kDebugMode) {
    FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
    FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
  }
}
```

---

## 🚀 Production Checklist

- [ ] Security rules reviewed
- [ ] User authentication required
- [ ] Batch operations chunked ≤500
- [ ] Pagination implemented
- [ ] Offline persistence enabled
- [ ] Real-time subscriptions managed
- [ ] Error handling in place
- [ ] Emulator tests passing

---

**Firebase Firestore is powerful for real-time, collaborative apps!** 🔥
