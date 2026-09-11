import '../../domain/models/models.dart';
import '../database/app_database.dart';

/// Repository for rooms, racks, and rack positions.
class LocationRepository {
  final AppDatabase _db;

  LocationRepository(this._db);

  // ─── Rooms ──────────────────────────────────────────────────

  Future<List<Room>> getAllRooms() async {
    final db = await _db.database;
    final results = await db.query('rooms', orderBy: 'name ASC');
    return results.map(_mapRowToRoom).toList();
  }

  Future<Room?> getRoomById(int id) async {
    final db = await _db.database;
    final results = await db.query('rooms', where: 'id = ?', whereArgs: [id]);
    if (results.isEmpty) return null;
    return _mapRowToRoom(results.first);
  }

  Future<int> insertRoom(String name, {String? description}) async {
    final db = await _db.database;
    final now = DateTime.now().toIso8601String();
    return await db.insert('rooms', {
      'name': name,
      'description': description,
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<void> updateRoom(int id, String name, {String? description}) async {
    final db = await _db.database;
    await db.update(
      'rooms',
      {
        'name': name,
        'description': description,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteRoom(int id) async {
    final db = await _db.database;
    await db.delete('rooms', where: 'id = ?', whereArgs: [id]);
  }

  // ─── Racks ──────────────────────────────────────────────────

  Future<List<Rack>> getRacksForRoom(int roomId) async {
    final db = await _db.database;
    final results = await db.query(
      'racks',
      where: 'room_id = ?',
      whereArgs: [roomId],
      orderBy: 'name ASC',
    );
    return results.map(_mapRowToRack).toList();
  }

  Future<Rack?> getRackById(int id) async {
    final db = await _db.database;
    final results = await db.query('racks', where: 'id = ?', whereArgs: [id]);
    if (results.isEmpty) return null;
    return _mapRowToRack(results.first);
  }

  /// Insert a rack and auto-create its positions.
  Future<int> insertRack(
    int roomId,
    String name, {
    int positionCount = 20,
  }) async {
    final db = await _db.database;
    final now = DateTime.now().toIso8601String();

    late int rackId;
    await db.transaction((txn) async {
      rackId = await txn.insert('racks', {
        'room_id': roomId,
        'name': name,
        'position_count': positionCount,
        'created_at': now,
        'updated_at': now,
      });

      // Auto-create positions
      for (int i = 1; i <= positionCount; i++) {
        await txn.insert('rack_positions', {
          'rack_id': rackId,
          'position_number': i,
          'created_at': now,
        });
      }
    });

    return rackId;
  }

  Future<void> deleteRack(int id) async {
    final db = await _db.database;
    await db.delete('racks', where: 'id = ?', whereArgs: [id]);
  }

  // ─── Rack Positions ─────────────────────────────────────────

  Future<List<RackPosition>> getPositionsForRack(int rackId) async {
    final db = await _db.database;
    final results = await db.query(
      'rack_positions',
      where: 'rack_id = ?',
      whereArgs: [rackId],
      orderBy: 'position_number ASC',
    );
    return results.map(_mapRowToRackPosition).toList();
  }

  /// Get positions for a rack with battery info (for the position grid).
  /// Returns a list of maps with position + battery details.
  Future<List<Map<String, dynamic>>> getPositionsWithBatteries(
    int rackId,
  ) async {
    final db = await _db.database;
    final results = await db.rawQuery('''
      SELECT rp.id AS position_id,
             rp.position_number,
             b.id AS battery_db_id,
             b.battery_id AS battery_code,
             b.status AS battery_status,
             (SELECT m.voltage FROM measurements m
               WHERE m.battery_id = b.id
               ORDER BY m.measured_at DESC LIMIT 1) AS latest_voltage
        FROM rack_positions rp
        LEFT JOIN batteries b ON b.current_position_id = rp.id
                              AND b.status = 'active'
       WHERE rp.rack_id = ?
       ORDER BY rp.position_number ASC
    ''', [rackId]);

    return results;
  }

  // ─── Mappers ────────────────────────────────────────────────

  Room _mapRowToRoom(Map<String, Object?> row) {
    return Room(
      id: row['id'] as int?,
      name: row['name'] as String,
      description: row['description'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  Rack _mapRowToRack(Map<String, Object?> row) {
    return Rack(
      id: row['id'] as int?,
      roomId: row['room_id'] as int,
      name: row['name'] as String,
      positionCount: (row['position_count'] as int?) ?? 20,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  RackPosition _mapRowToRackPosition(Map<String, Object?> row) {
    return RackPosition(
      id: row['id'] as int?,
      rackId: row['rack_id'] as int,
      positionNumber: row['position_number'] as int,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }
}
