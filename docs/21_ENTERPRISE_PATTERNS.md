# Enterprise Patterns & Production Deployment

> **Best practices for enterprise-grade Replicore applications**

---

## 🎯 Enterprise Architecture

### Microservices Pattern

```
┌─────────────────────────────────────────────────┐
│              Mobile App (Flutter)               │
│  ┌────────────────────────────────────────────┐ │
│  │         Replicore Sync Engine             │ │
│  │ ┌──────────────────────────────────────┐  │ │
│  │ │  Local Store (SQLite/Hive/Isar)    │  │ │
│  │ └──────────────────────────────────────┘  │ │
│  └─────────────┬────────────────────────────┘ │
└────────────────┼──────────────────────────────┘
                 │
        ┌────────┴─────────┐
        │                  │
    ┌───▼──────┐      ┌───▼──────┐
    │ Backend  │      │ Real-Time│
    │  API     │      │  Service │
    └──────────┘      └──────────┘
        │                  │
    ┌───▼──────────────────▼───┐
    │    Remote Database      │
    │   (Firebase/Supabase)    │
    └─────────────────────────┘
```

---

## 🔧 Dependency Injection Setup

### Service Locator (GetIt)

```dart
import 'package:get_it/get_it.dart';

final getIt = GetIt.instance;

Future<void> setupServices() async {
  // 1. Database
  final db = await openDatabase(
    join(await getDatabasesPath(), 'app.db'),
  );
  
  // 2. Stores
  final localStore = SqfliteLocalStore(db);
  
  // 3. Adapters
  final remoteAdapter = FirebaseAdapter(
    FirebaseFirestore.instance,
  );
  
  // 4. Configuration
  final config = ReplicoreConfig(
    batchSize: 50,
    maxRetries: 3,
    autoSync: true,
  );
  
  // 5. Logger
  final logger = _setupLogger();
  
  // 6. Engine
  final engine = SyncEngine(
    localStore: localStore,
    remoteAdapter: remoteAdapter,
    config: config,
  );
  
  // 7. Register for injection
  getIt.registerSingleton<SyncEngine>(engine);
  getIt.registerSingleton<LocalStore>(localStore);
  getIt.registerSingleton<RemoteAdapter>(remoteAdapter);
  
  // 8. Initialize
  await engine.initialize();
}

Logger _setupLogger() {
  final loggers = <Logger>[];
  
  // Console logging in dev
  loggers.add(ConsoleLogger());
  
  // Sentry for error tracking in prod
  if (kReleaseMode) {
    loggers.add(SentryLogger());
  }
  
  return MultiLogger(loggers);
}
```

---

## 📊 Monitoring & Observability

### Health Checks

```dart
class HealthChecker {
  final SyncEngine engine;
  
  Future<HealthStatus> check() async {
    try {
      // Local health
      if (!engine.isInitialized) {
        return HealthStatus.unhealthy('Engine not initialized');
      }
      
      // Remote health
      final remoteOk = await engine.remoteAdapter.ping();
      if (!remoteOk) {
        return HealthStatus.degraded('Remote unavailable');
      }
      
      // Sync health
      final metrics = engine.getMetrics();
      if (metrics.errorRate > 0.1) {
        return HealthStatus.degraded('High error rate');
      }
      
      return HealthStatus.healthy();
    } catch (e) {
      return HealthStatus.unhealthy(e.toString());
    }
  }
}

// Use in periodic check
Timer.periodic(Duration(minutes: 5), (_) async {
  final health = await healthChecker.check();
  if (!health.isHealthy) {
    sendAlert('Replicore health: ${health.status}');
  }
});
```

### Metrics Collection

