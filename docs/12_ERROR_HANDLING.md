# Error Handling & Recovery

> **Comprehensive exception handling and recovery strategies**

---

## 🎯 Exception Hierarchy

```
ReplicoreException
├── SyncException
│   ├── PullException
│   ├── PushException
│   └── ConflictException
├── StorageException
│   ├── RecordNotFoundException
│   └── DatabaseException
├── NetworkException
│   ├── TimeoutException
│   └── ConnectionException
└── ConfigurationException
    ├── TableNotRegisteredException
    └── InvalidConfigException
```

---

## 🛡️ Error Handling Patterns

### Try-Catch Pattern

```dart
try {
  await engine.sync();
} on PullException catch (e) {
  logger.error('Pull failed', error: e);
  // Handle pull-specific error
} on PushException catch (e) {
  logger.error('Push failed', error: e);
  // Handle push-specific error
} on NetworkException catch (e) {
  logger.warning('Network error', error: e);
  // Retry later
} catch (e) {
  logger.error('Unknown error', error: e);
}
```

### Stream Error Handling

```dart
engine.onSyncError.listen((error) {
  switch (error.runtimeType) {
    case NetworkException:
      // Show retry UI
      break;
    case SyncException:
      // Alert user
      break;
    default:
      // Log unexpectedError
      break;
  }
});
```

---

## 📋 Specific Exceptions

### PullException

**When**: Downloading from server fails

```dart
try {
  await engine.sync();
} on PullException catch (e) {
  // Happens when:
  // - Network error
  // - Server returns error
  // - Invalid response

  if (e.statusCode == 429) {
    // Rate limited: wait longer
    await Future.delayed(Duration(minutes: 1));
    await engine.sync();
  } else if (e.isNetworkError) {
    // Connection lost: retry when online
    // Replicore auto-retries
  }
}
```

### PushException

**When**: Uploading to server fails

```dart
on PushException catch (e) {
  // Happens when:
  // - Network error
  // - Server rejects data
  // - Permissions issue

  final failedRecords = e.failedRecords;
  logger.error(
    'Push failed for ${failedRecords.length} records',
    context: {'table': e.table},
  );
  
  // Failed records stay dirty and retry next sync
}
```

### NetworkException

**When**: Network is unavailable

```dart
on NetworkException catch (e) {
  // App is offline
  logger.info('Network unavailable, using offline mode');
  
  // Local operations still work!
  // Sync retries when network returns
}
```

### ConflictException

**When**: Conflict resolution fails

```dart
on ConflictException catch (e) {
  logger.warning(
    'Conflict resolution failed',
    context: {
      'table': e.table,
      'record_id': e.primaryKey,
    },
  );
  
  // Use CustomResolver to handle
}
```

---

## 🔄 Retry Strategies

### Automatic Retry (Default)

```dart
final config = ReplicoreConfig(
  maxRetries: 3,  // Automatic retry up to 3 times
  retryDelay: Duration(seconds: 2),
);

// Retry schedule: 2s → 4s → 8s (exponential backoff)
```

### Manual Retry

```dart
Future<void> syncWithRetry() async {
  int attempts = 0;
  const maxAttempts = 3;
  
  while (attempts < maxAttempts) {
    try {
      await engine.sync();
      return;  // Success
    } catch (e) {
      attempts++;
      if (attempts < maxAttempts) {
        await Future.delayed(
          Duration(seconds: 2 * attempts),
        );
      }
    }
  }
  
  throw Exception('Sync failed after $maxAttempts attempts');
}
```

### Exponential Backoff

```dart
Future<void> syncWithBackoff() async {
  int delay = 1;  // Start with 1 second
  
  for (int i = 0; i < 5; i++) {
    try {
      await engine.sync();
      return;
    } catch (e) {
      delay *= 2;  // Double: 1s → 2s → 4s → 8s → 16s
      
      if (i < 4) {
        await Future.delayed(Duration(seconds: delay));
      } else {
        rethrow;
      }
    }
  }
}
```

---

## 🎯 Error Recovery

### Network Recovery

