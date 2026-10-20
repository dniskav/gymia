import 'dart:convert';
import 'dart:typed_data';
import 'workout.dart';

class ActivityDefinition {
  ActivityDefinition({
    required String name,
    this.repeated = true,
    this.restSeconds = 90,
    List<Map<String, String>> fields = const [],
    this.instructions = '',
    this.origin = 'user',
  }) : name = validName(name),
       fields = List.unmodifiable(
         fields.map((f) => Map<String, String>.unmodifiable(f)),
       ) {
    validName(name);
    if (restSeconds < 0 ||
        restSeconds > 1800 ||
        fields.length > 12 ||
        instructions.length > 3000 ||
        fields.map((f) => f['key']).toSet().length != fields.length) {
      throw const ValidationException(
        'La propuesta de actividad no es válida.',
      );
    }
    for (final field in fields) {
      if (field.keys.toSet().difference({'key', 'label', 'unit'}).isNotEmpty ||
          !field.keys.toSet().containsAll({'key', 'label', 'unit'}) ||
          !RegExp(r'^[a-z][a-z0-9_]{0,39}$').hasMatch(field['key'] ?? '') ||
          (field['label'] ?? '').isEmpty ||
          (field['label'] ?? '').length > 80 ||
          (field['unit'] ?? '').length > 30) {
        throw const ValidationException('Los datos propuestos no son válidos.');
      }
    }
  }
  final String name, instructions, origin;
  final bool repeated;
  final int restSeconds;
  final List<Map<String, String>> fields;
  Map<String, dynamic> toJson() => {
    'name': name,
    'repeated': repeated,
    'restSeconds': restSeconds,
    'fields': fields,
    'instructions': instructions,
    'origin': origin,
  };
  factory ActivityDefinition.fromJson(Map<String, dynamic> value) =>
      ActivityDefinition(
        name: value['name'] as String,
        repeated: value['repeated'] as bool,
        restSeconds: value['restSeconds'] as int,
        fields:
            (value['fields'] as List)
                .map((f) => Map<String, String>.from(f as Map))
                .toList(),
        instructions: value['instructions'] as String? ?? '',
        origin: value['origin'] as String? ?? 'user',
      );

  static ActivityDefinition? proposal(String response) {
    final matches =
        RegExp(
          r'```gymia-activity\s*\n([\s\S]*?)```',
        ).allMatches(response).toList();
    if (matches.length != 1) return null;
    try {
      final json = jsonDecode(matches.single.group(1)!) as Map<String, dynamic>;
      if (json.keys.toSet().difference({
        'name',
        'repeated',
        'restSeconds',
        'fields',
        'instructions',
      }).isNotEmpty) {
        return null;
      }
      return ActivityDefinition.fromJson({...json, 'origin': 'llm'});
    } catch (_) {
      return null;
    }
  }
}

class ActivityInterval {
  const ActivityInterval(
    this.id,
    this.startedAt,
    this.endedAt, {
    this.restSeconds,
  });
  final String id;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int? restSeconds;
  Map<String, dynamic> toJson() => {
    'id': id,
    'startedAt': startedAt.toIso8601String(),
    'endedAt': endedAt?.toIso8601String(),
    'plannedRestSeconds': restSeconds,
  };
}

class ActivityMedia {
  ActivityMedia({
    required this.name,
    required this.mime,
    required Uint8List bytes,
  }) : bytes = Uint8List.fromList(bytes) {
    if (name.isEmpty ||
        name.length > 255 ||
        bytes.isEmpty ||
        bytes.length > 4 * 1024 * 1024 ||
        ![
          'image/png',
          'image/jpeg',
          'image/webp',
          'audio/mpeg',
          'audio/wav',
          'audio/mp4',
          'audio/ogg',
          'audio/flac',
          'application/pdf',
        ].contains(mime)) {
      throw const ValidationException('El adjunto no es válido o supera 4 MB.');
    }
  }
  final String name, mime;
  final Uint8List bytes;
  Map<String, dynamic> metadata() => {'name': name, 'mime': mime};
  Map<String, dynamic> toJson() => {
    ...metadata(),
    'base64': base64Encode(bytes),
  };
  factory ActivityMedia.fromJson(Map<String, dynamic> json) {
    final encoded = json['base64'] as String;
    if (encoded.length > 6 * 1024 * 1024) {
      throw const ValidationException('El adjunto es demasiado grande.');
    }
    return ActivityMedia(
      name: json['name'] as String,
      mime: json['mime'] as String,
      bytes: base64Decode(encoded),
    );
  }
}