```dart
class MetricsCollector {
  final Map<String, dynamic> metrics = {};
  
  void recordSync({
    required int duration,
    required int recordsPushed,
    required int recordsPulled,
    required bool success,
  }) {
    metrics['last_sync'] = {
      'timestamp': DateTime.now().toIso8601String(),
      'duration_ms': duration,
      'records_pushed': recordsPushed,
      'records_pulled': recordsPulled,
      'success': success,
    };
    
    // Send to analytics
    _sendToDatadog(metrics);
  }
  
  void _sendToDatadog(Map<String, dynamic> data) {
    // Implementation with Datadog/Firebase Analytics
  }
}

// Integrate with engine
engine.onSyncComplete.listen((result) {
  metricsCollector.recordSync(
    duration: result.duration.inMilliseconds,
    recordsPushed: result.recordsPushed,
    recordsPulled: result.recordsPulled,
    success: true,
  );
});
```

---

## 🔐 Security Best Practices

### Authentication Management

```dart
class SecureAdapter extends RemoteAdapter {
  final AuthService authService;
  
  @override
  Future<List<Map>> pull({
    required String table,
    required DateTime since,
  }) async {
    // Get fresh token
    final token = await authService.getRefreshToken();
    
    // Use in headers
    final headers = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
    
    // Make request
    return api.pull(table, since, headers);
  }
  
  @override
  Future<void> upsert({
    required String table,
    required List<Map> records,
  }) async {
    // Always use current token
    final token = await authService.getAccessToken();
    
    try {
      await api.upsert(table, records, token);
    } on AuthException {
      // Token expired, refresh
      await authService.refreshToken();
      rethrow;
    }
  }
}
```

### Data Encryption

```dart
// Local data encryption
final encryptedDb = await openDatabase(
  'app.db',
  onOpen: (db) {
    db.execute("PRAGMA key = '${encryptionKey}'");
  },
);

// Sensitive field encryption
class EncryptedTodo {
  final String uuid;
  final String encryptedTitle;
  
  String get title {
    return encrypt.decrypt(encryptedTitle);
  }
  
  static EncryptedTodo fromTodo(Todo todo) {
    return EncryptedTodo(
      uuid: todo.uuid,
      encryptedTitle: encrypt.encrypt(todo.title),
    );
  }
}
```

---

## 🚀 Deployment Strategy

### Staging Environment

```dart
enum Environment {
  development,
  staging,
  production,
}

class EnvironmentConfig {
  static final Environment current = 
    kDebugMode ? Environment.development : Environment.production;
  
  static ReplicoreConfig getSyncConfig() {
    switch (current) {
      case Environment.development:
        return ReplicoreConfig(
          autoSync: false,
          showLogs: true,
          logLevel: 'debug',
        );
      
      case Environment.staging:
        return ReplicoreConfig(
          autoSync: true,
          syncInterval: Duration(minutes: 1),
          showLogs: true,
          logLevel: 'info',
        );
      
      case Environment.production:
        return ReplicoreConfig(
          autoSync: true,
          syncInterval: Duration(minutes: 5),
          showLogs: false,
          maxRetries: 5,
          retryDelay: Duration(seconds: 2),
        );
    }
  }
}
```

### Blue-Green Deployment

```dart
class DeploymentManager {
  // Current active version
  String activeVersion = '1.0.0';
  String stagingVersion = '1.1.0';
  
  Future<void> deployStaging() async {
    // Test in staging environment
    final testEngine = SyncEngine(
      localStore: stagingStore,
      remoteAdapter: stagingAdapter,
    );
    
    await runTests(testEngine);
    
    // If successful, promotes to active
    activeVersion = stagingVersion;
    await restartEngine();
  }
}
```

---

## 📈 Scaling Strategies

### Connection Pooling

```dart
class ConnectionPool {
  final int maxConnections = 10;
  final Queue<HiveBox> availableBoxes = Queue();
  
  Future<HiveBox> acquire() async {
    if (availableBoxes.isEmpty) {
      return await _createNewConnection();
    }
    return availableBoxes.removeFirst();
  }
  
  void release(HiveBox box) {
    availableBoxes.addLast(box);
  }
}
```

