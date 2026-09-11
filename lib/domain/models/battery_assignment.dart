/// Tracks which battery is/was assigned to which rack position.
///
/// When a battery is moved or replaced, the old assignment gets a [removedAt]
/// timestamp and [isCurrent] set to false, and a new assignment is created.
class BatteryAssignment {
  final int? id;
  final int batteryId;
  final int positionId;
  final DateTime assignedAt;
  final DateTime? removedAt;
  final bool isCurrent;

  const BatteryAssignment({
    this.id,
    required this.batteryId,
    required this.positionId,
    required this.assignedAt,
    this.removedAt,
    this.isCurrent = true,
  });

  BatteryAssignment copyWith({
    int? id,
    int? batteryId,
    int? positionId,
    DateTime? assignedAt,
    DateTime? removedAt,
    bool? isCurrent,
  }) {
    return BatteryAssignment(
      id: id ?? this.id,
      batteryId: batteryId ?? this.batteryId,
      positionId: positionId ?? this.positionId,
      assignedAt: assignedAt ?? this.assignedAt,
      removedAt: removedAt ?? this.removedAt,
      isCurrent: isCurrent ?? this.isCurrent,
    );
  }
}
