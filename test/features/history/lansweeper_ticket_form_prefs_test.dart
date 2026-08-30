// Οι επιλογές φόρμας ticket ανήκουν στον χρήστη που τις έκανε.
//
// Ως τώρα γράφονταν στην κοινή θέση, ενώ το κλειδί είναι δηλωμένο προσωπικό:
// δύο συνάδελφοι με ενεργή τη «διατήρηση επιλογών» έβλεπαν ο ένας τα πεδία
// του άλλου — όποιος έστειλε τελευταίος.
//
//   flutter test test/features/history/lansweeper_ticket_form_prefs_test.dart

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/operator_repository.dart';
import 'package:call_logger/core/models/operator.dart';
import 'package:call_logger/core/services/current_operator.dart';
import 'package:call_logger/features/history/services/lansweeper_ticket_form_prefs.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_setup.dart';

Future<void> _signIn(String name) async {
  final db = await DatabaseHelper.instance.database;
  final saved = await OperatorRepository(
    db,
  ).insert(Operator(displayName: name, createdAt: DateTime(2026, 8, 30)));
  CurrentOperator.activate(saved);
}

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  setUp(() async {
    CurrentOperator.reset();
    final db = await DatabaseHelper.instance.database;
    await db.delete(
      'app_settings',
      where: 'key LIKE ?',
      whereArgs: ['lansweeper_%'],
    );
  });
  tearDown(CurrentOperator.reset);

  group('αποθήκευση και επαναφορά', () {
    test('ο κάθε χρήστης βρίσκει ΤΙΣ ΔΙΚΕΣ ΤΟΥ επιλογές', () async {
      await _signIn('Βασίλης');
      await const LansweeperTicketFormPrefs(
        customFieldValues: {'Κτίριο': 'Α πτέρυγα'},
        ticketState: 'Σε εξέλιξη',
      ).save();

      await _signIn('Συνάδελφος');
      expect(
        await LansweeperTicketFormPrefs.load(),
        isNull,
        reason: 'ο δεύτερος δεν κληρονομεί τις επιλογές του πρώτου',
      );

      await const LansweeperTicketFormPrefs(
        customFieldValues: {'Κτίριο': 'Β πτέρυγα'},
        ticketState: 'Νέο',
      ).save();

      final second = await LansweeperTicketFormPrefs.load();
      expect(second!.customFieldValues['Κτίριο'], 'Β πτέρυγα');
      expect(second.ticketState, 'Νέο');
    });

    test('η αποθήκευση του ενός δεν αλλάζει τον άλλον', () async {
      await _signIn('Βασίλης');
      await const LansweeperTicketFormPrefs(
        customFieldValues: {'Κτίριο': 'Α πτέρυγα'},
        ticketState: 'Σε εξέλιξη',
      ).save();
      final mine = await LansweeperTicketFormPrefs.load();

      await _signIn('Συνάδελφος');
      await const LansweeperTicketFormPrefs(
        customFieldValues: {'Κτίριο': 'Β πτέρυγα'},
        ticketState: 'Νέο',
      ).save();

      expect(mine!.customFieldValues['Κτίριο'], 'Α πτέρυγα');
    });
  });

  group('ανάγνωση αποθηκευμένου κειμένου', () {
    test('χαλασμένο περιεχόμενο δεν ρίχνει τη φόρμα', () {
      expect(LansweeperTicketFormPrefs.decode('{όχι json'), isNull);
      expect(LansweeperTicketFormPrefs.decode('[1,2,3]'), isNull);
      expect(LansweeperTicketFormPrefs.decode(''), isNull);
      expect(LansweeperTicketFormPrefs.decode(null), isNull);
    });

    test('κενή κατάσταση ticket διαβάζεται ως «καμία»', () {
      final prefs = LansweeperTicketFormPrefs.decode(
        '{"customFieldValues":{"Κτίριο":"Α"},"ticketState":"   "}',
      );
      expect(prefs!.ticketState, isNull);
      expect(prefs.customFieldValues['Κτίριο'], 'Α');
    });

    test('ό,τι γράφεται, διαβάζεται ίδιο', () {
      const original = LansweeperTicketFormPrefs(
        customFieldValues: {'Κτίριο': 'Α πτέρυγα', 'Όροφος': '2'},
        ticketState: 'Νέο',
      );
      final restored = LansweeperTicketFormPrefs.decode(original.encode());
      expect(restored!.customFieldValues, original.customFieldValues);
      expect(restored.ticketState, original.ticketState);
    });
  });
}