### Data Archiving

```dart
class DataArchiver {
  Future<void> archiveOldRecords(String table) async {
    final thirtyDaysAgo = 
      DateTime.now().subtract(Duration(days: 30));
    
    final oldRecords = await engine.readLocalWhere(
      table,
      where: 'updated_at < ?',
      whereArgs: [thirtyDaysAgo.toIso8601String()],
    );
    
    // Move to archive
    await _exportToArchiveStorage(oldRecords);
    
    // Delete from active
    for (var record in oldRecords) {
      await engine.deleteLocal(table, record['uuid']);
    }
  }
}
```

---

## 🧪 Testing Enterprise Apps

### Integration Tests

```dart
void main() {
  group('Enterprise Sync', () {
    late SyncEngine engine;
    
    setUpAll(() async {
      await setupTestServices();
      engine = getIt<SyncEngine>();
    });
    
    test('handles 10000 record sync', () async {
      // Create test data
      final records = List.generate(10000, (i) => {
        'uuid': 'test-$i',
        'title': 'Todo $i',
      });
      
      await engine.bulkWrite('todos', records);
      
      final stopwatch = Stopwatch()..start();
      await engine.sync();
      stopwatch.stop();
      
      // Should complete in <5 seconds with batching
      expect(stopwatch.elapsedMilliseconds, lessThan(5000));
    });
    
    test('recovers from network failure', () async {
      // Simulate network error
      whenCalling(mockAdapter.pull())
          .thenThrowError(NetworkException());
      
      // Should retry
      await engine.sync();
      
      // Verify retry happened
      verify(mockAdapter.pull()).called(greaterThan(1));
    });
  });
}
```

---

## 📋 Production Checklist

### Before Deployment

- [ ] All tests passing (unit, integration, e2e)
- [ ] Performance benchmarks meet targets
- [ ] Error handling tested for all failure modes
- [ ] Security review completed
- [ ] Logging configured correctly
- [ ] Monitoring/alerting set up
- [ ] Backup strategy documented
- [ ] Rollback plan documented
- [ ] Load testing completed
- [ ] User acceptance testing passed

### After Deployment

- [ ] Monitor error rates (should be <1%)
- [ ] Watch sync performance (should be <5s per cycle)
- [ ] Check battery drain (should be <5% per hour)
- [ ] Monitor disk usage (should be stable)
- [ ] Verify real-time updates working
- [ ] Test offline-online transitions
- [ ] Monitor user reports
- [ ] Plan for rollback if issues

---

## 🔄 Continuous Monitoring

### Dashboard Setup

```dart
class DashboardService {
  Stream<DashboardMetrics> getMetrics() async* {
    while (true) {
      final metrics = engine.getMetrics();
      
      yield DashboardMetrics(
        lastSyncTime: metrics.avgDuration,
        errorRate: metrics.errorRate,
        dataSynced: metrics.totalRecordsPushed,
        uptime: _calculateUptime(),
      );
      
      await Future.delayed(Duration(minutes: 1));
    }
  }
  
  Future<void> sendToDatadog(DashboardMetrics m) {
    // Send metrics to Datadog/New Relic/etc
  }
}
```

---

## 🚨 Error Handling Enterprise Way

```dart
class EnterpriseErrorHandler {
  void handleSyncError(Exception error) {
    // Log with context
    logger.error(
      'Sync failed',
      error: error,
      extra: {
        'app_version': packageInfo.version,
        'device': deviceInfo,
        'memory': getMemoryUsage(),
      },
    );
    
    // Track in analytics
    analytics.logEvent(
      name: 'sync_error',
      parameters: {
        'error_type': error.runtimeType.toString(),
        'is_network': error is NetworkException,
      },
    );
    
    // Alert if critical
    if (error is DatabaseException) {
      sendSlackAlert('Database error: $error');
    }
  }
}
```

---

**Enterprise deployments require planning and monitoring!** 🏢
