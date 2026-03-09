# Configuration & Environment Management

> **Complete guide to ReplicoreConfig and environment-specific settings**

---

## 🎯 ReplicoreConfig

### Basic Configuration

```dart
final config = ReplicoreConfig(
  batchSize: 500,          // Records per batch
  maxRetries: 3,            // Auto-retry failed syncs
  syncInterval: Duration(minutes: 5), // Auto-sync interval
  logLevel: LogLevel.info,  // Logging verbosity
);

final engine = SyncEngine(
  localStore: localStore,
  remoteAdapter: remoteAdapter,
  config: config,
);
```

---

## 📊 Configuration Presets

### Production Preset ⭐

```dart
final config = ReplicoreConfig.production();
// Equivalent to:
ReplicoreConfig(
  batchSize: 500,        // Optimal throughput
  maxRetries: 5,         // Retry failures
  syncInterval: Duration(minutes: 5),
  logLevel: LogLevel.warning,  // Minimal logging
  enableMetrics: true,
  enableHealthChecks: true,
);
```

**When to use**: Live apps, production servers

**Characteristics**:
- ✅ Optimized for performance
- ✅ Error recovery enabled
- ✅ Metrics collection on
- ✅ Minimal logging overhead

### Development Preset

```dart
final config = ReplicoreConfig.development();
// Equivalent to:
ReplicoreConfig(
  batchSize: 10,         // Debug batches
  maxRetries: 1,
  syncInterval: Duration(seconds: 30),
  logLevel: LogLevel.debug,  // Verbose logging
  enableMetrics: true,
  enableHealthChecks: true,
);
```

**When to use**: Development environment

**Characteristics**:
- ✅ Detailed logging
- ✅ Fast feedback loops
- ✅ Small batches for debugging

### Testing Preset

```dart
final config = ReplicoreConfig.testing();
// Equivalent to:
ReplicoreConfig(
  batchSize: 5,
  maxRetries: 0,         // Fail fast
  syncInterval: Duration(milliseconds: 500),
  logLevel: LogLevel.trace,  // Maximum verbosity
  enableMetrics: false,  // No overhead
);
```

**When to use**: Unit and integration tests

**Characteristics**:
- ✅ No randomness
- ✅ Deterministic
- ✅ Fast execution

---

## ⚙️ Configuration Options

### Batch Size

```dart
ReplicoreConfig(
  batchSize: 500,  // Default: optimal for most backends
)

// Guidance:
// <= 100: Fragile networks, frequent failures
// 500: Default, balanced
// 1000+: Fast networks, fewer requests
```

### Retry Strategy

```dart
ReplicoreConfig(
  maxRetries: 3,  // Retry up to 3 times
  retryDelay: Duration(seconds: 2),  // 2s, then exponential backoff
)

// Increases to: 2s → 4s → 8s
```

### Logging

```dart
ReplicoreConfig(
  logLevel: LogLevel.info,
)

// Levels:
// trace: Everything (very verbose)
// debug: All operations
// info: Important events only
// warning: Errors and warnings
// error: Errors only
```

### Metrics

```dart
ReplicoreConfig(
  enableMetrics: true,
  metricsCollector: InMemoryMetricsCollector(),
)

// Or use custom:
class CustomMetrics implements MetricsCollector {
  @override
  void recordSync(SyncMetrics metrics) {
    // Send to analytics
  }
}

config.metricsCollector = CustomMetrics();
```

---

## 🌍 Environment-Specific Setup

### Production

```dart
final config = ReplicoreConfig.production()
  .copyWith(
    batchSize: 1000,  // High-load optimization
    syncInterval: Duration(minutes: 10),  // Less frequent
  );
```

### Staging

```dart
final config = ReplicoreConfig.production()
  .copyWith(
    logLevel: LogLevel.debug,  // More detail
    enableHealthChecks: true,
  );
```

### Development

```dart
final config = ReplicoreConfig.development()
  .copyWith(
    enableDevTools: true,  // Debug tools
  );
```

### Testing

```dart
final config = ReplicoreConfig.testing()
  .copyWith(
    mockResponses: true,  // No network calls
  );
```

---

## 🔐 Secrets Management

### Environment Variables

```bash
# .env
SUPABASE_URL=https://xxx.supabase.co
SUPABASE_KEY=xxx
DATABASE_KEY=xxx
```

### Load in Code

```dart
import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<void> main() async {
  await dotenv.load();
  runApp(const MyApp());
}

final supabaseUrl = dotenv.env['SUPABASE_URL']!;
final supabaseKey = dotenv.env['SUPABASE_KEY']!;
```

### Secure Storage

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final storage = const FlutterSecureStorage();

// Save token
await storage.write(key: 'auth_token', value: token);

// Read token
final token = await storage.read(key: 'auth_token');

// Delete token
await storage.delete(key: 'auth_token');
```

---

## 📋 Configuration Checklist

### Development ✓
- [ ] Debug logging enabled
- [ ] Small batch size
- [ ] Dev tools enabled
- [ ] Mock data available

### Staging ✓
- [ ] Same config as production except logging
- [ ] Real backend connection
- [ ] Comprehensive logging
- [ ] Health checks enabled

### Production ✓
- [ ] Production preset used
- [ ] Metrics collection enabled
- [ ] Error handlers implemented
- [ ] Secrets secured
- [ ] Logging optimized
- [ ] Batch size tuned
- [ ] Health monitoring active

---

**Configuration is critical for production stability!** ⚙️
