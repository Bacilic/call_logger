import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/old_database/lamp_db_comparison.dart';
import '../database/old_database/lamp_settings_store.dart';
import '../database/old_database/old_equipment_repository.dart';

/// Ουδέτερες ειδοποιήσεις σύγκρισης βάσης ανάγνωσης έναντι εξόδου (Λάμπα).
class LampDbComparisonNotifier extends AsyncNotifier<List<String>> {
  static final LampSettingsStore _settings = LampSettingsStore();
  static final OldEquipmentRepository _repository = OldEquipmentRepository();

  @override
  Future<List<String>> build() async {
    return _compute();
  }

  Future<void> refresh({
    String? readPathOverride,
    String? outputPathOverride,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => _compute(
        readPathOverride: readPathOverride,
        outputPathOverride: outputPathOverride,
      ),
    );
  }

  Future<List<String>> _compute({
    String? readPathOverride,
    String? outputPathOverride,
  }) async {
    final readPath =
        readPathOverride ?? (await _settings.getReadPathRaw()) ?? '';
    final outputPath =
        outputPathOverride ?? (await _settings.getOutputPathRaw()) ?? '';
    if (readPath.trim().isEmpty && outputPath.trim().isEmpty) {
      return const <String>[];
    }

    final readSnapshot = await _repository.collectDbSnapshot(readPath);
    final outputSnapshot = await _repository.collectDbSnapshot(outputPath);
    return buildLampDbComparisonNotifications(
      read: readSnapshot,
      output: outputSnapshot,
      readPath: readPath,
      outputPath: outputPath,
    );
  }
}

final lampDbComparisonProvider =
    AsyncNotifierProvider<LampDbComparisonNotifier, List<String>>(
  LampDbComparisonNotifier.new,
);
