// Αποθηκευμένος λογαριασμός τμήματος γραμμένος ΧΩΡΙΣ «=»: το αναγνωριστικό
// είχε καταλήξει να περιέχει ολόκληρη τη φράση («Γιατρός Τεπ Παθολογικού 1
// gnk\TepPath1»), οπότε το Lansweeper δεν έβρισκε χρήστη και το αίτημα έφευγε
// χωρίς αιτούντα. Η επιδιόρθωση του «ξεχασμένου ίσον» έτρεχε μόνο την ώρα της
// πληκτρολόγησης — ό,τι είχε ήδη αποθηκευτεί έμενε σπασμένο για πάντα.
//
//   flutter test test/core/services/lansweeper_stored_account_repair_test.dart

import 'package:call_logger/core/services/lansweeper_department_accounts.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ό,τι βρέθηκε αποθηκευμένο στο τμήμα «ΤΕΠ Παθολογικής» (12/08/2026).
const _storedBroken =
    '[{"username":"Γιατρός Τεπ Παθολογικού 1 gnk\\\\TepPath1"},'
    '{"username":"Γιατρός Τεπ Παθολογικού2 gnk\\\\TepPath2"}]';

/// Το ίδιο τμήμα όπως θα γραφόταν σωστά.
const _storedHealthy =
    '[{"username":"gnk\\\\bio1","label":"Υπάλληλος Βιοχημικού 1"}]';

void main() {
  test('αποθηκευμένο ζεύγος χωρίς «=» καθαρίζεται στην ανάγνωση', () {
    final accounts = decodeLansweeperAccounts(_storedBroken);

    expect(accounts, hasLength(2));
    expect(accounts[0].username, r'gnk\TepPath1');
    expect(accounts[0].label, 'Γιατρός Τεπ Παθολογικού 1');
    expect(accounts[1].username, r'gnk\TepPath2');
    expect(accounts[1].label, 'Γιατρός Τεπ Παθολογικού2');
  });

  test('το αναγνωριστικό που φεύγει δεν περιέχει ποτέ κενά', () {
    for (final account in decodeLansweeperAccounts(_storedBroken)) {
      expect(
        account.username.contains(' '),
        isFalse,
        reason:
            'κενό μέσα στο αναγνωριστικό σημαίνει ότι το Lansweeper δεν θα '
            'βρει χρήστη και το ticket θα φύγει χωρίς αιτούντα',
      );
    }
  });

  test('σωστά αποθηκευμένο ζεύγος μένει ανέγγιχτο', () {
    final accounts = decodeLansweeperAccounts(_storedHealthy);

    expect(accounts, hasLength(1));
    expect(accounts.single.username, r'gnk\bio1');
    expect(accounts.single.label, 'Υπάλληλος Βιοχημικού 1');
  });

  test('αναγνωριστικό χωρίς κενά δεν σπάει σε κομμάτια', () {
    final accounts = decodeLansweeperAccounts(
      '[{"username":"gnk\\\\loimokseis1","label":"Γραφείο Λοιμώξεων"}]',
    );

    expect(accounts.single.username, r'gnk\loimokseis1');
    expect(accounts.single.label, 'Γραφείο Λοιμώξεων');
  });

  test('φράση χωρίς τίποτα που να μοιάζει με λογαριασμό μένει ως έχει', () {
    final accounts = decodeLansweeperAccounts(
      '[{"username":"Γραφείο Λοιμώξεων"}]',
    );

    expect(
      accounts.single.username,
      'Γραφείο Λοιμώξεων',
      reason: 'δεν μαντεύουμε — ο χρήστης βλέπει προειδοποίηση',
    );
  });

  test('η ανάγνωση είναι σταθερή: δεύτερο πέρασμα δεν αλλάζει τίποτα', () {
    final once = decodeLansweeperAccounts(_storedBroken);
    final twice = decodeLansweeperAccounts(
      encodeLansweeperAccounts(once) ?? '',
    );

    expect(twice, once);
  });
}
