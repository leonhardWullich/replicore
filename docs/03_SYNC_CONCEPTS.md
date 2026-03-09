# Synchronization Concepts Deep Dive

> **Master the fundamental concepts that power Replicore's bidirectional sync**

---

## 🎯 Core Sync Problem

Before Replicore, developers had to manually solve:

1. ❌ **"My app crashes, data is lost"**
   → Solution: `LocalStore` persists offline changes

2. ❌ **"I went offline and online, data conflicts"**
   → Solution: `Conflict Resolution Strategies`

3. ❌ **"Sync takes forever with 1000 records"**
   → Solution: `Batch Operations` (v0.5.1+)

4. ❌ **"Sync failed, I don't know which records synced"**
   → Solution: `Operation IDs` for safe retries

5. ❌ **"Same change synced twice"**
   → Solution: `Idempotency` via operation IDs

---

## 📥 Pull Operation (Download)

### What is Pull?

**Pull** = Download all changes from server since last sync.

```
Server State:        Local State:
┌──────────────┐    ┌──────────────┐
│ UUID=1 v.2   │    │ UUID=1 v.1   │
│ UUID=2 v.1   │ ──►│ UUID=2 (new) │
│ UUID=3 (new) │    │ UUID=3 (new) │
└──────────────┘    └──────────────┘
(newer)             (older)
```

### Pull Algorithm

**Step 1: Establish Cursor**

```dart
// First pull ever
cursor = null   // No previous state

// Subsequent pulls
cursor = SyncCursor(
  updatedAt: DateTime.parse('2024-01-15T10:30:00Z'),
  primaryKey: 'uuid-999',  // Last UUID seen at that time
)
```

**Step 2: Request Changes**

```dart
await remoteAdapter.pull(
  PullRequest(
    table: 'todos',
    cursor: cursor,        // null = first time
    limit: 100,            // Batch size
  ),
)
```

**Step 3: Server Response**

Server returns records **after** the cursor:

```
Scenario: Server has 5 records, cursor points to last 2

Before Cursor:
  │ 2024-01-15 10:00 UUID=1 │ SKIP (already synced)
  │ 2024-01-15 10:15 UUID=2 │ SKIP (already synced)
  │ 2024-01-15 10:20 UUID=3 │
  │ 2024-01-15 10:25 UUID=4 │
  │ 2024-01-15 10:30 UUID=5 │ ◄── Cursor here
  
  ↓ Return only these:
  
  │ 2024-01-15 10:35 UUID=6 │ ◄── RETURN
  │ 2024-01-15 10:40 UUID=7 │ ◄── RETURN
  │ 2024-01-15 10:45 UUID=8 │ ◄── RETURN
```

**Step 4: Keyset Pagination** (Anti-Pattern)

❌ **WRONG**: `OFFSET 100,000 LIMIT 100`
- Scans first 100,000 rows (slow!)
- Inconsistent if rows inserted (skips some)

✅ **RIGHT**: Keyset pagination

```sql
SELECT * FROM todos
WHERE (updated_at, uuid) > ('2024-01-15T10:30:00Z', 'uuid-999')
ORDER BY updated_at, uuid
LIMIT 100
```

Benefits:
- Fast (index scan)
- Consistent (no inserts cause skips)
- Real-time friendly

**Step 5: Process Records**

For each pulled record:

```dart
1. Check if exists locally
   └─ Query local store: SELECT * WHERE uuid = ?
   
2. Is local record dirty?
   └─ Check: is_synced = 0 AND deleted_at IS NULL
   
3. If conflict: Resolve
   └─ Apply strategy (ServerWins, LocalWins, etc.)
   
4. Store result
   └─ INSERT or UPDATE in local store
```

**Step 6: Pagination**

If `response.nextCursor` exists:

```dart
// Pull returns 100 records
if (response.nextCursor != null) {
  // More data exists on server
  // Immediately request next batch
  await pull(PullRequest(cursor: response.nextCursor))
}
```

Final state after all pages:

