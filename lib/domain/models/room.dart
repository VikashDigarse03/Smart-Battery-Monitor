/// Represents a physical battery room in the building.
class Room {
  final int? id;
  final String name;
  final String? description;
  final bool isArchived;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Room({
    this.id,
    required this.name,
    this.description,
    this.isArchived = false,
    required this.createdAt,
    required this.updatedAt,
  });

  Room copyWith({
    int? id,
    String? name,
    String? description,
    bool? isArchived,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Room(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      isArchived: isArchived ?? this.isArchived,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
