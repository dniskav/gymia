import 'package:flutter_test/flutter_test.dart';
import 'package:gymia/application/capability_registry.dart';
import 'package:gymia/domain/activity_definition.dart';
import 'package:gymia/domain/space.dart';
import 'package:gymia/domain/workout.dart';

void main() {
  test('a space has an immutable owner and rejects a foreign scope', () {
    final space = TrackiaSpace(
      id: 'gym',
      profileId: 'local',
      name: ' Gimnasio ',
    );
    expect(space.name, 'Gimnasio');
    expect(space.scope, SpaceScope(profileId: 'local', spaceId: 'gym'));
    expect(
      () => space.requireScope(
        SpaceScope(profileId: 'google_other', spaceId: 'gym'),
      ),
      throwsA(isA<ValidationException>()),
    );
    expect(
      () => TrackiaSpace(id: '../gym', profileId: 'local', name: 'Gimnasio'),
      throwsA(isA<ValidationException>()),
    );
    expect(
      SpaceScope(
        profileId: 'google_${List.filled(171, 'a').join()}',
        spaceId: 'gym',
      ).profileId,
      hasLength(178),
    );
  });

  test(
    'fields retain identity, unit, missing values and accepted snapshots',
    () {
      final original = TrackiaActivityDefinition(
        id: 'stretch',
        scope: SpaceScope(profileId: 'local', spaceId: 'gym'),
        name: 'Estiramiento',
        fields: [
          FieldDefinition(
            id: 'duration',
            type: FieldType.number,
            label: 'Tiempo',
            unit: 'min',
          ),
          FieldDefinition(
            id: 'feeling',
            type: FieldType.text,
            label: 'Sensación',
          ),
        ],
      );
      final snapshot = original.snapshot();
      final revised = original.edit(name: 'Estiramiento suave');
      expect(revised.revision, 2);
      expect(original.revision, 1);
      expect(snapshot.name, 'Estiramiento');
      expect(snapshot.fields.first.unit, 'min');
      expect(snapshot.valueFor('duration', const {}), isNull);
      expect(snapshot.valueFor('duration', const {'duration': 0}), 0);
      expect(
        () => original.fields.add(
          FieldDefinition(id: 'x', type: FieldType.text, label: 'X'),
        ),
        throwsUnsupportedError,
      );
      expect(
        () => TrackiaActivityDefinition(
          id: 'bad',
          scope: SpaceScope(profileId: 'local', spaceId: 'gym'),
          name: ' X ',
          fields: [
            FieldDefinition(id: 'same', type: FieldType.text, label: 'A'),
            FieldDefinition(id: 'same', type: FieldType.text, label: 'B'),
          ],
        ),
        throwsA(isA<ValidationException>()),
      );
    },
  );

  test('capabilities validate supported versions and keep legacy aliases', () {
    final registry = CapabilityRegistry.current;
    expect(registry.supports('gymia-activity', 1), isTrue);
    expect(registry.supports('gymia-sheet-plan', 1), isTrue);
    expect(registry.supports('trackia-linear-run', 1), isFalse);
    expect(registry.supports('gymia-activity', 2), isFalse);
    expect(
      registry.validate([const CapabilityRequirement('gymia-activity', 1)]),
      isEmpty,
    );
    expect(
      registry.validate([
        const CapabilityRequirement('trackia-audio-guide', 1),
      ]),
      contains('trackia-audio-guide'),
    );
  });
}
