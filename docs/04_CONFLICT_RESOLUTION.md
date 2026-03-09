# Conflict Resolution Deep Dive

> **Master all conflict resolution strategies and implement advanced merging logic**

---

## 🎯 Overview

Conflicts occur when the same record is modified both locally and on the server between syncs.

### Conflict Scenarios
```
Scenario                      Result
────────────────────────────────────────────
Server unchanged              No conflict (accept local)
Local unchanged               No conflict (accept server)
Both changed same field       CONFLICT (resolve!)
Both changed different fields Mergeable (custom logic)
Both deleted                  No conflict (delete)
Server deleted, local changed CONFLICT (which wins?)
```

---

## 📋 Built-in Strategies

### 1. ServerWins (Default) ⭐

**Rule**: Server version always wins

```dart
TableConfig(
  strategy: SyncStrategy.serverWins,
)
```

**When conflict detected**:
```dart
if (localIsDirty && serverChanged) {
  useServerVersion()  // Discard local
}
```

**Pros**:
- ✅ Simple to understand
- ✅ No data loss at server
- ✅ Works for shared data

**Cons**:
- ❌ Local changes lost
- ❌ User frustration if offline edits discarded

**Best for**:
- Shared documents
- Server is single source of truth
- Rare offline editing

**Example**:
```dart
// Shared Todo (Cloud version is authoritative)
localRecord:  {title: 'Buy MILK', updated_at: 10:00}
serverRecord: {title: 'Buy EGGS', updated_at: 10:30}

Result: Use "Buy EGGS"
```

---

### 2. LocalWins

**Rule**: Local version always wins

```dart
TableConfig(
  strategy: SyncStrategy.localWins,
)
```

**When conflict detected**:
```dart
if (localIsDirty && serverChanged) {
  keepLocalVersion()
  retryPush()  // Try again
}
```

**Pros**:
- ✅ User's edits preserved
- ✅ Minimal data loss
- ✅ Best for personal data

**Cons**:
- ❌ Server version lost
- ❌ Can create divergence
- ❌ Requires retry logic

**Best for**:
- Personal notes
- Offline-first apps
- User's edits are sacred

**Example**:
```dart
// Personal Document (User version is authoritative)
localRecord:  {content: 'NEW CONTENT', updated_at: 10:00}
serverRecord: {content: 'OLD CONTENT', updated_at: 10:30}

Result: Keep "NEW CONTENT", retry push
```

---

### 3. LastWriteWins

**Rule**: Newest by timestamp wins

```dart
TableConfig(
  strategy: SyncStrategy.lastWriteWins,
)
```

**Implementation**:
```dart
final localTime = DateTime.parse(local['updated_at']);
final serverTime = DateTime.parse(server['updated_at']);

if (localTime > serverTime) {
  keepLocal()
} else {
  useServer()
}
```

**Pros**:
- ✅ Deterministic
- ✅ No custom logic needed
- ✅ Fair for single user

**Cons**:
- ❌ Not safe for concurrent users
- ❌ Ignores importance of changes
- ❌ Can flip-flop

**Best for**:
- Single user apps
- Simple time-based preference
- Low conflict rate

**Example**:
```dart
// Note App
localRecord:  {content: 'LATEST', updated_at: 14:30}
serverRecord: {content: 'OLDER', updated_at: 14:20}

Result: Use local (newer timestamp)
```

---

## 🎨 Custom Resolver (Advanced)

**Rule**: Your logic decides

```dart
Future<Map<String, dynamic>> customResolver({
  required Map<String, dynamic> local,
  required Map<String, dynamic> remote,
  required String table,
}) async {
  // Your custom logic
  return mergedRecord;
}

TableConfig(
  strategy: SyncStrategy.custom,
  customResolver: customResolver,
)
```

---

## 💡 Advanced Patterns

### Pattern 1: Smart Field Merge

Merge at field level based on importance:

```dart
Future<Map<String, dynamic>> smartMerge({
  required Map<String, dynamic> local,
  required Map<String, dynamic> remote,
}) async {
  return {
    'id': local['id'],
    
    // Title: Use newer version
    'title': _newerField(
      local['title'],
      remote['title'],
      DateTime.parse(local['updated_at']),
      DateTime.parse(remote['updated_at']),
    ),
    
    // Status: Use local (user focused)
    'status': local['status'],
    
    // Tags: Merge both lists (union)
    'tags': _mergeLists(
      (local['tags'] as List?) ?? [],
      (remote['tags'] as List?) ?? [],
    ),
    
    // Updated: Set to now
    'updated_at': DateTime.now().toIso8601String(),
  };
}

String _newerField(
  String local,
  String remote,
  DateTime localTime,
  DateTime remoteTime,
) {
  return localTime.isAfter(remoteTime) ? local : remote;
}

List<String> _mergeLists(List<String> local, List<String> remote) {
  return {...local, ...remote}.toList();
}
```

