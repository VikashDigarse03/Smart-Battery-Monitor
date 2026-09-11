/// A single measurement record taken from an ESP32 device for a specific battery.
///
/// Measurements are immutable historical records — they are never updated or
/// deleted. Each measurement captures the sensor readings at a point in time,
/// along with derived values computed by the ESP32 firmware.
class Measurement {
  final int? id;
  final int batteryId; // FK → batteries.id
  final int? deviceId; // FK → devices.id
  final double voltage;
  final double current;
  final double temperature;
  final double? power; // voltage × |current|
  final int? batteryPercent; // SOC from ESP32
  final int? batteryHealth; // SOH from ESP32
  final double? timeLeft; // Hours remaining (from ESP32)
  final DateTime measuredAt;
  final String syncStatus; // 'pending', 'synced', 'failed'
  final DateTime createdAt;

  // Denormalized info for display
  final String? batteryCode; // e.g., "BAT-000123"
  final String? deviceCode; // e.g., "ESP32-0001"

  const Measurement({
    this.id,
    required this.batteryId,
    this.deviceId,
    required this.voltage,
    required this.current,
    required this.temperature,
    this.power,
    this.batteryPercent,
    this.batteryHealth,
    this.timeLeft,
    required this.measuredAt,
    this.syncStatus = 'pending',
    required this.createdAt,
    this.batteryCode,
    this.deviceCode,
  });

  Measurement copyWith({
    int? id,
    int? batteryId,
    int? deviceId,
    double? voltage,
    double? current,
    double? temperature,
    double? power,
    int? batteryPercent,
    int? batteryHealth,
    double? timeLeft,
    DateTime? measuredAt,
    String? syncStatus,
    DateTime? createdAt,
    String? batteryCode,
    String? deviceCode,
  }) {
    return Measurement(
      id: id ?? this.id,
      batteryId: batteryId ?? this.batteryId,
      deviceId: deviceId ?? this.deviceId,
      voltage: voltage ?? this.voltage,
      current: current ?? this.current,
      temperature: temperature ?? this.temperature,
      power: power ?? this.power,
      batteryPercent: batteryPercent ?? this.batteryPercent,
      batteryHealth: batteryHealth ?? this.batteryHealth,
      timeLeft: timeLeft ?? this.timeLeft,
      measuredAt: measuredAt ?? this.measuredAt,
      syncStatus: syncStatus ?? this.syncStatus,
      createdAt: createdAt ?? this.createdAt,
      batteryCode: batteryCode ?? this.batteryCode,
      deviceCode: deviceCode ?? this.deviceCode,
    );
  }
}
