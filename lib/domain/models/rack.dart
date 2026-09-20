/// Represents a physical battery rack within a room.
class Rack {
  final int? id;
  final int roomId;
  final String name;
  final int positionCount;
  final String batteryType;
  final double nominalVoltage;
  final double capacityAh;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Rack({
    this.id,
    required this.roomId,
    required this.name,
    required this.positionCount,
    this.batteryType = 'Lead Acid',
    this.nominalVoltage = 12.0,
    this.capacityAh = 100.0,
    required this.createdAt,
    required this.updatedAt,
  });

  Rack copyWith({
    int? id,
    int? roomId,
    String? name,
    int? positionCount,
    String? batteryType,
    double? nominalVoltage,
    double? capacityAh,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Rack(
      id: id ?? this.id,
      roomId: roomId ?? this.roomId,
      name: name ?? this.name,
      positionCount: positionCount ?? this.positionCount,
      batteryType: batteryType ?? this.batteryType,
      nominalVoltage: nominalVoltage ?? this.nominalVoltage,
      capacityAh: capacityAh ?? this.capacityAh,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
