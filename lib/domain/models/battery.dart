/// Lifecycle status of a battery.
enum BatteryStatus {
  active,
  inactive,
  underMaintenance,
  retired,
  removed;

  String get displayName {
    switch (this) {
      case BatteryStatus.active:
        return 'Active';
      case BatteryStatus.inactive:
        return 'Inactive';
      case BatteryStatus.underMaintenance:
        return 'Under Maintenance';
      case BatteryStatus.retired:
        return 'Retired';
      case BatteryStatus.removed:
        return 'Removed';
    }
  }

  static BatteryStatus fromString(String value) {
    switch (value) {
      case 'active':
        return BatteryStatus.active;
      case 'inactive':
        return BatteryStatus.inactive;
      case 'under_maintenance':
        return BatteryStatus.underMaintenance;
      case 'retired':
        return BatteryStatus.retired;
      case 'removed':
        return BatteryStatus.removed;
      default:
        return BatteryStatus.active;
    }
  }

  String toDbString() {
    switch (this) {
      case BatteryStatus.active:
        return 'active';
      case BatteryStatus.inactive:
        return 'inactive';
      case BatteryStatus.underMaintenance:
        return 'under_maintenance';
      case BatteryStatus.retired:
        return 'retired';
      case BatteryStatus.removed:
        return 'removed';
    }
  }
}

/// Represents a physical battery with its metadata and current state.
class Battery {
  final int? id;
  final String batteryId; // e.g., "BAT-000123"
  final String? manufacturer;
  final String? model;
  final String? serialNumber;
  final String batteryType; // e.g., "Lead Acid"
  final double nominalVoltage; // e.g., 12.0
  final double? capacityAh; // e.g., 100.0
  final BatteryStatus status;
  final DateTime? installationDate;
  final DateTime? retirementDate;
  final int? currentPositionId;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Denormalized location info (populated via joins)
  final String? roomName;
  final String? rackName;
  final int? positionNumber;

  const Battery({
    this.id,
    required this.batteryId,
    this.manufacturer,
    this.model,
    this.serialNumber,
    this.batteryType = 'Lead Acid',
    this.nominalVoltage = 12.0,
    this.capacityAh,
    this.status = BatteryStatus.active,
    this.installationDate,
    this.retirementDate,
    this.currentPositionId,
    required this.createdAt,
    required this.updatedAt,
    this.roomName,
    this.rackName,
    this.positionNumber,
  });

  /// Returns the full location string, e.g., "Room 2 / Rack 3 / Position 15"
  String get locationString {
    final parts = <String>[];
    if (roomName != null) parts.add(roomName!);
    if (rackName != null) parts.add(rackName!);
    if (positionNumber != null) parts.add('Position $positionNumber');
    return parts.isEmpty ? 'Unassigned' : parts.join(' / ');
  }

  Battery copyWith({
    int? id,
    String? batteryId,
    String? manufacturer,
    String? model,
    String? serialNumber,
    String? batteryType,
    double? nominalVoltage,
    double? capacityAh,
    BatteryStatus? status,
    DateTime? installationDate,
    DateTime? retirementDate,
    int? currentPositionId,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? roomName,
    String? rackName,
    int? positionNumber,
  }) {
    return Battery(
      id: id ?? this.id,
      batteryId: batteryId ?? this.batteryId,
      manufacturer: manufacturer ?? this.manufacturer,
      model: model ?? this.model,
      serialNumber: serialNumber ?? this.serialNumber,
      batteryType: batteryType ?? this.batteryType,
      nominalVoltage: nominalVoltage ?? this.nominalVoltage,
      capacityAh: capacityAh ?? this.capacityAh,
      status: status ?? this.status,
      installationDate: installationDate ?? this.installationDate,
      retirementDate: retirementDate ?? this.retirementDate,
      currentPositionId: currentPositionId ?? this.currentPositionId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      roomName: roomName ?? this.roomName,
      rackName: rackName ?? this.rackName,
      positionNumber: positionNumber ?? this.positionNumber,
    );
  }
}
