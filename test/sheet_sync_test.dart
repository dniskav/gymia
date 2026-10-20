import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymia/data/profile_store.dart';
import 'package:gymia/data/sheet_sync_service.dart';
import 'package:gymia/domain/activity.dart';
import 'package:gymia/domain/sheet_context.dart';
import 'package:gymia/domain/sheet_sync.dart';
import 'package:gymia/domain/user_profile.dart';
import 'package:gymia/domain/workout.dart';

Map<String, dynamic> syncSnapshot({
  List<List<String>>? rows,
  List<String>? occupied,
}) => {
  'rows': rows ?? [canonicalHeaders],
  'occupied': occupied ?? [for (var c = 0; c < 7; c++) '0:$c'],
  'merges': <dynamic>[],
  'properties': {
    'sheetId': 7,
    'title': 'Entrenamientos',
    'gridProperties': {'rowCount': 1000, 'columnCount': 26},
  },
};
String proposal(List<Map<String, dynamic>> writes) =>
    '```gymia-sheet-plan\n${jsonEncode({'summary': 'Enviar resultados', 'writes': writes})}\n```';
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await ProfileStore.instance.load();
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ProfileStore.channel, null),
  );
  test(
    'validates exact cells, types, bounds, formulas, merges and complete protocol',
    () {
      final snapshot = syncSnapshot();
      final plan = SheetSyncPlan.parse(
        proposal([
          {'cell': 'B2', 'value': 60},
          {'cell': 'C2', 'value': false},
          {'cell': 'AA10', 'value': '=literal'},
        ]),
        {
          ...snapshot,
          'properties': {
            'sheetId': 7,
            'gridProperties': {'rowCount': 1000, 'columnCount': 30},
          },
        },
      );
      expect(plan.writes.map((w) => w.address), ['B2', 'C2', 'AA10']);
      for (final writes in [
        [
          {'cell': 'A1', 'value': 'overwrites header'},
        ],
        [
          {'cell': 'A1001', 'value': 1},
        ],
        [
          {'cell': 'A0', 'value': 1},
        ],
        [
          {'cell': 'B2', 'value': 1},
          {'cell': 'B2', 'value': 2},
        ],
        [
          {'cell': 'B2', 'value': <String, dynamic>{}},
        ],
        [
          {'cell': 'B2', 'value': 1, 'endpoint': 'untrusted'},
        ],
      ]) {
        expect(
          () => SheetSyncPlan.parse(proposal(writes), snapshot),
          throwsA(isA<ValidationException>()),
        );
      }
      expect(
        () => SheetSyncPlan.parse('```gymia-sheet-plan\n{"writes":', snapshot),
        throwsA(isA<ValidationException>()),
      );
      expect(
        () => SheetSyncPlan.parse(
          proposal([
            {'cell': 'B2', 'value': 1},
          ]),
          {
            ...snapshot,
            'merges': [
              {
                'startRowIndex': 1,
                'endRowIndex': 3,
                'startColumnIndex': 1,
                'endColumnIndex': 3,
              },
            ],
          },
        ),
        throwsA(isA<ValidationException>()),
      );
    },
  );
  test('reviewed updates allow values but always reject formulas', () {
    final occupied = {
      ...syncSnapshot(),
      'entered': {
        '1:1': {'numberValue': 55},
      },
      'occupied': ['1:1'],
    };
    final response = proposal([
      {'cell': 'B2', 'value': 60},
    ]);
    expect(
      () => SheetSyncPlan.parse(response, occupied),
      throwsA(isA<ValidationException>()),
    );
    expect(
      SheetSyncPlan.parse(
        response,
        occupied,
        allowOverwrite: true,
      ).writes.single.value,
      60,
    );
    expect(
      () => SheetSyncPlan.parse(response, {
        ...occupied,
        'entered': {
          '1:1': {'formulaValue': '=SUM(A1:A2)'},
        },
      }, allowOverwrite: true),
      throwsA(isA<ValidationException>()),
    );
  });
  test(
    'canonical export preserves metrics, interval notes, free notes and drafts',
    () {
      final date = DateTime(2026, 10, 19, 18);
      final workout = Workout(
        id: 'workout',
        name: 'Fuerza',
        startedAt: date,
        finishedAt: date.add(const Duration(hours: 1)),
        exercises: [],
      );
      final activity = FocusActivity(
        id: 'a',
        workoutId: workout.id,
        definition: ActivityDefinition(name: 'Press'),
        createdAt: date,
        finishedAt: date.add(const Duration(minutes: 10)),
        draft: 'Dato pendiente importante',
        intervals: [
          ActivityInterval('i', date, date.add(const Duration(seconds: 42))),
        ],
        messages: [
          ActivityMessage(
            id: 'm',
            text: '60kg 10r, carga TOTAL, molestia al final',
            role: 'user',
            recordedAt: date,
            intervalId: 'i',
            metrics: const {'weight_kg': 60, 'reps': 10},
          ),
          ActivityMessage(
            id: 'n',
            text: 'Nota libre original',
            role: 'user',
            recordedAt: date,
          ),
        ],
      );
      final source = sheetWorkoutSource(workout, [activity]);
      final plan = canonicalSheetPlan(source, syncSnapshot())!;
      expect(plan.writes.any((c) => c.value == 42), true);
      expect(
        plan.writes.any((c) => c.value == activity.messages.first.text),
        true,
      );
      expect(plan.writes.any((c) => c.value == 'Nota libre original'), true);
      expect(
        plan.writes.any(
          (c) => '${c.value}'.contains('Dato pendiente importante'),
        ),
        true,
      );
      expect(plan.writes.every((c) => c.row > 0), true);
      expect((source['activities'] as List).single['messages'], hasLength(2));
    },
  );
  test(
    'sync directive accepts creation without a workout and rejects incomplete or extra commands',
    () {
      expect(
        sheetSyncDirective(
          '```gymia-sync\n{"workoutId":"","create":true,"name":"Mis entrenos"}\n```',
        )?['create'],
        true,
      );
      expect(
        sheetSyncDirective(
          '```gymia-sync\n{"workoutId":"x","endpoint":"url"}\n```',
        ),
        null,
      );
      expect(sheetSyncDirective('```gymia-sync\n{"workoutId":"x"'), null);
    },
  );
  test(
    'local destination authorization never moves records or changes profile',
    () async {
      final methods = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ProfileStore.channel, (call) async {
            methods.add(call.method);
            if (call.method == 'connectIdentity') {
              return const UserProfile(
                subject: 'destination',
                email: 'dest@example.test',
              ).toJson();
            }
            if (call.method == 'authorizeWrite') {
              expect((call.arguments as Map)['expectedSubject'], 'destination');
              return true;
            }
            throw StateError(call.method);
          });
      final service = SheetSyncService(profileId: 'local');
      await service.authorize();
      expect(methods, ['connectIdentity', 'authorizeWrite']);
      expect(ProfileStore.instance.activeId, 'local');
      expect(ProfileStore.instance.profiles, isEmpty);
      final next = SheetSyncService(profileId: 'local');
      await next.authorize();
      expect(methods.last, 'authorizeWrite');
      expect(methods.where((m) => m == 'connectIdentity'), hasLength(1));
    },
  );
  test('cancelled/denied permission cannot authorize writes', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ProfileStore.channel, (call) async {
          if (call.method == 'connectIdentity') {
            return const UserProfile(
              subject: 'destination',
              email: 'dest@example.test',
            ).toJson();
          }
          if (call.method == 'authorizeWrite') return false;
          throw StateError('No write allowed');
        });
    final service = SheetSyncService(profileId: 'local');
    await expectLater(service.authorize(), throwsA(isA<ValidationException>()));
    await expectLater(
      service.call('writeWorkout', {}),
      throwsA(isA<ValidationException>()),
    );
    expect(
      await SheetSyncService.storage.read(key: service.destinationKey),
      null,
    );
  });
  test('profile mismatch rejects operation before calling Google', () async {
    final service = SheetSyncService(profileId: 'another-profile');
    await expectLater(service.authorize(), throwsA(isA<ValidationException>()));
  });
  test(
    'interrupted creation persists identity and retries recovery only',
    () async {
      final requests = <Map>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ProfileStore.channel, (call) async {
            if (call.method == 'connectIdentity') {
              return const UserProfile(
                subject: 'destination',
                email: 'dest@example.test',
              ).toJson();
            }
            if (call.method == 'authorizeWrite') return true;
            if (call.method == 'createSpreadsheet') {
              requests.add(call.arguments as Map);
              if (requests.length == 1) {
                throw PlatformException(code: 'GOOGLE_NETWORK');
              }
              return {
                'id': 'created-file',
                'name': 'Entrenos',
                'title': 'Entrenamientos',
              };
            }
            throw StateError(call.method);
          });
      final service = SheetSyncService(profileId: 'local');
      await service.authorize();
      await expectLater(
        service.create('Entrenos'),
        throwsA(isA<PlatformException>()),
      );
      final recovered = await service.create('Different ignored on recovery');
      expect(recovered, isA<SheetContext>());
      expect(requests[0]['recoverOnly'], false);
      expect(requests[1]['recoverOnly'], true);
      expect(requests[0]['requestId'], requests[1]['requestId']);
      expect(requests[1]['name'], 'Entrenos');
    },
  );
  test(
    'multi-day container exports each interval on its real execution date',
    () {
      final start = DateTime(2026, 10, 8, 18);
      final workout = Workout(
        id: 'span',
        name: 'Varias fechas',
        startedAt: start,
        finishedAt: DateTime(2026, 10, 20),
        exercises: [],
      );
      final activity = FocusActivity(
        id: 'a',
        workoutId: 'span',
        definition: ActivityDefinition(name: 'Press'),
        createdAt: start,
        finishedAt: DateTime(2026, 10, 20),
        intervals: [
          ActivityInterval('old', start, start.add(const Duration(minutes: 1))),
          ActivityInterval(
            'new',
            DateTime(2026, 10, 19, 18),
            DateTime(2026, 10, 19, 18, 1),
          ),
        ],
        messages: [],
      );
      final plan =
          canonicalSheetPlan(
            sheetWorkoutSource(workout, [activity]),
            syncSnapshot(),
          )!;
      expect(plan.writes.where((c) => c.column == 0).map((c) => c.value), [
        '2026-10-08',
        '2026-10-19',
      ]);
    },
  );
}