```dart
void _setupConnectivityMonitoring() {
  Connectivity().onConnectivityChanged.listen((result) {
    if (result == ConnectivityResult.none) {
      logger.info('Network lost');
      // Local operations continue
    } else {
      logger.info('Network restored');
      // Auto-sync triggered
      engine.sync();
    }
  });
}
```

### Partial Success Handling

```dart
engine.onSyncComplete.listen((result) {
  if (result.recordsPushed < result.totalDirty) {
    logger.warning(
      'Partial success: ${result.recordsPushed}/'
      '${result.totalDirty} pushed',
    );
    
    // Failed records will retry next sync automatically
    // No action needed
  }
});
```

### Dead Letter Queue

```dart
// Track permanently failed records
final deadLetterQueue = <String>[];

engine.onSyncError.listen((error) {
  if (error.attemptCount >= 10) {
    // Move to dead letter after 10 failures
    deadLetterQueue.addAll(error.failedRecords);
    
    logger.error(
      'Moving ${error.failedRecords.length} to DLQ',
      context: {
        'table': error.table,
        'reason': error.message,
      },
    );
  }
});
```

---

## 📊 Error Monitoring

### Track Error Rates

```dart
class ErrorMonitor {
  int totalSyncs = 0;
  int failedSyncs = 0;
  final errors = <String, int>{};
  
  void trackError(Exception e) {
    final type = e.runtimeType.toString();
    errors[type] = (errors[type] ?? 0) + 1;
  }
  
  double getErrorRate() {
    return failedSyncs / totalSyncs;
  }
  
  void printStats() {
    print('Error rate: ${getErrorRate() * 100}%');
    errors.forEach((type, count) {
      print('  $type: $count');
    });
  }
}

final monitor = ErrorMonitor();

engine.onSyncStart.listen((_) {
  monitor.totalSyncs++;
});

engine.onSyncError.listen((error) {
  monitor.failedSyncs++;
  monitor.trackError(error);
});
```

### Alert on Thresholds

```dart
engine.onSyncError.listen((error) {
  if (monitor.getErrorRate() > 0.1) {
    // >10% error rate
    sendAlert('High sync error rate detected');
  }
});
```

---

## 🛡️ Defensive Programming

### Input Validation

```dart
Future<void> createTodo(String title) async {
  if (title.trim().isEmpty) {
    throw ArgumentError('Title cannot be empty');
  }
  
  if (title.length > 1000) {
    throw ArgumentError('Title too long');
  }
  
  await engine.writeLocal('todos', {
    'uuid': generateUuid(),
    'title': title.trim(),
    'updated_at': DateTime.now().toIso8601String(),
  });
}
```

### State Validation

```dart
Future<bool> isReadyForSync() async {
  if (!_isInitialized) {
    throw StateError('SyncEngine not initialized');
  }
  
  if (!await Connectivity().checkConnectivity()
      .then((r) => r != ConnectivityResult.none)) {
    return false;  // Not ready, but will retry
  }
  
  return true;
}
```

---

## 🧪 Testing Error Scenarios

### Mock Failures

```dart
class MockAdapterWithFailures extends RemoteAdapter {
  int attemptCount = 0;
  
  @override
  Future<void> upsert({required String table, ...}) async {
    attemptCount++;
    
    if (attemptCount < 3) {
      throw TimeoutException('Simulated timeout');
    }
    // Succeed on 3rd attempt
  }
}

test('retry on failure', () async {
  final engine = SyncEngine(
    remoteAdapter: MockAdapterWithFailures(),
    ...
  );
  
  await engine.sync();  // Should succeed after retries
});
```

---

## 🚀 Production Error Handling

```dart
Future<void> setupErrorHandling() async {
  // Catch all platform errors
  PlatformDispatcher.instance.onError = (error, stack) {
    logger.error(
      'Uncaught error',
      error: error,
      stackTrace: stack,
    );
    
    // Send to error tracking service
    sendToSentry(error, stack);
    
    return true;
  };
  
  // Catch all async errors
  runZonedGuarded(
    () => runApp(const MyApp()),
    (error, stack) {
      logger.error('Zone error', error: error, stackTrace: stack);
      sendToSentry(error, stack);
    },
  );
}
```

---

**Error handling is critical for production reliability!** 🛡️
