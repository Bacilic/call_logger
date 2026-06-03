import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/old_database/lamp_old_db_validator.dart';
import '../database/old_database/lamp_settings_store.dart';

/// True όταν η βάση προς ανάγνωση δεν είναι έτοιμη (badge στο rail, banner αναζήτησης).
bool lampReadPathNeedsAttention(LampOldDbCheckResult? result) {
  if (result == null) return false;
  return result.status != LampOldDbStatus.ok;
}

/// Έλεγχος διαδρομής .db προς ανάγνωση (Λάμπα) — κοινή πηγή για rail, banner και guards.
class LampReadPathHealthNotifier extends AsyncNotifier<LampOldDbCheckResult?> {
  static final LampSettingsStore _settings = LampSettingsStore();
  static final LampOldDbValidator _validator = LampOldDbValidator();

  @override
  Future<LampOldDbCheckResult?> build() async {
    final path = await _settings.getReadPath();
    return _validator.validateReadPath(path);
  }

  /// Επανελέγχει από αποθηκευμένες ρυθμίσεις ή από [pathOverride] (π.χ. μετά επικόλληση στο dialog).
  Future<void> refresh({String? pathOverride}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final path = pathOverride ?? await _settings.getReadPath();
      return _validator.validateReadPath(path);
    });
  }
}

final lampReadPathHealthProvider =
    AsyncNotifierProvider<LampReadPathHealthNotifier, LampOldDbCheckResult?>(
  LampReadPathHealthNotifier.new,
);

final lampShowNavWarningProvider = Provider<bool>((ref) {
  final async = ref.watch(lampReadPathHealthProvider);
  return lampReadPathNeedsAttention(async.value);
});
