/// Represents a physical battery rack within a room.
class Rack {
  final int? id;
  final int roomId;
  final String name;
  final int positionCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Rack({
    this.id,
    required this.roomId,
    required this.name,
    required this.positionCount,
    required this.createdAt,
    required this.updatedAt,
  });

  Rack copyWith({
    int? id,
    int? roomId,
    String? name,
    int? positionCount,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Rack(
      id: id ?? this.id,
      roomId: roomId ?? this.roomId,
      name: name ?? this.name,
      positionCount: positionCount ?? this.positionCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
