import 'package:call_logger/core/database/old_database/lamp_old_db_validator.dart';
import 'package:call_logger/core/database/old_database/lamp_settings_store.dart';
import 'package:call_logger/features/lamp/controllers/lamp_path_management.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('computeMatchReadToOutputButtonState', () {
    test('disabled when output path is empty', () {
      final state = computeMatchReadToOutputButtonState(
        outputPath: '',
        readPath: r'C:\read.db',
      );
      expect(state.enabled, isFalse);
      expect(state.tooltip, 'Η διαδρομή της βάσης εξόδου είναι κενή');
    });

    test('disabled when paths already match', () {
      final state = computeMatchReadToOutputButtonState(
        outputPath: r'C:\Data\lamp.db',
        readPath: r'c:\data\lamp.db',
      );
      expect(state.enabled, isFalse);
      expect(
        state.tooltip,
        'Η διαδρομή της βάσης εξόδου είναι ίδια με τη βάση ανάγνωσης',
      );
    });

    test('disabled when output path format is invalid', () {
      final state = computeMatchReadToOutputButtonState(
        outputPath: r'C:\Data\old_base_test',
        readPath: r'C:\Data\read.db',
      );
      expect(state.enabled, isFalse);
      expect(
        state.tooltip,
        'Η διαδρομή της βάσης εξόδου δεν είναι έγκυρη (αρχείο .db)',
      );
    });

    test('enabled when output is valid and differs from read', () {
      final state = computeMatchReadToOutputButtonState(
        outputPath: r'C:\Data\output.db',
        readPath: r'C:\Data\read.db',
      );
      expect(state.enabled, isTrue);
      expect(state.tooltip, 'Ίδια διαδρομή με τη βάση εξόδου');
    });
  });

  group('LampPathController path persistence contract', () {
    test('settings store round-trips typed read and output paths', () async {
      final settings = LampSettingsStore();
      await settings.setReadPath(r'C:\read\lamp_read.db');
      await settings.setOutputPath(r'C:\out\lamp_out.db');

      expect(await settings.getReadPathRaw(), r'C:\read\lamp_read.db');
      expect(await settings.getOutputPathRaw(), r'C:\out\lamp_out.db');
    });

    test('effective read path falls back to output when read is empty', () {
      final output = r'C:\out\lamp_out.db';
      expect(
        LampOldDbValidator.pathsReferToSameFile('', output),
        isFalse,
      );
      expect(
        LampOldDbValidator.pathsReferToSameFile(output, output),
        isTrue,
      );
    });
  });
}
