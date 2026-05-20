/// Immutable domain model for an event where cards were exchanged.
class Event {
  const Event({
    required this.id,
    required this.name,
    this.date,
    this.memo,
  });

  final String id;
  final String name;
  final DateTime? date;
  final String? memo;

  Event copyWith({
    String? id,
    String? name,
    DateTime? date,
    String? memo,
  }) {
    return Event(
      id: id ?? this.id,
      name: name ?? this.name,
      date: date ?? this.date,
      memo: memo ?? this.memo,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Event &&
          other.id == id &&
          other.name == name &&
          other.date == date &&
          other.memo == memo;

  @override
  int get hashCode => Object.hash(id, name, date, memo);

  @override
  String toString() => 'Event(id: $id, name: $name, date: $date, memo: $memo)';
}