### Pattern 2: Content-Based Merge

Detect actual changes vs just timestamps:

```dart
Future<Map<String, dynamic>> contentMerge({
  required Map<String, dynamic> local,
  required Map<String, dynamic> remote,
  required Map<String, dynamic> ancestor, // Previous version
}) async {
  // Compare what actually changed
  
  final localChanges = _getChanges(ancestor, local);
  final remoteChanges = _getChanges(ancestor, remote);
  
  // If both changed same field: conflict
  final conflicts = localChanges.keys
    .where((k) => remoteChanges.containsKey(k))
    .toList();
  
  if (conflicts.isEmpty) {
    // No overlap: safe merge
    return {...remote, ...local};
  }
  
  // Has conflicts: apply custom logic per field
  return _mergeWithConflicts(
    ancestor,
    local,
    remote,
    conflicts,
  );
}
```

### Pattern 3: User Prompt

Ask user to choose:

```dart
Future<Map<String, dynamic>> userChoose({
  required Map<String, dynamic> local,
  required Map<String, dynamic> remote,
  required BuildContext context,
}) async {
  final chosen = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Conflict Detected'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Keep local or use remote?'),
          const SizedBox(height: 16),
          _buildRecordPreview('Local', local),
          const Divider(),
          _buildRecordPreview('Remote', remote),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Keep Local'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Use Remote'),
        ),
      ],
    ),
  );
  
  return chosen ?? true ? local : remote;
}

Widget _buildRecordPreview(String label, Map<String, dynamic> record) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      Text('updated_at: ${record['updated_at']}'),
      Text('content: ${record['content']}'),
    ],
  );
}
```

### Pattern 4: ML-Based Similarity

Use machine learning to detect if changes are "the same":

```dart
Future<Map<String, dynamic>> mlMerge({
  required Map<String, dynamic> local,
  required Map<String, dynamic> remote,
}) async {
  final similarity = _calculateSimilarity(
    local['content'] ?? '',
    remote['content'] ?? '',
  );
  
  // If very similar: probably same edit on both sides
  if (similarity > 0.85) {
    return local; // Keep local (minor differences)
  }
  
  // If different: need smart merge
  if (similarity < 0.3) {
    return _threeWayMerge(local, remote);
  }
  
  // In-between: partial merge
  return _partialMerge(local, remote);
}

double _calculateSimilarity(String a, String b) {
  // Levenshtein distance algorithm
  // Returns 0.0 to 1.0
  // 1.0 = identical
  // 0.0 = completely different
  // ...implementation...
  return 0.5;
}
```

---

## ⚠️ Complex Scenarios

### Scenario: Concurrent Edits (Different Fields)

```
Base:    {title: 'TODO', done: false}

Local:   {title: 'TODO', done: true}   (checked it)
Server:  {title: 'NEW TITLE', done: false} (renamed it)

Safe merge (ServerWins for title, Local for done):
Result:  {title: 'NEW TITLE', done: true}
```

**Implementation**:
```dart
Future<Map> resolveFieldLevel({
  required Map local,
  required Map remote,
  required Map base,
}) async {
  final result = {...remote}; // Start with remote
  
  // Check what local changed
  for (final key in local.keys) {
    if (base[key] != local[key]) {
      // Local changed this field
      final remoteChanged = base[key] != remote[key];
      
      if (!remoteChanged) {
        // Remote didn't change it: safe to use local
        result[key] = local[key];
      }
      // If remote also changed: conflict (use strategy)
    }
  }
  
  return result;
}
```

### Scenario: Delete Conflict

```
User 1 (Phone): Deletes record (deleted_at = now)
User 2 (Web):   Edits record (content changed)

Sync:
  Phone pulls: {deleted_at: '...', content: 'old'}
  Phone wants: Soft delete
  Web version: Has new content
  
Conflict: Delete or keep with new content?
```

**Resolution**:
```dart
Future<Map> deleteConflict({
  required Map local,
  required Map remote,
}) async {
  final localDeleted = local['deleted_at'] != null;
  final remoteDeleted = remote['deleted_at'] != null;
  
  if (localDeleted && !remoteDeleted) {
    // Local deleted, remote exists
    return remote; // Keep remote with new edits
  }
  
  if (!localDeleted && remoteDeleted) {
    // Remote deleted, local edited
    return local; // Keep locally edited version
  }
  
  // Neither deleted, regular conflict
  return local; // Apply regular strategy
}
```

