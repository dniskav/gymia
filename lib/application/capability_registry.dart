import '../domain/workout.dart';

class CapabilityRequirement {
  const CapabilityRequirement(this.id, this.version);
  final String id;
  final int version;
}

/// Only capabilities already handled by the installed runtime belong here.
/// TrackIA plan, stage, and audio IDs are added when their adapters ship.
class CapabilityRegistry {
  CapabilityRegistry(Map<String, int> supported)
    : _supported = Map.unmodifiable(supported) {
    if (_supported.entries.any(
      (entry) =>
          !RegExp(r'^[a-z][a-z0-9-]{0,79}$').hasMatch(entry.key) ||
          entry.value < 1,
    )) {
      throw const ValidationException('Catálogo de capacidades no válido.');
    }
  }

  final Map<String, int> _supported;
  static final current = CapabilityRegistry({
    'gymia-activity': 1,
    'gymia-result': 1,
    'gymia-archive': 1,
    'gymia-recall': 1,
    'gymia-sync': 1,
    'gymia-sheet-plan': 1,
  });

  Map<String, int> get supported => _supported;

  bool supports(String id, int version) =>
      version >= 1 && (_supported[id] ?? 0) >= version;

  List<String> validate(Iterable<CapabilityRequirement> requirements) => [
    for (final requirement in requirements)
      if (!supports(requirement.id, requirement.version)) requirement.id,
  ];
}
