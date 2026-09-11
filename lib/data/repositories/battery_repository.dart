
import '../../domain/models/models.dart';
import '../database/app_database.dart';

/// Repository for battery CRUD operations and ID generation.
class BatteryRepository {
  final AppDatabase _db;

  BatteryRepository(this._db);

  /// Generates the next unique battery ID (e.g., BAT-000001).
  Future<String> generateNextBatteryId() async {
    final numberStr = await _db.getSetting('next_battery_number');
    final number = int.parse(numberStr ?? '1');
    final batteryId = 'BAT-${number.toString().padLeft(6, '0')}';

    // Increment the counter
    await _db.setSetting('next_battery_number', '${number + 1}');
    return batteryId;
  }

  /// Insert a new battery. Returns the row ID.
  Future<int> insertBattery(Battery battery) async {
    final db = await _db.database;
    final now = DateTime.now().toIso8601String();
    return await db.insert('batteries', {
      'battery_id': battery.batteryId,
      'manufacturer': battery.manufacturer,
      'model': battery.model,
      'serial_number': battery.serialNumber,
      'battery_type': battery.batteryType,
      'nominal_voltage': battery.nominalVoltage,
      'capacity_ah': battery.capacityAh,
      'status': battery.status.toDbString(),
      'installation_date': battery.installationDate?.toIso8601String(),
      'retirement_date': battery.retirementDate?.toIso8601String(),
      'current_position_id': battery.currentPositionId,
      'created_at': now,
      'updated_at': now,
    });
  }

  /// Look up a battery by its human-readable ID (e.g., BAT-000123).
  Future<Battery?> findByBatteryId(String batteryId) async {
    final db = await _db.database;
    final results = await db.rawQuery('''
      SELECT b.*,
             r.name AS room_name,
             rk.name AS rack_name,
             rp.position_number
        FROM batteries b
        LEFT JOIN rack_positions rp ON b.current_position_id = rp.id
        LEFT JOIN racks rk ON rp.rack_id = rk.id
        LEFT JOIN rooms r ON rk.room_id = r.id
       WHERE b.battery_id = ?
    ''', [batteryId]);

    if (results.isEmpty) return null;
    return _mapRowToBattery(results.first);
  }

  /// Get a battery by its database row ID.
  Future<Battery?> findById(int id) async {
    final db = await _db.database;
    final results = await db.rawQuery('''
      SELECT b.*,
             r.name AS room_name,
             rk.name AS rack_name,
             rp.position_number
        FROM batteries b
        LEFT JOIN rack_positions rp ON b.current_position_id = rp.id
        LEFT JOIN racks rk ON rp.rack_id = rk.id
        LEFT JOIN rooms r ON rk.room_id = r.id
       WHERE b.id = ?
    ''', [id]);

    if (results.isEmpty) return null;
    return _mapRowToBattery(results.first);
  }

  /// Get all batteries with optional status filter.
  Future<List<Battery>> getAllBatteries({BatteryStatus? status}) async {
    final db = await _db.database;
    String query = '''
      SELECT b.*,
             r.name AS room_name,
             rk.name AS rack_name,
             rp.position_number
        FROM batteries b
        LEFT JOIN rack_positions rp ON b.current_position_id = rp.id
        LEFT JOIN racks rk ON rp.rack_id = rk.id
        LEFT JOIN rooms r ON rk.room_id = r.id
    ''';

    List<Object?> args = [];
    if (status != null) {
      query += ' WHERE b.status = ?';
      args.add(status.toDbString());
    }
    query += ' ORDER BY b.battery_id ASC';

    final results = await db.rawQuery(query, args);
    return results.map(_mapRowToBattery).toList();
  }

  /// Get batteries at a specific rack position.
  Future<Battery?> getBatteryAtPosition(int positionId) async {
    final db = await _db.database;
    final results = await db.rawQuery('''
      SELECT b.*,
             r.name AS room_name,
             rk.name AS rack_name,
             rp.position_number
        FROM batteries b
        LEFT JOIN rack_positions rp ON b.current_position_id = rp.id
        LEFT JOIN racks rk ON rp.rack_id = rk.id
        LEFT JOIN rooms r ON rk.room_id = r.id
       WHERE b.current_position_id = ?
         AND b.status = 'active'
    ''', [positionId]);

    if (results.isEmpty) return null;
    return _mapRowToBattery(results.first);
  }