```
Local Store (after pull):
┌─────────────────────────────┐
│ UUID=1,v.2 (from server)    │
│ UUID=2,v.1 (unchanged)      │
│ UUID=3,v.1 (from server)    │
│ UUID=4,v.1 (from server)    │
│ UUID=5,v.1 (from server)    │
│ (all is_synced=1)           │
└─────────────────────────────┘
```

---

## 📤 Push Operation (Upload)

### What is Push?

**Push** = Upload all local changes to server.

```
Local State (dirty):      Server State:
┌──────────────────┐    ┌──────────────┐
│ UUID=1,v.2,dirty │    │ UUID=1,v.1   │
│ UUID=2,v.1,dirty │ ──►│ UUID=2,v.1   │
│ UUID=3,delete    │    │ (UUID=3)     │
└──────────────────┘    └──────────────┘
(newer, unsync'd)       (older)
```

### Push Algorithm (v0.5.1 with Batch)

**Step 1: Get Dirty Records**

```dart
final dirty = await localStore.getDirtyRecords('todos');

Raw result:
[
  { uuid: 1, title: 'New Title', is_synced: 0, deleted_at: null },
  { uuid: 2, title: 'Another', is_synced: 0, deleted_at: null },
  { uuid: 3, title: 'Old', is_synced: 0, deleted_at: '2024-01...' },
]
```

**Step 2: Generate Operation IDs** (For Idempotency)

```dart
// Operation ID = SHA256(table:pk:data)
// Same operation ID on retry = server deduplicates

final opId1 = sha256('todos:1:{"title":"New Title"...}')
             = 'op-abc-123'

final dirty_ withOpIds = [
  { uuid: 1, title: 'New Title', _operation_id: 'op-abc-123' },
  { uuid: 2, title: 'Another', _operation_id: 'op-def-456' },
  { uuid: 3, title: 'Old', _operation_id: 'op-ghi-789' },
]
```

**Step 3: Set Operation IDs Locally** (NEW v0.5.1!)

```dart
// Batch update: 1 SQL operation, not 3
await localStore.setOperationIds(
  'todos',
  'uuid',
  {
    1: 'op-abc-123',
    2: 'op-def-456',
    3: 'op-ghi-789',
  },
);

Result: is_synced stays 0 (still dirty), but _operation_id set
This ensures safe retry if network fails
```

**Step 4: Group by Operation Type** (NEW v0.5.1!)

```dart
// Separate upserts from deletes
final upserts = dirty.where((r) => r['deleted_at'] == null);
final deletes = dirty.where((r) => r['deleted_at'] != null);
```

**Step 5: Batch Upsert** (NEW v0.5.1!)

```dart
// Before (v0.5.0): Loop, make 50 individual calls
for (final record in upserts) {
  await remoteAdapter.upsert(table: 'todos', data: record);
}

// After (v0.5.1): Single batch call
final successfulIds = await remoteAdapter.batchUpsert(
  table: 'todos',
  records: upserts,
  primaryKeyColumn: 'uuid',
  idempotencyKeys: operationIds,  // Safe for retries!
);

// Benefits:
// ✅ 50 records = 1 network request (not 50)
// ✅ Single SQL UPSERT on server (atomic)
// ✅ 50x faster!
```

**Step 6: Batch Delete** (NEW v0.5.1!)

```dart
// Similarly batch delete
final successfulIds = await remoteAdapter.batchSoftDelete(
  table: 'todos',
  records: deletes,
  primaryKeyColumn: 'uuid',
  deletedAtColumn: 'deleted_at',
  updatedAtColumn: 'updated_at',
  idempotencyKeys: operationIds,
);

// Same batch benefits as upsert
```

**Step 7: Mark as Synced** (NEW v0.5.1!)

```dart
// Mark successfully synced records as clean
await localStore.markManyAsSynced(
  'todos',
  'uuid',
  successfulIds,  // Only successful ones
);

// Result: is_synced = 1 for successful records
// Failed records stay is_synced = 0 for retry
```

