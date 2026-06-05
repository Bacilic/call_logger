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
    final outputPath = await _settings.getOutputPath();
    final excelPath = await _settings.getExcelPath();
    return _validator.validateReadPath(
      path,
      outputPath: outputPath,
      excelPath: excelPath,
    );
  }

  /// Επανελέγχει από αποθηκευμένες ρυθμίσεις ή από overrides (π.χ. πεδία dialog).
  Future<void> refresh({
    String? pathOverride,
    String? outputPathOverride,
    String? excelPathOverride,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final readPath = pathOverride ?? await _settings.getReadPath();
      final outputPath =
          outputPathOverride ?? await _settings.getOutputPath();
      final excelPath = excelPathOverride ?? await _settings.getExcelPath();
      return _validator.validateReadPath(
        readPath,
        outputPath: outputPath,
        excelPath: excelPath,
      );
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