  /// Update battery status.
  Future<void> updateBatteryStatus(int id, BatteryStatus status) async {
    final db = await _db.database;
    await db.update(
      'batteries',
      {
        'status': status.toDbString(),
        'updated_at': DateTime.now().toIso8601String(),
        if (status == BatteryStatus.retired)
          'retirement_date': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Assign battery to a rack position.
  Future<void> assignToPosition(int batteryId, int positionId) async {
    final db = await _db.database;
    final now = DateTime.now().toIso8601String();

    await db.transaction((txn) async {
      // Close any existing assignment for this position
      await txn.update(
        'battery_assignments',
        {'is_current': 0, 'removed_at': now},
        where: 'position_id = ? AND is_current = 1',
        whereArgs: [positionId],
      );

      // Close any existing assignment for this battery
      await txn.update(
        'battery_assignments',
        {'is_current': 0, 'removed_at': now},
        where: 'battery_id = ? AND is_current = 1',
        whereArgs: [batteryId],
      );

      // Create new assignment
      await txn.insert('battery_assignments', {
        'battery_id': batteryId,
        'position_id': positionId,
        'assigned_at': now,
        'is_current': 1,
      });

      // Update battery's current position
      await txn.update(
        'batteries',
        {
          'current_position_id': positionId,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [batteryId],
      );
    });
  }

  /// Replace a battery at a position. Retires old battery and assigns new one.
  Future<void> replaceBattery({
    required int oldBatteryId,
    required int newBatteryId,
    required int positionId,
    String? retirementReason,
  }) async {
    final db = await _db.database;
    final now = DateTime.now();
    final nowStr = now.toIso8601String();

    await db.transaction((txn) async {
      // Retire old battery
      await txn.update(
        'batteries',
        {
          'status': BatteryStatus.retired.toDbString(),
          'retirement_date': nowStr,
          'current_position_id': null,
          'updated_at': nowStr,
        },
        where: 'id = ?',
        whereArgs: [oldBatteryId],
      );

      // Close old assignment
      await txn.update(
        'battery_assignments',
        {'is_current': 0, 'removed_at': nowStr},
        where: 'battery_id = ? AND is_current = 1',
        whereArgs: [oldBatteryId],
      );

      // Record retirement event
      await txn.insert('battery_events', {
        'battery_id': oldBatteryId,
        'event_type': BatteryEventType.retired.toDbString(),
        'description':
            retirementReason ?? 'Battery replaced',
        'event_date': nowStr,
        'created_at': nowStr,
      });

      // Assign new battery
      await txn.insert('battery_assignments', {
        'battery_id': newBatteryId,
        'position_id': positionId,
        'assigned_at': nowStr,
        'is_current': 1,
      });

      // Update new battery
      await txn.update(
        'batteries',
        {
          'current_position_id': positionId,
          'status': BatteryStatus.active.toDbString(),
          'installation_date': nowStr,
          'updated_at': nowStr,
        },
        where: 'id = ?',
        whereArgs: [newBatteryId],
      );

      // Record installation event
      await txn.insert('battery_events', {
        'battery_id': newBatteryId,
        'event_type': BatteryEventType.installed.toDbString(),
        'description': 'Battery installed (replacement)',
        'event_date': nowStr,
        'created_at': nowStr,
      });
    });
  }

  /// Get total battery count by status.
  Future<Map<String, int>> getBatteryCounts() async {
    final db = await _db.database;
    final results = await db.rawQuery('''
      SELECT status, COUNT(*) as count
        FROM batteries
       GROUP BY status
    ''');

    final counts = <String, int>{'total': 0};
    for (final row in results) {
      final status = row['status'] as String;
      final count = row['count'] as int;
      counts[status] = count;
      counts['total'] = (counts['total'] ?? 0) + count;
    }
    return counts;
  }

  Battery _mapRowToBattery(Map<String, Object?> row) {
    return Battery(
      id: row['id'] as int?,
      batteryId: row['battery_id'] as String,
      manufacturer: row['manufacturer'] as String?,
      model: row['model'] as String?,
      serialNumber: row['serial_number'] as String?,
      batteryType: (row['battery_type'] as String?) ?? 'Lead Acid',
      nominalVoltage: (row['nominal_voltage'] as num?)?.toDouble() ?? 12.0,
      capacityAh: (row['capacity_ah'] as num?)?.toDouble(),
      status: BatteryStatus.fromString(
        (row['status'] as String?) ?? 'active',
      ),
      installationDate: row['installation_date'] != null
          ? DateTime.tryParse(row['installation_date'] as String)
          : null,
      retirementDate: row['retirement_date'] != null
          ? DateTime.tryParse(row['retirement_date'] as String)
          : null,
      currentPositionId: row['current_position_id'] as int?,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
      roomName: row['room_name'] as String?,
      rackName: row['rack_name'] as String?,
      positionNumber: row['position_number'] as int?,
    );
  }
}