class ActivityMessage {
  const ActivityMessage({
    required this.id,
    required this.text,
    required this.role,
    required this.recordedAt,
    this.intervalId,
    this.metrics = const {},
    this.mediaName,
    this.mediaMime,
  });
  final String id, text, role;
  final String? intervalId;
  final DateTime recordedAt;
  final Map<String, dynamic> metrics;
  final String? mediaName, mediaMime;
  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'role': role,
    'intervalId': intervalId,
    'recordedAt': recordedAt.toIso8601String(),
    'metrics': metrics,
    'attachment':
        mediaName == null ? null : {'name': mediaName, 'mime': mediaMime},
  };
}

class FocusActivity {
  const FocusActivity({
    required this.id,
    required this.workoutId,
    required this.definition,
    required this.createdAt,
    required this.intervals,
    required this.messages,
    this.exerciseId,
    this.finishedAt,
    this.draft = '',
    this.restEndsAt,
    this.finishedRecordedAt,
    this.finishIssues = const [],
  });
  final String id, workoutId, draft;
  final String? exerciseId;
  final ActivityDefinition definition;
  final DateTime createdAt;
  final DateTime? finishedAt, restEndsAt, finishedRecordedAt;
  final List<String> finishIssues;
  final List<ActivityInterval> intervals;
  final List<ActivityMessage> messages;
  ActivityInterval? get running =>
      intervals.where((i) => i.endedAt == null).firstOrNull;
  bool get active => finishedAt == null;
  Map<String, dynamic> toJson() => {
    'id': id,
    'workoutId': workoutId,
    'definition': definition.toJson(),
    'createdAt': createdAt.toIso8601String(),
    'finishedAt': finishedAt?.toIso8601String(),
    'finishedRecordedAt': finishedRecordedAt?.toIso8601String(),
    'finishIssues': finishIssues,
    'intervals': [
      for (var index = 0; index < intervals.length; index++)
        {
          ...intervals[index].toJson(),
          'durationSeconds':
              intervals[index].endedAt != null &&
                      !intervals[index].endedAt!.isBefore(
                        intervals[index].startedAt,
                      )
                  ? intervals[index].endedAt!
                      .difference(intervals[index].startedAt)
                      .inSeconds
                  : null,
          'actualRestSeconds':
              index + 1 < intervals.length &&
                      intervals[index].endedAt != null &&
                      !intervals[index + 1].startedAt.isBefore(
                        intervals[index].endedAt!,
                      )
                  ? intervals[index + 1].startedAt
                      .difference(intervals[index].endedAt!)
                      .inSeconds
                  : null,
        },
    ],
    'messages': messages.map((m) => m.toJson()).toList(),
  };
}

/// Only a complete unambiguous strength shorthand is parsed locally. Preserve
/// everything else as original text, without forcing it into strength metrics.
Map<String, dynamic> compactStrengthMetrics(
  String text,
  ActivityDefinition definition,
) {
  if (!definition.fields.any(
        (f) => f['key'] == 'weight_kg' && f['unit'] == 'kg',
      ) ||
      !definition.fields.any((f) => f['key'] == 'reps')) {
    return {};
  }
  final match = RegExp(
    r'^\s*(\d{1,4}(?:[.,]\d{1,2})?)\s*(?:kg|k)\s*(\d{1,3})\s*r(?:eps)?(?:\s*(f|nf))?\s*$',
    caseSensitive: false,
  ).firstMatch(text);
  if (match == null) return {};
  try {
    return {
      'weight_kg': parseWeight(match[1]!) / 100,
      'reps': parseReps(match[2]!),
      if (match[3] != null &&
          definition.fields.any((f) => f['key'] == 'failure'))
        'failure': match[3]!.toLowerCase() == 'f',
    };
  } on ValidationException {
    return {};
  }
}

abstract interface class ActivityRepository {
  Future<List<FocusActivity>> loadActivities();
  Future<String> prepareActivity(
    ActivityDefinition definition, {
    String? exerciseId,
  });
  Future<void> startInterval(String activityId);
  Future<void> stopInterval(String activityId);
  Future<void> setActivityDraft(String activityId, String text);
  Future<String> recordActivityMessage(
    String activityId,
    String text, {
    String role = 'user',
    String? intervalId,
    ActivityMedia? media,
  });
  Future<void> finishActivity(
    String activityId,
    DateTime end, {
    bool acceptConflicts = false,
  });
  Future<void> setActivityRest(String activityId, int seconds);
  Future<ActivityMedia?> loadActivityMedia(String messageId);
  Future<void> cancelActivityPreparation(String activityId);
  Future<void> renameActivity(String activityId, String name);
  Future<void> replaceActivityPreparation(
    String activityId,
    ActivityDefinition definition, {
    String? exerciseId,
  });
  Future<void> resumeActivityPreparation(String activityId);
  Future<void> interpretActivityMessage(
    String messageId,
    Map<String, dynamic> metrics, {
    List<Map<String, String>> fields = const [],
  });
}
