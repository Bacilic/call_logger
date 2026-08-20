// Φάση 3 — Κοινή τιμή με παράκαμψη: το τρίτο στρώμα εμβέλειας.
//
// Το κρίσιμο συμβόλαιο: «δεν έχω δική μου τιμή» ΔΕΝ είναι το ίδιο με «έχω
// δική μου και είναι επίτηδες κενή». Χωρίς τη διάκριση, όποιος αδειάσει την
// παράκαμψή του κολλάει σε κενή τιμή χωρίς δρόμο επιστροφής στην κοινή.
//
//   flutter test test/core/services/overridable_settings_test.dart

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/operator_settings_repository.dart';
import 'package:call_logger/core/models/operator.dart';
import 'package:call_logger/core/services/current_operator.dart';
import 'package:call_logger/core/services/overridable_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_setup.dart';

Operator _operator(int id) => Operator(
  id: id,
  displayName: 'Χρήστης $id',
  createdAt: DateTime(2026, 8, 20),
);

const _machineKey = OverridableSettingKeys.remoteToolExecutablePath;
const _profileKey = OverridableSettingKeys.geminiApiKey;

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    CurrentOperator.reset();
    final db = await DatabaseHelper.instance.database;
    await db.delete(OperatorSettingsRepository.tableName);
  });

  tearDown(CurrentOperator.reset);

  group('Η αλυσίδα — παράκαμψη πρώτα, κοινή μετά', () {
    test('χωρίς παράκαμψη ισχύει η κοινή τιμή', () async {
      expect(
        await OverridableSettings.resolve(_machineKey, shared: 'κοινή'),
        'κοινή',
      );
      expect(await OverridableSettings.hasOverride(_machineKey), isFalse);
    });

    test('με παράκαμψη ισχύει η παράκαμψη', () async {
      await OverridableSettings.setOverride(_machineKey, 'δική μου');
      expect(
        await OverridableSettings.resolve(_machineKey, shared: 'κοινή'),
        'δική μου',
      );
    });

    test('η αλλαγή της κοινής δεν αγγίζει όποιον έχει παράκαμψη', () async {
      await OverridableSettings.setOverride(_machineKey, 'δική μου');
      expect(
        await OverridableSettings.resolve(_machineKey, shared: 'άλλαξε'),
        'δική μου',
      );
    });
  });

  group('«Δεν έχω» ΔΕΝ είναι «έχω κενή»', () {
    test('κενή παράκαμψη είναι δηλωμένη και κερδίζει την κοινή', () async {
      await OverridableSettings.setOverride(_machineKey, '');

      expect(await OverridableSettings.hasOverride(_machineKey), isTrue);
      expect(
        await OverridableSettings.resolve(_machineKey, shared: 'κοινή'),
        isEmpty,
        reason:
            '«Επίτηδες κενή» σημαίνει «κανένα πρόγραμμα εδώ» — δεν πέφτουμε '
            'πίσω στην κοινή.',
      );
    });

    test('«Χρήση της κοινής» επαναφέρει τον δρόμο επιστροφής', () async {
      await OverridableSettings.setOverride(_machineKey, '');
      await OverridableSettings.clearOverride(_machineKey);

      expect(await OverridableSettings.hasOverride(_machineKey), isFalse);
      expect(
        await OverridableSettings.resolve(_machineKey, shared: 'κοινή'),
        'κοινή',
        reason: 'Χωρίς αυτό, ο χρήστης θα κολλούσε για πάντα στην κενή τιμή.',
      );
    });
  });

  group('Εμβέλεια ΥΠΟΛΟΓΙΣΤΗ', () {
    test('δεν χρειάζεται συνδεδεμένο χρήστη', () async {
      CurrentOperator.reset();
      await OverridableSettings.setOverride(_machineKey, r'D:\tool.exe');
      expect(await OverridableSettings.overrideOf(_machineKey), r'D:\tool.exe');
    });

    test('είναι ίδια για όλους όσοι κάθονται εδώ', () async {
      CurrentOperator.activate(_operator(1));
      await OverridableSettings.setOverride(_machineKey, r'D:\tool.exe');

      CurrentOperator.activate(_operator(2));
      expect(
        await OverridableSettings.overrideOf(_machineKey),
        r'D:\tool.exe',
        reason: 'Η διαδρομή ανήκει στο μηχάνημα, όχι στο πρόσωπο.',
      );
    });
  });

  group('Εμβέλεια ΠΡΟΦΙΛ', () {
    test('ακολουθεί τον χρήστη, όχι το μηχάνημα', () async {
      CurrentOperator.activate(_operator(1));
      await OverridableSettings.setOverride(_profileKey, 'κλειδί-του-πρώτου');

      CurrentOperator.activate(_operator(2));
      expect(
        await OverridableSettings.resolve(_profileKey, shared: 'κοινό'),
        'κοινό',
        reason: 'Ο δεύτερος δεν έχει δικό του — ισχύει το κοινό.',
      );

      CurrentOperator.activate(_operator(1));
      expect(
        await OverridableSettings.resolve(_profileKey, shared: 'κοινό'),
        'κλειδί-του-πρώτου',
      );
    });

    test('χωρίς συνδεδεμένο χρήστη ισχύει πάντα η κοινή', () async {
      CurrentOperator.reset();
      await OverridableSettings.setOverride(_profileKey, 'δεν θα γραφτεί');
      expect(
        await OverridableSettings.resolve(_profileKey, shared: 'κοινό'),
        'κοινό',
      );
    });
  });

  group('Παράκαμψη ανά οντότητα', () {
    test('κάθε εργαλείο έχει τη δική του διαδρομή', () async {
      await OverridableSettings.setOverride(
        _machineKey.forId(7),
        r'D:\anydesk.exe',
      );

      expect(
        await OverridableSettings.resolve(
          _machineKey.forId(7),
          shared: 'κοινή',
        ),
        r'D:\anydesk.exe',
      );
      expect(
        await OverridableSettings.resolve(
          _machineKey.forId(8),
          shared: 'κοινή',
        ),
        'κοινή',
        reason: 'Η παράκαμψη ενός εργαλείου δεν διαρρέει στα άλλα.',
      );
    });
  });

  group('Ο κατάλογος', () {
    test('δεν έχει διπλά κλειδιά', () {
      final keys = OverridableSettingKeys.all.map((k) => k.key).toList();
      expect(keys.toSet(), hasLength(keys.length));
    });

    test('τα κλειδιά παράκαμψης δεν συγκρούονται με τα κοινά', () {
      // Η παράκαμψη ζει σε ΔΙΚΟ ΤΗΣ κλειδί: αν χρησιμοποιούσε το ίδιο όνομα
      // με την κοινή τιμή, η μία θα έγραφε πάνω στην άλλη.
      for (final key in OverridableSettingKeys.all) {
        expect(key.key, endsWith('_override'), reason: key.key);
      }
    });
  });
}
