/// Types of lifecycle events that can occur for a battery.
enum BatteryEventType {
  installed,
  measured,
  maintenance,
  replaced,
  retired,
  removed,
  statusChanged,
  locationChanged;

  String get displayName {
    switch (this) {
      case BatteryEventType.installed:
        return 'Installed';
      case BatteryEventType.measured:
        return 'Measurement Performed';
      case BatteryEventType.maintenance:
        return 'Maintenance';
      case BatteryEventType.replaced:
        return 'Replaced';
      case BatteryEventType.retired:
        return 'Retired';
      case BatteryEventType.removed:
        return 'Removed';
      case BatteryEventType.statusChanged:
        return 'Status Changed';
      case BatteryEventType.locationChanged:
        return 'Location Changed';
    }
  }

  static BatteryEventType fromString(String value) {
    switch (value) {
      case 'installed':
        return BatteryEventType.installed;
      case 'measured':
        return BatteryEventType.measured;
      case 'maintenance':
        return BatteryEventType.maintenance;
      case 'replaced':
        return BatteryEventType.replaced;
      case 'retired':
        return BatteryEventType.retired;
      case 'removed':
        return BatteryEventType.removed;
      case 'status_changed':
        return BatteryEventType.statusChanged;
      case 'location_changed':
        return BatteryEventType.locationChanged;
      default:
        return BatteryEventType.statusChanged;
    }
  }

  String toDbString() {
    switch (this) {
      case BatteryEventType.installed:
        return 'installed';
      case BatteryEventType.measured:
        return 'measured';
      case BatteryEventType.maintenance:
        return 'maintenance';
      case BatteryEventType.replaced:
        return 'replaced';
      case BatteryEventType.retired:
        return 'retired';
      case BatteryEventType.removed:
        return 'removed';
      case BatteryEventType.statusChanged:
        return 'status_changed';
      case BatteryEventType.locationChanged:
        return 'location_changed';
    }
  }
}

/// A lifecycle event for a battery (installation, maintenance, replacement, etc.).
class BatteryEvent {
  final int? id;
  final int batteryId;
  final BatteryEventType eventType;
  final String? description;
  final DateTime eventDate;
  final DateTime createdAt;

  const BatteryEvent({
    this.id,
    required this.batteryId,
    required this.eventType,
    this.description,
    required this.eventDate,
    required this.createdAt,
  });

  BatteryEvent copyWith({
    int? id,
    int? batteryId,
    BatteryEventType? eventType,
    String? description,
    DateTime? eventDate,
    DateTime? createdAt,
  }) {
    return BatteryEvent(
      id: id ?? this.id,
      batteryId: batteryId ?? this.batteryId,
      eventType: eventType ?? this.eventType,
      description: description ?? this.description,
      eventDate: eventDate ?? this.eventDate,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
