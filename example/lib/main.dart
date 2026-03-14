import 'package:flutter/material.dart';
import 'package:path/path.dart';
import 'package:replicore/replicore.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'sync/sync_service.dart';
import 'ui/login_screen.dart';
import 'ui/todo_list_screen.dart';

// ── Global app state (accessed by screens via appDb, appEngine, etc.) ────────
late Database appDb;
late SyncEngine appEngine;
late Logger appLogger;
late MetricsCollector appMetricsCollector;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── 1. Initialize Supabase ─────────────────────────────────────────────────
  // IMPORTANT: Run the setup in example/supabase_setup.md to create the tables
  // or provide the required credentials below.
  await Supabase.initialize(
    url: 'https://eymcvxrloanvjapoogkh.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImV5bWN2eHJsb2FudmphcG9vZ2toIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzI2MzM3ODEsImV4cCI6MjA4ODIwOTc4MX0.Coe-WYoXPsf88Xwy4ZIgRyrA0w4nq9Mm1bC5VrCc1lI',
  );

  // ── 2. Open Local SQLite Database ──────────────────────────────────────────
  appDb = await openDatabase(
    join(await getDatabasesPath(), 'replicore_example.db'),
    version: 1,
    onCreate: (db, _) async {
      // Minimal schema — Replicore adds sync columns automatically via
      // ensureSyncColumns() during engine.init().
      await db.execute('''
        CREATE TABLE todos (
          id       TEXT PRIMARY KEY NOT NULL,
          user_id  TEXT NOT NULL,
          title    TEXT NOT NULL,
          is_done  INTEGER NOT NULL DEFAULT 0
        )
      ''');
    },
  );

  // ── 3. Initialize Replicore ────────────────────────────────────────────────

  // Create local store (handles both data and sync cursors)
  final localStore =
      SqfliteStore(appDb, conflictAlgorithm: ConflictAlgorithm.replace);

  // Create remote adapter for Supabase
  final remoteAdapter = SupabaseAdapter(
    client: Supabase.instance.client,
    localStore: localStore,
    postgresChangeEventAll: PostgresChangeEvent.all,
    isAuthException: (e) => e is AuthException,
  );

  // Create logger (console output for development)
  appLogger = ConsoleLogger(minLevel: LogLevel.info);

  // Create metrics collector (in-memory for this example)
  appMetricsCollector = InMemoryMetricsCollector();

  // Create SyncEngine with production configuration
  appEngine = SyncEngine(
    localStore: localStore,
    remoteAdapter: remoteAdapter,
    config: ReplicoreConfig.production(),
    logger: appLogger,
    metricsCollector: appMetricsCollector,
  )..registerTable(
      TableConfig(
        name: 'todos',
        primaryKey: 'id',
        columns: [
          'id',
          'user_id',
          'title',
          'is_done',
          'updated_at',
          'deleted_at',
        ],
        // Last write (most recent timestamp) wins on conflict
        strategy: SyncStrategy.lastWriteWins,
      ),
    );

  // Initialize engine (idempotent — safe to call on every app start)
  try {
    await appEngine.init();
  } catch (e) {
    appLogger.error('Failed to initialize Replicore engine', error: e);
    // Continue anyway — the app can still function offline
  }

  // ── 4. Setup Background Sync ───────────────────────────────────────────────
  SyncService.instance.start(engine: appEngine);

  runApp(TodoApp(
    db: appDb,
    engine: appEngine,
    logger: appLogger,
    metricsCollector: appMetricsCollector,
  ));
}

// ── Root Widget ────────────────────────────────────────────────────────────────

class TodoApp extends StatelessWidget {
  final Database db;
  final SyncEngine engine;
  final Logger logger;
  final MetricsCollector metricsCollector;

  const TodoApp({
    super.key,
    required this.db,
    required this.engine,
    required this.logger,
    required this.metricsCollector,
  });

  @override
  Widget build(BuildContext context) {
    final currentUser = Supabase.instance.client.auth.currentUser;

    return MaterialApp(
      title: 'Replicore Todo Example',
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
      ),
      home: currentUser != null
          ? TodoListScreen(
              db: db,
              engine: engine,
              logger: logger,
              metricsCollector: metricsCollector,
            )
          : const LoginScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