**Step 8: Error Handling**

```
Scenario: 50 records, 45 succeed, 5 fail

Result:
  ✅ 45 marked as synced (is_synced = 1)
  ❌ 5 stay dirty (is_synced = 0)
  
Next sync:
  → Retry only the 5 failed
  → Other 45 ignored
```

---

## ⚔️ Conflict Resolution

### What is a Conflict?

```
Scenario: User works offline

Time                Remote              Local
─────────────────────────────────────────────────
NOW-30min           Record v.1          (offline)
                                        │
                                        ├─ User edits
NOW-20min                              │
                                        Record v.2,dirty
NOW-10min           Record v.3          │
                    (server updated)    │
NOW                 (sync begins)       │
                    Pull: Record v.3    │
                                        Conflict!
                                        Which one to keep?
```

### Resolution Strategies

#### 1. ServerWins (Default)

**Rule**: Remote version always wins

```dart
if (localRecord != null && localRecord.isDirty) {
  // Discard local changes, use remote
  useRemoteVersion()
}
```

**Code**:
```dart
TableConfig(
  strategy: SyncStrategy.serverWins,
)

// When pull receives newer server record:
// Overwrites local dirty version
```

**When to use**:
- Server is single source of truth
- Local changes are "drafts"
- OK to lose local edits if conflict

**Example App**:
```
Shared Todo App:
- Server has latest state (shared with others)
- Local changes are "my draft"
- On conflict: use server version
```

#### 2. LocalWins

**Rule**: Local version always wins

```dart
if (localRecord != null && localRecord.isDirty) {
  // Keep local changes, ignore remote
  keepLocalVersion()
  retryPush()  // Push again
}
```

**When to use**:
- Local is source of truth
- User's edits are sacred
- Minimize data loss

**Example App**:
```
Offline Document Editor:
- User is working intensely offline
- If sync conflicts: keep user's changes
- Retry push to server
```

#### 3. LastWriteWins

**Rule**: Newest by timestamp wins

```dart
final local = localRecord.updatedAt
final remote = pulledRecord.updatedAt

if (local > remote) {
  keepLocalVersion()
} else {
  useRemoteVersion()
}
```

**When to use**:
- Single user, "last action wins"
- Simple apps with rare conflicts
- ⚠️ NOT safe for multi-user apps

**Example**:
```
Single-user Todo App:
- User edits locally at 10:00
- User edits on web at 10:30
- On conflict: use 10:30 version
```

#### 4. CustomResolver (Everything Else)

**Rule**: Your custom logic decides**

```dart
Future<Map<String, dynamic>> customResolver({
  required Map<String, dynamic> localRecord,
  required Map<String, dynamic> remoteRecord,
  required String table,
}) async {
  // Your logic
  return mergedRecord;
}
```

**Examples**:

**Example 1: Smart Merge**
```dart
// Merge at field level
final merged = {
  'uuid': localRecord['uuid'],
  'title': localRecord['title'],           // Use local
  'completed': remoteRecord['completed'],  // Use remote
  'updated_at': DateTime.now(),
};
return merged;
```

**Example 2: AI-Based**
```dart
// Use ML to choose best version
final similarity = calculateSimilarity(
  localRecord['description'],
  remoteRecord['description'],
);

if (similarity > 0.8) {
  return localRecord;  // Same change on both sides
} else {
  return mergeChanges(localRecord, remoteRecord);
}
```

**Example 3: User Prompt**
```dart
// Ask user to choose
final chosen = await showDialog(
  context: context,
  builder: (context) => ConflictDialog(
    local: localRecord,
    remote: remoteRecord,
  ),
);
return chosen;
```

### Conflict Detection

When does Replicore detect a conflict?

```
Conditions:
1. Local record has changed locally (is_synced = 0)
2. Pull receives newer version from server

If both true:
  └─ Call resolution strategy
  
Otherwise:
  └─ No conflict (one version is current)
```

**Examples**:

