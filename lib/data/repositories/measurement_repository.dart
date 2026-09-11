import '../../domain/models/models.dart';
import '../database/app_database.dart';

/// Repository for measurement CRUD and history queries.
class MeasurementRepository {
  final AppDatabase _db;

  MeasurementRepository(this._db);

  /// Save a new measurement and create a 'measured' battery event.
  Future<int> saveMeasurement(Measurement measurement) async {
    final db = await _db.database;
    final now = DateTime.now().toIso8601String();

    late int id;
    await db.transaction((txn) async {
      id = await txn.insert('measurements', {
        'battery_id': measurement.batteryId,
        'device_id': measurement.deviceId,
        'voltage': measurement.voltage,
        'current_amps': measurement.current,
        'temperature': measurement.temperature,
        'power': measurement.power,
        'battery_percent': measurement.batteryPercent,
        'battery_health': measurement.batteryHealth,
        'time_left': measurement.timeLeft,
        'measured_at': measurement.measuredAt.toIso8601String(),
        'sync_status': measurement.syncStatus,
        'created_at': now,
      });

      // Also record a lifecycle event
      await txn.insert('battery_events', {
        'battery_id': measurement.batteryId,
        'event_type': BatteryEventType.measured.toDbString(),
        'description':
            'V=${measurement.voltage}V, I=${measurement.current}A, T=${measurement.temperature}°C',
        'event_date': measurement.measuredAt.toIso8601String(),
        'created_at': now,
      });
    });

    return id;
  }

  /// Get all measurements for a battery, most recent first.
  Future<List<Measurement>> getMeasurementsForBattery(
    int batteryId, {
    int? limit,
  }) async {
    final db = await _db.database;
    String query = '''
      SELECT m.*,
             b.battery_id AS battery_code,
             d.device_id AS device_code
        FROM measurements m
        LEFT JOIN batteries b ON m.battery_id = b.id
        LEFT JOIN devices d ON m.device_id = d.id
       WHERE m.battery_id = ?
       ORDER BY m.measured_at DESC
    ''';

    if (limit != null) {
      query += ' LIMIT $limit';
    }

    final results = await db.rawQuery(query, [batteryId]);
    return results.map(_mapRowToMeasurement).toList();
  }

  /// Get the latest measurement for a battery.
  Future<Measurement?> getLatestMeasurement(int batteryId) async {
    final measurements =
        await getMeasurementsForBattery(batteryId, limit: 1);
    return measurements.isEmpty ? null : measurements.first;
  }

  /// Get measurements within a date range, optionally filtered by room/rack/battery.
  Future<List<Measurement>> getMeasurementsForReport({
    DateTime? fromDate,
    DateTime? toDate,
    int? roomId,
    int? rackId,
    int? batteryDbId,
  }) async {
    final db = await _db.database;

    String query = '''
      SELECT m.*,
             b.battery_id AS battery_code,
             d.device_id AS device_code
        FROM measurements m
        JOIN batteries b ON m.battery_id = b.id
        LEFT JOIN devices d ON m.device_id = d.id
        LEFT JOIN rack_positions rp ON b.current_position_id = rp.id
        LEFT JOIN racks rk ON rp.rack_id = rk.id
        LEFT JOIN rooms r ON rk.room_id = r.id
       WHERE 1=1
    ''';

    final args = <Object?>[];

    if (fromDate != null) {
      query += ' AND m.measured_at >= ?';
      args.add(fromDate.toIso8601String());
    }
    if (toDate != null) {
      query += ' AND m.measured_at <= ?';
      args.add(toDate.toIso8601String());
    }
    if (roomId != null) {
      query += ' AND r.id = ?';
      args.add(roomId);
    }
    if (rackId != null) {
      query += ' AND rk.id = ?';
      args.add(rackId);
    }
    if (batteryDbId != null) {
      query += ' AND b.id = ?';
      args.add(batteryDbId);
    }

    query += ' ORDER BY m.measured_at DESC';

    final results = await db.rawQuery(query, args);
    return results.map(_mapRowToMeasurement).toList();
  }

  /// Count measurements taken today.
  Future<int> getMeasurementsCountToday() async {
    final db = await _db.database;
    final todayStart =
        DateTime.now().copyWith(hour: 0, minute: 0, second: 0, millisecond: 0);
    final results = await db.rawQuery(
      'SELECT COUNT(*) as count FROM measurements WHERE measured_at >= ?',
      [todayStart.toIso8601String()],
    );
    return (results.first['count'] as int?) ?? 0;
  }

  /// Get pending (unsynced) measurements.
  Future<List<Measurement>> getPendingMeasurements() async {
    final db = await _db.database;
    final results = await db.rawQuery('''
      SELECT m.*,
             b.battery_id AS battery_code,
             d.device_id AS device_code
        FROM measurements m
        LEFT JOIN batteries b ON m.battery_id = b.id
        LEFT JOIN devices d ON m.device_id = d.id
       WHERE m.sync_status = 'pending'
       ORDER BY m.measured_at ASC
    ''');
    return results.map(_mapRowToMeasurement).toList();
  }

  /// Mark a measurement as synced.
  Future<void> markAsSynced(int measurementId) async {
    final db = await _db.database;
    await db.update(
      'measurements',
      {'sync_status': 'synced'},
      where: 'id = ?',
      whereArgs: [measurementId],
    );
  }

  Measurement _mapRowToMeasurement(Map<String, Object?> row) {
    return Measurement(
      id: row['id'] as int?,
      batteryId: row['battery_id'] as int,
      deviceId: row['device_id'] as int?,
      voltage: (row['voltage'] as num).toDouble(),
      current: (row['current_amps'] as num).toDouble(),
      temperature: (row['temperature'] as num).toDouble(),
      power: (row['power'] as num?)?.toDouble(),
      batteryPercent: row['battery_percent'] as int?,
      batteryHealth: row['battery_health'] as int?,
      timeLeft: (row['time_left'] as num?)?.toDouble(),
      measuredAt: DateTime.parse(row['measured_at'] as String),
      syncStatus: (row['sync_status'] as String?) ?? 'pending',
      createdAt: DateTime.parse(row['created_at'] as String),
      batteryCode: row['battery_code'] as String?,
      deviceCode: row['device_code'] as String?,
    );
  }
}
