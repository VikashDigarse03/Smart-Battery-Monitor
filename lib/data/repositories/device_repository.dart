import '../database/app_database.dart';
import '../../domain/models/models.dart';

/// Repository for ESP32 device registration and management.
class DeviceRepository {
  final AppDatabase _db;

  DeviceRepository(this._db);

  Future<List<Device>> getAllDevices() async {
    final db = await _db.database;
    final results = await db.query('devices', orderBy: 'device_id ASC');
    return results.map(_mapRowToDevice).toList();
  }

  Future<Device?> findByDeviceId(String deviceId) async {
    final db = await _db.database;
    final results = await db.query(
      'devices',
      where: 'device_id = ?',
      whereArgs: [deviceId],
    );
    if (results.isEmpty) return null;
    return _mapRowToDevice(results.first);
  }

  Future<Device?> findByBluetoothAddress(String address) async {
    final db = await _db.database;
    final results = await db.query(
      'devices',
      where: 'bluetooth_address = ?',
      whereArgs: [address],
    );
    if (results.isEmpty) return null;
    return _mapRowToDevice(results.first);
  }

  Future<int> insertDevice(Device device) async {
    final db = await _db.database;
    final now = DateTime.now().toIso8601String();
    return await db.insert('devices', {
      'device_id': device.deviceId,
      'name': device.name,
      'bluetooth_address': device.bluetoothAddress,
      'wifi_ip_address': device.wifiIpAddress,
      'wifi_ssid': device.wifiSsid,
      'status': device.status,
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<void> updateLastConnected(int id) async {
    final db = await _db.database;
    await db.update(
      'devices',
      {
        'last_connected_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateDevice(Device device) async {
    final db = await _db.database;
    await db.update(
      'devices',
      {
        'name': device.name,
        'bluetooth_address': device.bluetoothAddress,
        'wifi_ip_address': device.wifiIpAddress,
        'wifi_ssid': device.wifiSsid,
        'status': device.status,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [device.id],
    );
  }

  /// Generate next ESP32 device ID.
  Future<String> generateNextDeviceId() async {
    final db = await _db.database;
    final results = await db.rawQuery(
      'SELECT COUNT(*) as count FROM devices',
    );
    final count = (results.first['count'] as int?) ?? 0;
    return 'ESP32-${(count + 1).toString().padLeft(4, '0')}';
  }

  Device _mapRowToDevice(Map<String, Object?> row) {
    return Device(
      id: row['id'] as int?,
      deviceId: row['device_id'] as String,
      name: row['name'] as String?,
      bluetoothAddress: row['bluetooth_address'] as String?,
      wifiIpAddress: row['wifi_ip_address'] as String?,
      wifiSsid: row['wifi_ssid'] as String?,
      lastConnectedAt: row['last_connected_at'] != null
          ? DateTime.tryParse(row['last_connected_at'] as String)
          : null,
      status: (row['status'] as String?) ?? 'active',
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }
}
