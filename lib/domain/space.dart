import 'workout.dart';

/// Stable IDs are keys, never display names or filesystem fragments.
String validTrackiaId(String raw) {
  // A Google subject can be 128 bytes; its base64url profile ID is longer.
  if (!RegExp(r'^[A-Za-z0-9_-]{1,256}$').hasMatch(raw)) {
    throw const ValidationException('El identificador de ámbito no es válido.');
  }
  return raw;
}

class SpaceScope {
  SpaceScope({required String profileId, required String spaceId})
    : profileId = validTrackiaId(profileId),
      spaceId = validTrackiaId(spaceId);

  final String profileId;
  final String spaceId;

  @override
  bool operator ==(Object other) =>
      other is SpaceScope &&
      profileId == other.profileId &&
      spaceId == other.spaceId;

  @override
  int get hashCode => Object.hash(profileId, spaceId);
}

class TrackiaSpace {
  TrackiaSpace({
    required String id,
    required String profileId,
    required String name,
    this.revision = 1,
  }) : id = validTrackiaId(id),
       profileId = validTrackiaId(profileId),
       name = validName(name) {
    if (revision < 1) {
      throw const ValidationException('La revisión debe ser positiva.');
    }
  }

  final String id;
  final String profileId;
  final String name;
  final int revision;
  SpaceScope get scope => SpaceScope(profileId: profileId, spaceId: id);

  void requireScope(SpaceScope requested) {
    if (requested != scope) {
      throw const ValidationException('El espacio pertenece a otro ámbito.');
    }
  }

  TrackiaSpace rename(String nextName) => TrackiaSpace(
    id: id,
    profileId: profileId,
    name: nextName,
    revision: revision + 1,
  );
}
