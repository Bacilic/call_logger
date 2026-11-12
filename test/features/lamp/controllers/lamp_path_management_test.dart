import 'package:call_logger/core/config/app_config.dart';
import 'package:call_logger/core/database/old_database/lamp_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Οι ρυθμίσεις διαδρομής της Λάμπας μετά την κατάργηση της «Δημιουργίας
/// βάσης από Excel»: μένει μόνο η βάση που διαβάζει η Λάμπα, και κανένας
/// σταθμός δεν τη χάνει στη μετάβαση.
void main() {
  String key(String base) => AppConfig.prefixedPreferencesKey(base);

  const readKey = 'lamp_old_db_read_path';
  const outputKey = 'lamp_old_db_output_path';
  const excelKey = 'lamp_excel_path';

  test('η διαδρομή της βάσης γράφεται και διαβάζεται ίδια', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final settings = LampSettingsStore();
    await settings.setReadPath('C:/read/lamp_read.db');

    expect(await settings.getReadPath(), 'C:/read/lamp_read.db');
  });

  test('σταθμός με κενή βάση Λάμπας κρατά τη βάση που δημιουργούσε το Excel '
      'και οι ρυθμίσεις του Excel σβήνονται', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      key(outputKey): 'C:/out/lamp_out.db',
      key(excelKey): 'C:/import/lamp.xlsx',
    });

    expect(await LampSettingsStore().getReadPath(), 'C:/out/lamp_out.db');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(key(readKey)), 'C:/out/lamp_out.db');
    expect(prefs.containsKey(key(outputKey)), isFalse);
    expect(prefs.containsKey(key(excelKey)), isFalse);
  });

  test(
    'σταθμός με δική του βάση Λάμπας δεν την αλλάζει στη μετάβαση',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        key(readKey): 'C:/read/experiment.db',
        key(outputKey): 'C:/out/fresh_import.db',
      });

      expect(await LampSettingsStore().getReadPath(), 'C:/read/experiment.db');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(key(outputKey)), isFalse);
    },
  );

  test(
    'η μετάβαση γίνεται μία φορά: βάση που άδειασε αργότερα δεν ξαναγεμίζει',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        key(readKey): 'C:/read/lamp.db',
      });
      final settings = LampSettingsStore();
      await settings.getReadPath();
      await settings.setReadPath('');

      expect(await settings.getReadPath(), isNull);
    },
  );
}
