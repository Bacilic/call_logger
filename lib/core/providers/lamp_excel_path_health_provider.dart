import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/old_database/lamp_excel_validator.dart';
import '../database/old_database/lamp_settings_store.dart';

/// Έλεγχος διαδρομής Excel (πηγή εισαγωγής Λάμπας).
class LampExcelPathHealthNotifier extends AsyncNotifier<LampExcelCheckResult?> {
  static final LampSettingsStore _settings = LampSettingsStore();
  static const LampExcelValidator _validator = LampExcelValidator();

  @override
  Future<LampExcelCheckResult?> build() async {
    final path = await _settings.getExcelPath();
    return _validator.validateExcelSource(path);
  }

  /// Επανελέγχει από αποθηκευμένες ρυθμίσεις ή από override (π.χ. πεδίο dialog).
  Future<void> refresh({String? pathOverride}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final excelPath = pathOverride ?? await _settings.getExcelPath();
      return _validator.validateExcelSource(excelPath);
    });
  }
}

final lampExcelPathHealthProvider =
    AsyncNotifierProvider<LampExcelPathHealthNotifier, LampExcelCheckResult?>(
  LampExcelPathHealthNotifier.new,
);