---

## 📊 Real-World Examples

### Example 1: Note-Taking App

```dart
Future<Map<String, dynamic>> noteResolver({
  required Map<String, dynamic> local,
  required Map<String, dynamic> remote,
}) async {
  // For note app: merge content if both changed
  
  final localContent = local['content'] ?? '';
  final remoteContent = remote['content'] ?? '';
  final baseContent = ''; // Assume empty if not provided
  
  final localChanged = baseContent != localContent;
  final remoteChanged = baseContent != remoteContent;
  
  if (!localChanged) return remote;
  if (!remoteChanged) return local;
  
  // Both changed: merge with divider
  return {
    ...local,
    'content': '''
$remoteContent

--- Your local changes ---

$localContent
''',
    'conflict': true, // Flag for UI
    'updated_at': DateTime.now().toIso8601String(),
  };
}
```

### Example 2: Todo App

```dart
Future<Map<String, dynamic>> todoResolver({
  required Map<String, dynamic> local,
  required Map<String, dynamic> remote,
}) async {
  // For todo: check status independently
  
  return {
    'id': local['id'],
    'title': _newerVersion(local, remote, 'title'),
    'description': _newerVersion(local, remote, 'description'),
    'completed': local['completed'], // User's local state
    'tags': _mergeTags(local, remote),
    'updated_at': DateTime.now().toIso8601String(),
  };
}

String _newerVersion(
  Map a,
  Map b,
  String field,
) {
  final aTime = DateTime.parse(a['updated_at'] ?? '');
  final bTime = DateTime.parse(b['updated_at'] ?? '');
  return aTime.isAfter(bTime) ? a[field] : b[field];
}

List<String> _mergeTags(Map local, Map remote) {
  final localTags = (local['tags'] as List?)?.cast<String>() ?? [];
  final remoteTags = (remote['tags'] as List?)?.cast<String>() ?? [];
  return {...localTags, ...remoteTags}.toList();
}
```

---

## 🔍 Monitoring Conflicts

### Track Conflict Rate

```dart
engine.onConflict.listen((conflict) {
  metrics.recordConflict(
    table: conflict.table,
    recordId: conflict.primaryKey,
    strategy: conflict.strategy,
  );
  
  logger.info(
    'Conflict resolved',
    context: {
      'table': conflict.table,
      'strategy': conflict.strategy,
      'winner': conflict.resolvedVersion,
    },
  );
});
```

### Alert on High Conflict Rate

```dart
void _monitorConflicts() {
  int conflictCount = 0;
  
  engine.onConflict.listen((_) {
    conflictCount++;
    
    if (conflictCount > 10) {
      logger.warning(
        'High conflict rate detected',
        context: {'conflicts': conflictCount},
      );
      // Maybe alert user or change strategy
    }
  });
}
```

---

## ⚙️ Implementation Guide

### Step 1: Choose Strategy

```dart
// Simple app: Use ServerWins (default)
TableConfig(
  name: 'todos',
  strategy: SyncStrategy.serverWins,
)

// Personal data: Use LocalWins
TableConfig(
  name: 'notes',
  strategy: SyncStrategy.localWins,
)

// Complex app: Use custom
TableConfig(
  name: 'documents',
  strategy: SyncStrategy.custom,
  customResolver: myCustomResolver,
)
```

### Step 2: Test Conflict Scenarios

```dart
test('conflict resolution', () async {
  final engine = SyncEngine(...);
  
  // Create conflict
  await engine.writeLocal('todos', {
    'id': 1,
    'title': 'Local version',
    'updated_at': DateTime.now().toIso8601String(),
    '_is_synced': false,
  });
  
  // Simulate server version
  final adapter = MockAdapter();
  adapter.serverData = [{
    'id': 1,
    'title': 'Server version',
    'updated_at': DateTime.now().toIso8601String(),
  }];
  
  // Trigger sync
  await engine.sync();
  
  // Verify resolution
  final result = await engine.getSingleRecord('todos', 1);
  expect(result['title'], 'Server version'); // ServerWins
});
```

---

## 💡 Best Practices

1. **Start with ServerWins** - Simple, predictable
2. **Use LocalWins carefully** - Requires retry logic
3. **Custom resolver** - Only if necessary
4. **Monitor conflict rate** - High rate = design issue
5. **Test offline scenarios** - Conflicts appear in offline testing
6. **Document your strategy** - Team should understand
7. **Consider field-level strategies** - Not all-or-nothing

---

**Master conflict resolution and sync reliably!** 🎯
