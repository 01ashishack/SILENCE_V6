import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class OfflineDatabase {
  static final OfflineDatabase instance = OfflineDatabase._init();
  static Database? _database;

  OfflineDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('silence_offline.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 2,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  // v1 → v2: dead-letter support. Failed scans are kept (status='failed') with
  // the last error instead of being silently deleted after max retries, so the
  // user can see "couldn't sync" rather than losing the scan. (audit P1)
  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
          "ALTER TABLE offline_scan_queue ADD COLUMN status TEXT NOT NULL DEFAULT 'pending'");
      await db.execute('ALTER TABLE offline_scan_queue ADD COLUMN last_error TEXT');
    }
  }

  Future<void> _createDB(Database db, int version) async {
    // 1. OFFLINE SCAN QUEUE (Write Queue)
    await db.execute('''
      CREATE TABLE offline_scan_queue (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        library_id TEXT NOT NULL,
        member_id TEXT NOT NULL,
        shift_id TEXT NOT NULL,
        qr_version INTEGER NOT NULL,
        timestamp TEXT NOT NULL,
        device_id TEXT,
        retry_count INTEGER DEFAULT 0,
        synced INTEGER DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'pending',
        last_error TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await db.execute('CREATE INDEX idx_offline_queue_pending ON offline_scan_queue(synced, created_at)');
    await db.execute('CREATE INDEX idx_offline_queue_member_shift ON offline_scan_queue(member_id, shift_id, timestamp)');

    // 2. READ CACHE - MEMBERS (Admin)
    await db.execute('''
      CREATE TABLE cache_members (
        id TEXT PRIMARY KEY,
        library_id TEXT NOT NULL,
        full_name TEXT NOT NULL,
        phone TEXT,
        photo_url TEXT,
        status TEXT,
        seat_label TEXT,
        shift_name TEXT,
        expiry_date TEXT,
        last_seen TEXT,
        cached_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    await db.execute('CREATE INDEX idx_cache_members_library ON cache_members(library_id)');

    // 3. READ CACHE - TODAY'S ATTENDANCE (Admin)
    await db.execute('''
      CREATE TABLE cache_attendance_today (
        id TEXT PRIMARY KEY,
        library_id TEXT NOT NULL,
        member_id TEXT NOT NULL,
        member_name TEXT,
        seat_label TEXT,
        check_in_time TEXT,
        check_out_time TEXT,
        status TEXT,
        session_type TEXT,
        cached_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    await db.execute('CREATE INDEX idx_cache_attendance_library ON cache_attendance_today(library_id)');

    // 4. READ CACHE - SEAT GRID (Admin)
    await db.execute('''
      CREATE TABLE cache_seat_grid (
        id TEXT PRIMARY KEY,
        library_id TEXT NOT NULL,
        shift_id TEXT NOT NULL,
        floor_id TEXT,
        section_id TEXT,
        seat_label TEXT NOT NULL,
        seat_status TEXT,
        occupied_by_member_name TEXT,
        occupied_by_member_id TEXT,
        cached_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    await db.execute('CREATE INDEX idx_cache_seat_grid_library_shift ON cache_seat_grid(library_id, shift_id)');

    // 5. READ CACHE - MEMBER OWN DATA (Member memberships & attendance)
    await db.execute('''
      CREATE TABLE cache_member_memberships (
        id TEXT PRIMARY KEY,
        member_id TEXT NOT NULL,
        library_id TEXT NOT NULL,
        library_name TEXT,
        seat_label TEXT,
        shift_name TEXT,
        plan_type TEXT,
        start_date TEXT,
        end_date TEXT,
        status TEXT,
        days_remaining INTEGER,
        dues_amount INTEGER,
        cached_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await db.execute('''
      CREATE TABLE cache_member_attendance (
        id TEXT PRIMARY KEY,
        member_id TEXT NOT NULL,
        library_id TEXT,
        check_in_time TEXT,
        check_out_time TEXT,
        duration_minutes INTEGER,
        session_type TEXT,
        date TEXT,
        cached_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    await db.execute('CREATE INDEX idx_cache_member_attendance_date ON cache_member_attendance(member_id, date)');

    // 6. SYNC METADATA
    await db.execute('''
      CREATE TABLE sync_metadata (
        key TEXT PRIMARY KEY,
        value TEXT,
        updated_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    // Insert default values
    await db.insert('sync_metadata', {'key': 'last_member_sync', 'value': '1970-01-01T00:00:00Z'});
    await db.insert('sync_metadata', {'key': 'last_attendance_sync', 'value': '1970-01-01T00:00:00Z'});
    await db.insert('sync_metadata', {'key': 'last_seatgrid_sync', 'value': '1970-01-01T00:00:00Z'});
    await db.insert('sync_metadata', {'key': 'cache_version_members', 'value': '1'});
    await db.insert('sync_metadata', {'key': 'cache_version_seatgrid', 'value': '1'});
  }

  Future<void> close() async {
    final db = await instance.database;
    db.close();
  }

  /// Count of scans that exhausted their retries and were dead-lettered
  /// (status='failed'). Surfaced as a visible "couldn't sync" indicator. (audit P1)
  Future<int> failedScanCount() async {
    final db = await instance.database;
    final rows = await db.rawQuery(
        "SELECT COUNT(*) AS c FROM offline_scan_queue WHERE status = 'failed'");
    return (rows.first['c'] as int?) ?? 0;
  }

  /// Re-arm dead-lettered scans for another sync attempt (status→pending,
  /// retry_count→0). Returns how many rows were reset.
  Future<int> retryFailedScans() async {
    final db = await instance.database;
    return db.update(
      'offline_scan_queue',
      {'status': 'pending', 'retry_count': 0},
      where: "status = 'failed'",
    );
  }
}