```
Case 1: No conflict (server changed, local didn't)
  Local:  UUID=1,v.1,synced
  Server: UUID=1,v.3
  → Accept server version (not dirty)

Case 2: No conflict (local changed, server didn't)
  Local:  UUID=1,v.2,dirty
  Server: UUID=1,v.1
  → Keep local version (will push)

Case 3: Conflict (both changed)
  Local:  UUID=1,v.2,dirty
  Server: UUID=1,v.3
  → Resolve using strategy!

Case 4: Soft delete conflict
  Local:  UUID=1,deleted_at=now,dirty
  Server: UUID=1,deleted_at=null
  → Resolve (what takes precedence?)
```

---

## 🗑️ Soft Deletes

### Why Soft Deletes?

❌ **Hard Delete**: `DELETE FROM todos WHERE uuid = ?`
- Data lost forever
- No audit trail
- Can't undo

✅ **Soft Delete**: Set `deleted_at` timestamp

```sql
UPDATE todos SET deleted_at = NOW() WHERE uuid = ?
```

Benefits:
- ✅ Data preserved
- ✅ Audit trail
- ✅ Can restore
- ✅ Consistent across devices

### How Soft Deletes Work

**User deletes locally**:
```dart
await repository.deleteTodo(uuid);

// Internally:
await localStore.writeLocal(
  'todos',
  {
    'uuid': uuid,
    'deleted_at': DateTime.now().toIso8601String(),
  },
);
```

**This sets `deleted_at`, marks as dirty**

**Push syncs**:
```dart
// Server receives:
{
  'uuid': '123',
  'deleted_at': '2024-01-15T10:30:00Z',
  '_operation_id': 'op-xyz',
}

// Server updates:
UPDATE todos SET deleted_at = '2024-01-15T...'
WHERE id = '123'
```

**UI filters deleted records**:
```dart
final todos = await repository.getTodos();

// Filtering typically in query:
SELECT * FROM todos WHERE deleted_at IS NULL

// Or in app:
todos.where((t) => t.deleted_at == null)
```

### Multi-Device Soft Delete

```
Timeline:

Time    Phone                   Tablet
───────────────────────────────────────────
NOW     User deletes todo      (synced, not dirty)
        deleted_at = NOW
        is_synced = 0
        
NOW+5s  Push syncs             (still synced)
        deleted_at synced
        
NOW+10s Pull syncs             Record deleted_at
                               received from server
                               UI updates
                               Todo disappears
```

---

## 🔑 Operation IDs & Idempotency

### The Problem

```
Network fails during push:

Request 1:
  POST /api/todos [data: {uuid: 1, title: '...'}]
  ├─ Server receives ✓
  ├─ Inserts record ✓
  ├─ Sends response
  └─ Network fails ✗ (response lost)

Client-side:
  "Sync failed, no response"
  └─ Retry immediately

Request 2:
  POST /api/todos [data: {uuid: 1, title: '...'}]
  ├─ Server receives ✓
  ├─ Inserts record AGAIN ✗ (duplicate!)
  └─ Now have 2 identical records!
```

### The Solution: Operation IDs

Generate deterministic ID from data:

```dart
final opId = sha256.convert(utf8.encode(
  'upsert:todos:1:{"title":"My Todo"...}'
)).toString();

// First request:
POST /api/todos/upsert
{
  "data": {"uuid": 1, "title": "..."},
  "operation_id": "op-abc-123"  ◄── Include this
}

// Server stores mapping:
operations[op-abc-123] = {id: 1, status: success}

// Retry request (same operation_id):
POST /api/todos/upsert
{
  "data": {"uuid": 1, "title": "..."},
  "operation_id": "op-abc-123"  ◄── Same ID
}

// Server recognizes:
"I've seen op-abc-123 before!"
└─ Returns success without duplicate insert
```

**Key Property**: Same data = same operation ID

