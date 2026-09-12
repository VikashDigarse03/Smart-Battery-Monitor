import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

/// Singleton database helper for the Battery Monitor application.
///
/// Creates and manages the SQLite database with all tables for batteries,
/// measurements, rooms, racks, positions, devices, events, assignments,
/// and app settings.
class AppDatabase {
  static final AppDatabase _instance = AppDatabase._internal();
  factory AppDatabase() => _instance;
  AppDatabase._internal();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'battery_monitor.db');

    return await openDatabase(
      path,
      version: 2, // Upgraded to v2 to support rack-level specs
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }
  
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Since this is pre-production, simply wipe and recreate.
    await db.execute('DROP TABLE IF EXISTS app_settings');
    await db.execute('DROP TABLE IF EXISTS battery_events');
    await db.execute('DROP TABLE IF EXISTS measurements');
    await db.execute('DROP TABLE IF EXISTS battery_assignments');
    await db.execute('DROP TABLE IF EXISTS batteries');
    await db.execute('DROP TABLE IF EXISTS rack_positions');
    await db.execute('DROP TABLE IF EXISTS racks');
    await db.execute('DROP TABLE IF EXISTS rooms');
    await db.execute('DROP TABLE IF EXISTS devices');
    await _onCreate(db, newVersion);
  }

  Future<void> _onCreate(Database db, int version) async {
    // ─── Rooms ────────────────────────────────────────────────
    await db.execute('''
      CREATE TABLE rooms (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        description TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // ─── Racks ────────────────────────────────────────────────
    await db.execute('''
      CREATE TABLE racks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        room_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        position_count INTEGER NOT NULL DEFAULT 20,
        battery_type TEXT NOT NULL DEFAULT 'Lead Acid',
        nominal_voltage REAL NOT NULL DEFAULT 12.0,
        capacity_ah REAL NOT NULL DEFAULT 100.0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (room_id) REFERENCES rooms(id) ON DELETE CASCADE
      )
    ''');

    // ─── Rack Positions ───────────────────────────────────────
    await db.execute('''
      CREATE TABLE rack_positions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        rack_id INTEGER NOT NULL,
        position_number INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (rack_id) REFERENCES racks(id) ON DELETE CASCADE,
        UNIQUE(rack_id, position_number)
      )
    ''');

    // ─── Batteries ────────────────────────────────────────────
    await db.execute('''
      CREATE TABLE batteries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        battery_id TEXT NOT NULL UNIQUE,
        serial_number TEXT,
        status TEXT NOT NULL DEFAULT 'active',
        installation_date TEXT,
        retirement_date TEXT,
        current_position_id INTEGER,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (current_position_id) REFERENCES rack_positions(id)
          ON DELETE SET NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_batteries_battery_id ON batteries(battery_id)',
    );
    await db.execute(
      'CREATE INDEX idx_batteries_status ON batteries(status)',
    );

    // ─── Battery Assignments ──────────────────────────────────
    await db.execute('''
      CREATE TABLE battery_assignments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        battery_id INTEGER NOT NULL,
        position_id INTEGER NOT NULL,
        assigned_at TEXT NOT NULL,
        removed_at TEXT,
        is_current INTEGER NOT NULL DEFAULT 1,
        FOREIGN KEY (battery_id) REFERENCES batteries(id) ON DELETE CASCADE,
        FOREIGN KEY (position_id) REFERENCES rack_positions(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_assignments_current ON battery_assignments(is_current)',
    );

    // ─── Measurements ─────────────────────────────────────────
    await db.execute('''
      CREATE TABLE measurements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        battery_id INTEGER NOT NULL,
        device_id INTEGER,
        voltage REAL NOT NULL,
        current_amps REAL NOT NULL,
        temperature REAL NOT NULL,
        power REAL,
        battery_percent INTEGER,
        battery_health INTEGER,
        time_left REAL,
        measured_at TEXT NOT NULL,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        created_at TEXT NOT NULL,
        FOREIGN KEY (battery_id) REFERENCES batteries(id) ON DELETE CASCADE,
        FOREIGN KEY (device_id) REFERENCES devices(id) ON DELETE SET NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_measurements_battery ON measurements(battery_id)',
    );
    await db.execute(
      'CREATE INDEX idx_measurements_date ON measurements(measured_at)',
    );
    await db.execute(
      'CREATE INDEX idx_measurements_sync ON measurements(sync_status)',
    );

    // ─── Battery Events ───────────────────────────────────────
    await db.execute('''
      CREATE TABLE battery_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        battery_id INTEGER NOT NULL,
        event_type TEXT NOT NULL,
        description TEXT,
        event_date TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (battery_id) REFERENCES batteries(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_events_battery ON battery_events(battery_id)',
    );

    // ─── Devices (ESP32s) ─────────────────────────────────────
    await db.execute('''
      CREATE TABLE devices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        device_id TEXT NOT NULL UNIQUE,
        name TEXT,
        bluetooth_address TEXT,
        wifi_ip_address TEXT,
        wifi_ssid TEXT,
        last_connected_at TEXT,
        status TEXT NOT NULL DEFAULT 'active',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // ─── App Settings (key-value store) ───────────────────────
    await db.execute('''
      CREATE TABLE app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    // ─── Seed default settings ────────────────────────────────
    await _seedDefaults(db);
  }

  Future<void> _seedDefaults(Database db) async {
    // Insert default Room 1
    final now = DateTime.now().toIso8601String();
    await db.insert('rooms', {
      'name': 'Room 1',
      'description': 'Default battery room',
      'created_at': now,
      'updated_at': now,
    });

    // Insert default settings (ESP32 thresholds & calibration)
    final defaults = {
      'volt_critical_low': '10.5',
      'volt_warning_low': '11.5',
      'volt_normal_low': '12.0',
      'volt_full': '12.7',
      'volt_overcharge': '14.8',
      'temp_warning': '45.0',
      'temp_critical': '55.0',
      'current_warning': '20.0',
      'current_critical': '28.0',
      'voltage_divider_ratio': '5.0',
      'voltage_calibration': '1.0',
      'acs712_sensitivity': '66.0',
      'current_divider_ratio': '0.5',
      'acs712_zero_offset': '1300.0',
      'adc_samples': '64',
      'voltage_connected_threshold': '1.0',
      'battery_capacity_ah': '100',
      'esp32_ip_address': '192.168.4.1',
      'esp32_wifi_ssid': 'ESP32_Battery',
      'esp32_wifi_password': '12345678',
      'connection_mode': 'bluetooth', // 'bluetooth' or 'wifi'
      'next_battery_number': '1', // For auto-generating BAT-XXXXXX
    };

    for (final entry in defaults.entries) {
      await db.insert('app_settings', {
        'key': entry.key,
        'value': entry.value,
      });
    }
  }

  /// Retrieve a single setting value.
  Future<String?> getSetting(String key) async {
    final db = await database;
    final results = await db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: [key],
    );
    if (results.isEmpty) return null;
    return results.first['value'] as String?;
  }

  /// Update or insert a setting.
  Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.insert(
      'app_settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get all settings as a map.
  Future<Map<String, String>> getAllSettings() async {
    final db = await database;
    final results = await db.query('app_settings');
    return {
      for (final row in results) row['key'] as String: row['value'] as String,
    };
  }

  /// Close the database connection.
  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }
}
