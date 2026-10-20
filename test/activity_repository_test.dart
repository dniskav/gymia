import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gymia/data/sqlite_workout_repository.dart';
import 'package:gymia/domain/activity.dart';
import 'package:gymia/domain/workout.dart';

void main() {
  sqfliteFfiInit();
  late Directory dir;
  late SqliteWorkoutRepository repo;
  late DateTime now;
  setUp(() async {
    now = DateTime(2026, 10, 8, 10);
    dir = await Directory.systemTemp.createTemp('gymia-activity-');
    repo = await SqliteWorkoutRepository.open(
      factory: databaseFactoryFfi,
      path: '${dir.path}/test.sqlite',
      clock: () => now,
    );
  });
  tearDown(() async {
    await repo.close();
    await dir.delete(recursive: true);
  });
  final strength = ActivityDefinition(
    name: 'Pec Fly',
    restSeconds: 120,
    fields: const [
      {'key': 'weight_kg', 'label': 'Peso', 'unit': 'kg'},
      {'key': 'reps', 'label': 'Reps', 'unit': ''},
      {'key': 'failure', 'label': 'Fallo', 'unit': ''},
    ],
  );

  test(
    'stop fixes end and rest atomically; early/late restart does not wait or duplicate',
    () async {
      final id = await repo.prepareActivity(strength);
      await repo.startInterval(id);
      await expectLater(
        repo.startInterval(id),
        throwsA(isA<ValidationException>()),
      );
      now = now.add(const Duration(seconds: 30));
      await repo.stopInterval(id);
      var a = (await repo.loadActivities()).single;
      expect(a.intervals.single.endedAt, now);
      expect(a.restEndsAt, now.add(const Duration(seconds: 120)));
      await expectLater(
        repo.stopInterval(id),
        throwsA(isA<ValidationException>()),
      );
      now = now.add(const Duration(seconds: 100));
      await repo.recordActivityMessage(id, '60k 13r f');
      await repo.startInterval(id);
      a = (await repo.loadActivities()).single;
      expect(a.restEndsAt, isNull);
      expect(a.intervals.length, 2);
      expect(a.intervals.first.restSeconds, 120);
      expect((a.toJson()['intervals'] as List).first['actualRestSeconds'], 100);
      expect(a.messages.single.intervalId, a.intervals.first.id);
      expect(a.messages.single.metrics, {
        'weight_kg': 60.0,
        'reps': 13,
        'failure': true,
      });
      now = now.add(const Duration(seconds: 30));
      await repo.stopInterval(id);
      now = now.add(const Duration(seconds: 180));
      await repo.startInterval(id);
      expect((await repo.loadActivities()).single.intervals.length, 3);
    },
  );

  test(
    'continuous sport and symptoms persist without strength fields, including draft and backup',
    () async {
      final id = await repo.prepareActivity(
        ActivityDefinition(
          name: 'Fútbol',
          repeated: false,
          restSeconds: 0,
          fields: const [
            {'key': 'goals', 'label': 'Goles', 'unit': ''},
          ],
        ),
      );
      await repo.startInterval(id);
      now = now.add(const Duration(minutes: 60));
      await repo.stopInterval(id);
      final m = await repo.recordActivityMessage(
        id,
        '2 goles; me molestó la rodilla',
        media: ActivityMedia(
          name: 'foto.png',
          mime: 'image/png',
          bytes: Uint8List.fromList([1, 2, 3, 4]),
        ),
      );
      await repo.interpretActivityMessage(m, {'goals': 2});
      await expectLater(
        repo.interpretActivityMessage(m, {'reps': 20}),
        throwsA(isA<ValidationException>()),
      );
      await repo.setActivityDraft(id, 'Además me dio un calambre');
      await repo.close();
      repo = await SqliteWorkoutRepository.open(
        factory: databaseFactoryFfi,
        path: '${dir.path}/test.sqlite',
        clock: () => now,
      );
      var a = (await repo.loadActivities()).single;
      expect(a.draft, 'Además me dio un calambre');
      expect(a.messages.single.text, '2 goles; me molestó la rodilla');
      expect(a.messages.single.metrics, {'goals': 2});
      expect(a.messages.single.mediaName, 'foto.png');
      expect((await repo.loadActivityMedia(a.messages.single.id))!.bytes, [
        1,
        2,
        3,
        4,
      ]);
      expect(a.restEndsAt, isNull);
      await repo.recordActivityMessage(id, a.draft);
      await repo.finishActivity(id, now);
      await repo.finish(a.workoutId);
      final backup = await repo.createBackupJson();
      await repo.restoreBackupJson(backup);
      expect(jsonDecode(await repo.createBackupJson()), jsonDecode(backup));
      a = (await repo.loadActivities()).single;
      expect(a.definition.repeated, isFalse);
      expect(a.messages, hasLength(2));
      expect((await repo.load()).single.setCount, 0);
      // Closing the day's local container never prevents another session today.
      final later = await repo.prepareActivity(
        ActivityDefinition(name: 'Yoga', repeated: false, restSeconds: 0),
      );
      expect(later, isNot(id));
      expect((await repo.load()).length, 2);
    },
  );

  test(
    'cannot finish while running; late reply retains target after switching activity',
    () async {
      final id = await repo.prepareActivity(strength);
      await repo.startInterval(id);
      final interval = (await repo.loadActivities()).single.running!.id;
      await expectLater(
        repo.finishActivity(id, now),
        throwsA(isA<ValidationException>()),
      );
      await expectLater(
        repo.prepareActivity(ActivityDefinition(name: 'Yoga')),
        throwsA(isA<ValidationException>()),
      );
      now = now.add(const Duration(seconds: 30));
      await repo.stopInterval(id);
      await repo.finishActivity(id, now);
      final next = await repo.prepareActivity(
        ActivityDefinition(name: 'Yoga', repeated: false),
      );
      await repo.recordActivityMessage(
        id,
        'Respuesta sobre Pec Fly',
        role: 'assistant',
        intervalId: interval,
      );
      final all = await repo.loadActivities();
      expect(
        all.singleWhere((a) => a.id == id).messages.single.text,
        'Respuesta sobre Pec Fly',
      );
      expect(all.singleWhere((a) => a.id == next).messages, isEmpty);
    },
  );

  test(
    'changing rest uses actual stop and cannot override deterministic metrics',
    () async {
      final id = await repo.prepareActivity(strength);
      await repo.startInterval(id);
      now = now.add(const Duration(seconds: 30));
      await repo.stopInterval(id);
      final stopped = now;
      now = now.add(const Duration(seconds: 10));
      await repo.setActivityRest(id, 180);
      expect(
        (await repo.loadActivities()).single.restEndsAt,
        stopped.add(const Duration(seconds: 180)),
      );
      final message = await repo.recordActivityMessage(id, '60k 13r f');
      await repo.interpretActivityMessage(message, {'weight_kg': 99});
      expect(
        (await repo.loadActivities())
            .single
            .messages
            .single
            .metrics['weight_kg'],
        60,
      );
    },
  );

  test(
    'proposal is bounded data; malformed or multiple proposals cannot prepare',
    () {
      expect(
        ActivityDefinition.proposal(
          '```gymia-activity\n{"name":"Yoga","repeated":false,"restSeconds":0,"fields":[],"instructions":"Consultar molestias previas"}\n```',
        )!.repeated,
        isFalse,
      );
      expect(
        ActivityDefinition.proposal(
          '```gymia-activity\n{"name":"Yoga","repeated":false,"restSeconds":-1,"fields":[],"instructions":""}\n```',
        ),
        isNull,
      );
      expect(
        ActivityDefinition.proposal(
          '```gymia-activity\n{}\n```\n```gymia-activity\n{}\n```',
        ),
        isNull,
      );
      expect(
        compactStrengthMetrics('me dolió el hombro, hice 60k 13r f', strength),
        isEmpty,
      );
    },
  );
  test(
    'rest survives Terminar and selecting another activity, then cancels on Iniciar',
    () async {
      final first = await repo.prepareActivity(strength);
      await repo.startInterval(first);
      now = now.add(const Duration(seconds: 30));
      await repo.stopInterval(first);
      final end = now.add(const Duration(seconds: 120));
      await repo.finishActivity(first, now);
      final next = await repo.prepareActivity(
        ActivityDefinition(name: 'Cinta', repeated: false, restSeconds: 30),
      );
      expect(
        (await repo.loadActivities())
            .singleWhere((a) => a.id == first)
            .restEndsAt,
        end,
      );
      await repo.setActivityRest(first, 150);
      await repo.startInterval(next);
      final previous = (await repo.loadActivities()).singleWhere(
        (a) => a.id == first,
      );
      expect(previous.restEndsAt, isNull);
      expect(previous.intervals.single.restSeconds, 150);
    },
  );
  test(
    'fields can grow from a new result but existing meaning and original are preserved',
    () async {
      final id = await repo.prepareActivity(
        ActivityDefinition(name: 'Fútbol', repeated: false, restSeconds: 0),
      );
      await repo.startInterval(id);
      now = now.add(const Duration(minutes: 30));
      await repo.stopInterval(id);
      final message = await repo.recordActivityMessage(
        id,
        '2 goles y 1 asistencia; molestia de rodilla',
      );
      await repo.interpretActivityMessage(
        message,
        {'goals': 2, 'assists': 1},
        fields: [
          {'key': 'goals', 'label': 'Goles', 'unit': ''},
          {'key': 'assists', 'label': 'Asistencias', 'unit': ''},
        ],
      );
      final a = (await repo.loadActivities()).single;
      expect(a.definition.fields, hasLength(2));
      expect(
        a.messages.single.text,
        '2 goles y 1 asistencia; molestia de rodilla',
      );
      await expectLater(
        repo.interpretActivityMessage(
          message,
          {'goals': 10},
          fields: [
            {'key': 'goals', 'label': 'Goles', 'unit': 'kg'},
          ],
        ),
        throwsA(isA<ValidationException>()),
      );
      expect((await repo.loadActivities()).single.messages.single.metrics, {
        'goals': 2,
        'assists': 1,
      });
    },
  );
  test(
    'changing unstarted preparation keeps notes without manufacturing an interval',
    () async {
      final id = await repo.prepareActivity(strength);
      await repo.recordActivityMessage(id, 'No hay máquina disponible');
      await repo.cancelActivityPreparation(id);
      final next = await repo.prepareActivity(
        ActivityDefinition(name: 'Otra variante'),
      );
      final old = (await repo.loadActivities()).singleWhere((a) => a.id == id);
      expect(old.intervals, isEmpty);
      expect(old.finishIssues, ['not_started']);
      expect(old.messages.single.text, 'No hay máquina disponible');
      expect(next, isNot(id));
    },
  );
  test(
    'rename preserves identity, running clock, metrics and recovery',
    () async {
      final id = await repo.prepareActivity(strength);
      await repo.startInterval(id);
      now = now.add(const Duration(seconds: 20));
      await repo.recordActivityMessage(id, '60k 10r f');
      final before = (await repo.loadActivities()).single;
      await repo.renameActivity(id, 'Pec Fly · máquina nueva');
      final after = (await repo.loadActivities()).single;
      expect(after.id, id);
      expect(after.running!.id, before.running!.id);
      expect(after.running!.startedAt, before.running!.startedAt);
      expect(after.messages.single.metrics, before.messages.single.metrics);
      expect(after.definition.fields, before.definition.fields);
      await repo.close();
      repo = await SqliteWorkoutRepository.open(
        factory: databaseFactoryFfi,
        path: '${dir.path}/test.sqlite',
        clock: () => now,
      );
      expect(
        (await repo.loadActivities()).single.definition.name,
        'Pec Fly · máquina nueva',
      );
    },
  );
  test(
    'failed replacement leaves preparation active; canceled one can resume',
    () async {
      final id = await repo.prepareActivity(strength);
      await repo.recordActivityMessage(id, 'Conservar mi nota');
      await expectLater(
        repo.replaceActivityPreparation(
          id,
          ActivityDefinition(name: 'Fútbol'),
          exerciseId: 'missing',
        ),
        throwsA(isA<ValidationException>()),
      );
      expect((await repo.loadActivities()).single.active, isTrue);
      await repo.cancelActivityPreparation(id);
      await repo.resumeActivityPreparation(id);
      final resumed = (await repo.loadActivities()).single;
      expect(resumed.id, id);
      expect(resumed.active, isTrue);
      expect(resumed.intervals, isEmpty);
      expect(resumed.messages.single.text, 'Conservar mi nota');
      await repo.replaceActivityPreparation(
        id,
        ActivityDefinition(name: 'Fútbol', repeated: false),
      );
      final all = await repo.loadActivities();
      expect(all.where((a) => a.active).single.definition.name, 'Fútbol');
      expect(
        all.singleWhere((a) => a.id == id).messages.single.text,
        'Conservar mi nota',
      );
    },
  );
}
