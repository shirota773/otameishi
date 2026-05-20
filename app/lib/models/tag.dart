/// Immutable domain model for a user-defined tag.
class Tag {
  const Tag({required this.id, required this.name});

  final String id;
  final String name;

  Tag copyWith({String? id, String? name}) {
    return Tag(id: id ?? this.id, name: name ?? this.name);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Tag && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);

  @override
  String toString() => 'Tag(id: $id, name: $name)';
}
