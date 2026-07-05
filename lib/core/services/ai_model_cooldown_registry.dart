/// In-memory καταγραφή cooldown ανά μοντέλο ΤΝ (δεν αποθηκεύεται στη βάση).
class AiModelCooldownRegistry {
  AiModelCooldownRegistry({DateTime Function()? now})
      : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final Map<String, DateTime> _availableAtByModel = {};

  void markUnavailable(String model, Duration retryAfter) {
    final id = model.trim();
    if (id.isEmpty || retryAfter <= Duration.zero) return;
    final availableAt = _now().add(retryAfter);
    final existing = _availableAtByModel[id];
    if (existing == null || availableAt.isAfter(existing)) {
      _availableAtByModel[id] = availableAt;
    }
  }

  DateTime? availableAt(String model) {
    final id = model.trim();
    if (id.isEmpty) return null;
    final at = _availableAtByModel[id];
    if (at == null) return null;
    if (!_now().isBefore(at)) {
      _availableAtByModel.remove(id);
      return null;
    }
    return at;
  }

  bool isInCooldown(String model) => availableAt(model) != null;

  ({String model, DateTime availableAt})? earliestAvailable(
    Iterable<String> models,
  ) {
    final now = _now();
    ({String model, DateTime availableAt})? best;
    for (final raw in models) {
      final id = raw.trim();
      if (id.isEmpty) continue;
      final at = _availableAtByModel[id];
      if (at == null || !now.isBefore(at)) continue;
      if (best == null || at.isBefore(best.availableAt)) {
        best = (model: id, availableAt: at);
      }
    }
    return best;
  }
}
