import 'space.dart';
import 'workout.dart';

enum FieldType { number, text, boolean, choice, attachment }

class FieldDefinition {
  FieldDefinition({
    required String id,
    required this.type,
    required String label,
    this.unit,
    List<String> options = const [],
  }) : id = validTrackiaId(id),
       label = validName(label),
       options = List.unmodifiable(options) {
    if (unit != null && unit!.length > 80 ||
        (type == FieldType.choice && this.options.isEmpty) ||
        (type != FieldType.choice && this.options.isNotEmpty) ||
        this.options.length > 100 ||
        this.options.toSet().length != this.options.length) {
      throw const ValidationException('La definición del campo no es válida.');
    }
    for (final option in this.options) {
      validName(option);
    }
  }

  final String id;
  final FieldType type;
  final String label;
  final String? unit;
  final List<String> options;
}

/// A definition is an immutable revision; accepted plans take their own snapshot.
class TrackiaActivityDefinition {
  TrackiaActivityDefinition({
    required String id,
    required this.scope,
    required String name,
    List<FieldDefinition> fields = const [],
    this.instructions = '',
    this.revision = 1,
    this.schemaVersion = 1,
  }) : id = validTrackiaId(id),
       name = validName(name),
       fields = List.unmodifiable(fields) {
    if (revision < 1 ||
        schemaVersion < 1 ||
        instructions.length > 8000 ||
        this.fields.length > 128 ||
        this.fields.map((f) => f.id).toSet().length != this.fields.length) {
      throw const ValidationException(
        'La definición de actividad no es válida.',
      );
    }
  }

  final String id;
  final SpaceScope scope;
  final String name;
  final List<FieldDefinition> fields;
  final String instructions;
  final int revision;
  final int schemaVersion;

  /// Missing is null; an explicit zero stays zero.
  Object? valueFor(String fieldId, Map<String, Object?> values) {
    if (!fields.any((field) => field.id == fieldId)) {
      throw const ValidationException(
        'El campo no pertenece a esta actividad.',
      );
    }
    return values[fieldId];
  }

  TrackiaActivityDefinition snapshot() => TrackiaActivityDefinition(
    id: id,
    scope: scope,
    name: name,
    fields: fields,
    instructions: instructions,
    revision: revision,
    schemaVersion: schemaVersion,
  );

  TrackiaActivityDefinition edit({
    String? name,
    List<FieldDefinition>? fields,
    String? instructions,
  }) => TrackiaActivityDefinition(
    id: id,
    scope: scope,
    name: name ?? this.name,
    fields: fields ?? this.fields,
    instructions: instructions ?? this.instructions,
    revision: revision + 1,
    schemaVersion: schemaVersion,
  );
}
