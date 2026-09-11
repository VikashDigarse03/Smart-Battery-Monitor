/// Represents a physical slot within a rack where a battery can be installed.
class RackPosition {
  final int? id;
  final int rackId;
  final int positionNumber;
  final DateTime createdAt;

  const RackPosition({
    this.id,
    required this.rackId,
    required this.positionNumber,
    required this.createdAt,
  });

  RackPosition copyWith({
    int? id,
    int? rackId,
    int? positionNumber,
    DateTime? createdAt,
  }) {
    return RackPosition(
      id: id ?? this.id,
      rackId: rackId ?? this.rackId,
      positionNumber: positionNumber ?? this.positionNumber,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