```dart
// These all generate same opId:
operationId({uuid: 1, title: 'A'})
  == operationId({uuid: 1, title: 'A'})

// Different data = different opId:
operationId({uuid: 1, title: 'A'})
  != operationId({uuid: 1, title: 'B'})
```

---

## 📊 Sync Metadata Columns

Every table requires these columns:

### 1. Primary Key
```
Column: uuid (or id)
Type: TEXT (UUID format)
Purpose: Uniquely identify record
Synced: Yes (required)
```

### 2. Updated At
```
Column: updated_at
Type: TIMESTAMP
Purpose: Tracks when record was last modified
Used for: Keyset pagination cursor
Synced: Yes (required)
Auto-set: By backend (NOW() default)
```

### 3. Deleted At
```
Column: deleted_at
Type: TIMESTAMP (nullable)
Purpose: Soft delete marker
Value: null = not deleted
Value: timestamp = deleted at that time
Synced: Yes (required)
```

### 4. Is Synced (Local Only!)
```
Column: is_synced
Type: INTEGER (0 or 1)
Purpose: Track if changes pushed
Value: 0 = dirty (local changes not synced)
Value: 1 = clean (synced to server)
Synced: NO (local only!)
Storage: Local only
```

### 5. Operation ID (Local Only!)
```
Column: _operation_id
Type: TEXT (nullable)
Purpose: Idempotency key for safe retries
Value: null = not yet synced
Value: UUID = operation identifier
Synced: NO (local only!)
Storage: Local only, can be deleted after sync
```

---

## 📈 Practical Examples

### Example 1: User Edits Todo

```
Initial State:
  Local:  {uuid: 1, title: 'Buy milk', is_synced: 1}
  Server: {uuid: 1, title: 'Buy milk'}

User edits locally (offline):
  Input: title = 'Buy milk and bread'
  
Result:
  Local:  {uuid: 1, title: 'Buy milk and bread', is_synced: 0}
  Server: {uuid: 1, title: 'Buy milk'} (unchanged)

App goes online, sync triggered:
  
Push phase:
  1. Detect dirty: is_synced = 0 ✓
  2. Generate opId: 'op-xyz'
  3. Batch upsert: [record with opId]
  4. Server updates
  5. Mark synced: is_synced = 1
  
Result:
  Local:  {uuid: 1, title: 'Buy milk and bread', is_synced: 1}
  Server: {uuid: 1, title: 'Buy milk and bread'}
```

### Example 2: Conflict Resolution

```
User on Phone (offline):
  Initial: {uuid: 1, title: 'Buy MILK', is_synced: 1}
  User edits: {uuid: 1, title: 'Buy BREAD', is_synced: 0}

Same time, User on Tablet (online):
  POST /api/todos/upsert
  {uuid: 1, title: 'Buy EGGS'}
  Server updates: {uuid: 1, title: 'Buy EGGS', updated_at: 12:00}

Phone gets network, begins sync:

Pull phase:
  Server response: {uuid: 1, title: 'Buy EGGS', updated_at: 12:00}
  Local:          {uuid: 1, title: 'Buy BREAD', is_synced: 0}
  
  Conflict detected! (server changed AND local dirty)
  
  Apply strategy (assuming ServerWins):
    Keep: {uuid: 1, title: 'Buy EGGS', is_synced: 1}
    Result: Local overwritten with server version
    User's "Buy BREAD" edit lost!

If strategy was CustomResolver with field merge:
    merged: {uuid: 1, title: 'Buy EGGS and BREAD'}
    Keep merged version
```

---

## 💡 Best Practices

1. **Always use ServerWins** unless you have specific reason
2. **Never rely on hard deletes** for sync apps
3. **Understand operation IDs** - they're your safety net
4. **Monitor conflict rate** - high rate indicates design issue
5. **Test offline scenarios** - conflicts often appear in offline testing
6. **Batch operations** (v0.5.1+) - always use, 50x faster

---

Next: [Conflict Resolution Deep Dive](./04_CONFLICT_RESOLUTION.md)

**Master these concepts and sync problems disappear!** 🚀
