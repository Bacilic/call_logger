// Unit test: οι λογαριασμοί Lansweeper του τμήματος — ανάλυση «ετικέτα =
// αναγνωριστικό», αποθήκευση, και η ιεραρχία επιλογής αιτούντα.
//
//   flutter test test/core/services/lansweeper_department_accounts_test.dart

import 'package:call_logger/core/services/lansweeper_department_accounts.dart';
import 'package:call_logger/core/services/lansweeper_requester_resolution.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseLansweeperAccountsInput', () {
    test('ζεύγη με ετικέτα χωρισμένα με κόμμα', () {
      final accounts = parseLansweeperAccountsInput(
        r'Υπάλληλος Βιοχημικού #1 = gnk\bio1, Υπάλληλος Βιοχημικού #2 = gnk\bio2',
      );

      expect(accounts, hasLength(2));
      expect(accounts.first.label, 'Υπάλληλος Βιοχημικού #1');
      expect(accounts.first.username, r'gnk\bio1');
      expect(accounts.last.username, r'gnk\bio2');
    });

    test('σκέτο αναγνωριστικό χωρίς «=» γίνεται δεκτό', () {
      final accounts = parseLansweeperAccountsInput(r'gnk\docpaid');

      expect(accounts, hasLength(1));
      expect(accounts.single.username, r'gnk\docpaid');
      expect(accounts.single.label, isEmpty);
    });

    test('email ως αναγνωριστικό δεν μπερδεύεται με ετικέτα', () {
      final accounts = parseLansweeperAccountsInput(
        'Γραμματεία = grammateia@hospkorinthos.gr',
      );

      expect(accounts.single.username, 'grammateia@hospkorinthos.gr');
      expect(accounts.single.label, 'Γραμματεία');
    });

    test('κενά και άδεια κομμάτια αγνοούνται', () {
      final accounts = parseLansweeperAccountsInput(
        r'  ,  gnk\bio1 ,, Ετικέτα =   , ',
      );

      expect(
        accounts.map((a) => a.username),
        [r'gnk\bio1'],
        reason: 'Ζεύγος χωρίς αναγνωριστικό δεν είναι λογαριασμός',
      );
    });

    test(
      r'ξεχασμένο «=»: «Γραφείο Λοιμώξεων gnk\x» σπάει μόνο του σωστά',
      () {
        final accounts = parseLansweeperAccountsInput(
          r'Γραφείο Λοιμώξεων gnk\loimokseis1',
        );

        expect(accounts.single.username, r'gnk\loimokseis1');
        expect(accounts.single.label, 'Γραφείο Λοιμώξεων');
      },
    );

    test('ξεχασμένο «=» με email στο τέλος', () {
      final accounts = parseLansweeperAccountsInput(
        'Γραμματεία ΤΕΠ grammateia@hospkorinthos.gr',
      );

      expect(accounts.single.username, 'grammateia@hospkorinthos.gr');
      expect(accounts.single.label, 'Γραμματεία ΤΕΠ');
    });

    test('κείμενο χωρίς καμία έγκυρη ταυτότητα μένει ως έχει', () {
      final accounts = parseLansweeperAccountsInput('Γραφείο Λοιμώξεων');

      expect(
        accounts.single.username,
        'Γραφείο Λοιμώξεων',
        reason: 'Δεν μαντεύουμε — ο χρήστης θα δει προειδοποίηση',
      );
    });

    test('διπλό αναγνωριστικό κρατιέται μία φορά', () {
      final accounts = parseLansweeperAccountsInput(
        r'Πρώτος = gnk\bio1, Δεύτερος = GNK\BIO1',
      );

      expect(accounts, hasLength(1));
      expect(accounts.single.label, 'Πρώτος');
    });
  });

  group('αποθήκευση και ανάγνωση', () {
    test('κύκλος: γράφω → αποθηκεύω → διαβάζω δίνει τα ίδια', () {
      final original = parseLansweeperAccountsInput(
        r'Α = gnk\bio1, Β = gnk\bio2',
      );

      final restored = decodeLansweeperAccounts(
        encodeLansweeperAccounts(original),
      );

      expect(restored, original);
    });

    test('κενή λίστα αποθηκεύεται ως null, ώστε η στήλη να αδειάζει', () {
      expect(encodeLansweeperAccounts(const []), isNull);
    });

    test('ετικέτα με κόμμα επιβιώνει της αποθήκευσης', () {
      final original = [
        const LansweeperAccount(
          username: r'gnk\bio1',
          label: 'Βιοχημικό, πρωινή βάρδια',
        ),
      ];

      final restored = decodeLansweeperAccounts(
        encodeLansweeperAccounts(original),
      );

      expect(restored.single.label, 'Βιοχημικό, πρωινή βάρδια');
    });

    test('χαλασμένο ή παλιό απλό κείμενο διαβάζεται αντί να χαθεί', () {
      expect(decodeLansweeperAccounts(null), isEmpty);
      expect(decodeLansweeperAccounts('   '), isEmpty);
      expect(
        decodeLansweeperAccounts(r'gnk\bio1, gnk\bio2').map((a) => a.username),
        [r'gnk\bio1', r'gnk\bio2'],
      );
      expect(
        decodeLansweeperAccounts(r'[{κακό json').map((a) => a.username),
        isNotEmpty,
        reason: 'Χαλασμένο JSON δεν σβήνει τα δεδομένα του χρήστη',
      );
    });
  });

  group('lansweeperAccountsWarning — τι δεν θα βρεθεί στο Lansweeper', () {
    test('έγκυροι λογαριασμοί: καμία προειδοποίηση', () {
      final accounts = parseLansweeperAccountsInput(
        r'Α = gnk\bio1, grammateia@hospkorinthos.gr',
      );

      expect(lansweeperAccountsWarning(accounts), isNull);
    });

    test('ονομασία χωρίς αναγνωριστικό: ονομάζει τι φταίει', () {
      final accounts = parseLansweeperAccountsInput('Γραφείο Λοιμώξεων');
      final warning = lansweeperAccountsWarning(accounts);

      expect(warning, isNotNull);
      expect(warning, contains('Γραφείο Λοιμώξεων'));
    });

    test('τελεία στο τέλος του email πιάνεται', () {
      final accounts = parseLansweeperAccountsInput(
        'v.drosos@hospkorinthos.gr.',
      );

      expect(lansweeperAccountsWarning(accounts), isNotNull);
    });

    test('πολλά άκυρα: αναφέρονται όλα', () {
      final accounts = parseLansweeperAccountsInput(
        r'Πρώτο λάθος, Δεύτερο λάθος, Σωστό = gnk\bio1',
      );
      final warning = lansweeperAccountsWarning(accounts);

      expect(warning, contains('Πρώτο λάθος'));
      expect(warning, contains('Δεύτερο λάθος'));
      expect(warning, isNot(contains(r'gnk\bio1')));
    });
  });

  group('resolveLansweeperRequester — ιεραρχία', () {
    const bio1 = LansweeperAccount(username: r'gnk\bio1', label: 'Βιοχημικό #1');
    const bio2 = LansweeperAccount(username: r'gnk\bio2', label: 'Βιοχημικό #2');
    const paid = LansweeperAccount(username: r'gnk\docpaid', label: 'Παιδιατρική');

    test('ο καλών με δικό του αναγνωριστικό κερδίζει — καμία ερώτηση', () {
      final options = resolveLansweeperRequester(
        callerUsername: r'gnk\d.brami',
        departments: [(departmentName: 'Βιοχημικό', accounts: [bio1, bio2])],
      );

      expect(options.selectedUsername, r'gnk\d.brami');
      expect(options.isChoosable, isFalse);
      expect(options.candidates, isEmpty);
    });

    test('άγνωστος καλών με ΕΝΑ λογαριασμό τμήματος: μπαίνει αυτόματα', () {
      final options = resolveLansweeperRequester(
        callerUsername: null,
        departments: [(departmentName: 'Παιδιατρική', accounts: [paid])],
      );

      expect(options.selectedUsername, r'gnk\docpaid');
      expect(
        options.isChoosable,
        isFalse,
        reason: 'Με μία επιλογή δεν υπάρχει τι να διαλέξει ο χρήστης',
      );
      expect(options.candidates, hasLength(1));
    });

    test('άγνωστος καλών με ΠΟΛΛΟΥΣ: προεπιλογή ο πρώτος, με επιλογή', () {
      final options = resolveLansweeperRequester(
        callerUsername: '   ',
        departments: [(departmentName: 'Βιοχημικό', accounts: [bio1, bio2])],
      );

      expect(options.selectedUsername, r'gnk\bio1');
      expect(options.isChoosable, isTrue);
      expect(options.candidates.map((c) => c.account.username), [
        r'gnk\bio1',
        r'gnk\bio2',
      ]);
    });

    test('πολλά τμήματα: όλοι οι λογαριασμοί, με το τμήμα τους', () {
      final options = resolveLansweeperRequester(
        callerUsername: null,
        departments: [
          (departmentName: 'Βιοχημικό', accounts: [bio1]),
          (departmentName: 'Παιδιατρική', accounts: [paid]),
        ],
      );

      expect(options.isChoosable, isTrue);
      expect(options.candidates.map((c) => c.departmentName), [
        'Βιοχημικό',
        'Παιδιατρική',
      ]);
    });

    test('ίδιος λογαριασμός σε δύο τμήματα εμφανίζεται μία φορά', () {
      final options = resolveLansweeperRequester(
        callerUsername: null,
        departments: [
          (departmentName: 'Βιοχημικό', accounts: [bio1]),
          (departmentName: 'Αιματολογικό', accounts: [bio1, bio2]),
        ],
      );

      expect(options.candidates.map((c) => c.account.username), [
        r'gnk\bio1',
        r'gnk\bio2',
      ]);
      expect(options.candidates.first.departmentName, 'Βιοχημικό');
    });

    test('τίποτα πουθενά: αιτών ο πράκτορας, χωρίς επιλογέα', () {
      final options = resolveLansweeperRequester(
        callerUsername: null,
        departments: [(departmentName: 'Λοιμώξεων', accounts: const [])],
      );

      expect(options.selectedUsername, isNull);
      expect(options.isChoosable, isFalse);
      expect(options.candidates, isEmpty);
    });
  });
}
