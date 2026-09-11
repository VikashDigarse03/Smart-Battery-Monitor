/// Represents a registered ESP32 measurement device.
class Device {
  final int? id;
  final String deviceId; // e.g., "ESP32-0001"
  final String? name;
  final String? bluetoothAddress; // MAC address for BT pairing
  final String? wifiIpAddress; // IP when connected via WiFi AP
  final String? wifiSsid; // ESP32 AP SSID
  final DateTime? lastConnectedAt;
  final String status; // 'active', 'inactive'
  final DateTime createdAt;
  final DateTime updatedAt;

  const Device({
    this.id,
    required this.deviceId,
    this.name,
    this.bluetoothAddress,
    this.wifiIpAddress,
    this.wifiSsid,
    this.lastConnectedAt,
    this.status = 'active',
    required this.createdAt,
    required this.updatedAt,
  });

  Device copyWith({
    int? id,
    String? deviceId,
    String? name,
    String? bluetoothAddress,
    String? wifiIpAddress,
    String? wifiSsid,
    DateTime? lastConnectedAt,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Device(
      id: id ?? this.id,
      deviceId: deviceId ?? this.deviceId,
      name: name ?? this.name,
      bluetoothAddress: bluetoothAddress ?? this.bluetoothAddress,
      wifiIpAddress: wifiIpAddress ?? this.wifiIpAddress,
      wifiSsid: wifiSsid ?? this.wifiSsid,
      lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
