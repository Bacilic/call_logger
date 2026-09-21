// Ποιος χρησιμοποιεί την εφαρμογή: αναγνώριση από τον λογαριασμό Windows και η
// σφραγίδα που αφήνει στο Ιστορικό.
//
//   flutter test test/core/services/operator_identity_test.dart

import 'package:call_logger/core/database/audit_service.dart';
import 'package:call_logger/core/database/database_schema_migrations.dart';
import 'package:call_logger/core/database/database_v1_schema.dart';
import 'package:call_logger/core/database/operator_repository.dart';
import 'package:call_logger/core/models/operator.dart';
import 'package:call_logger/core/services/current_operator.dart';
import 'package:call_logger/core/services/operator_identity.dart';
import 'package:call_logger/core/services/workstation_operators.dart';
import 'package:call_logger/features/operators/services/selectable_profiles.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  group('Αναγνώριση χρήστη από τον λογαριασμό Windows', () {
    late Database db;
    late OperatorRepository repository;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      // Η μνήμη του σταθμού ζει στις τοπικές ρυθμίσεις: κάθε τεστ ξεκινά με
      // άδεια, αλλιώς η επιλογή του ενός θα ήταν η αφετηρία του επόμενου.
      SharedPreferences.setMockInitialValues(<String, Object>{});
      initSqfliteFfiForTests();
      db = await openDatabase(inMemoryDatabasePath, singleInstance: false);
      await onDatabaseUpgradeSquashed(db, 46, 47);
      // Το Ιστορικό υπάρχει από πολύ πριν την v47: κάθε αλλαγή προφίλ γράφει
      // εκεί, οπότε βάση χωρίς αυτόν τον πίνακα δεν αντιστοιχεί σε τίποτα
      // πραγματικό.
      await db.execute(kCreateAuditLogTable);
      repository = OperatorRepository(db);
      CurrentOperator.reset();
    });

    tearDown(() async {
      CurrentOperator.reset();
      await db.close();
    });

    test('άγνωστος λογαριασμός ΔΕΝ δημιουργεί προφίλ σιωπηλά', () async {
      // Σε κοινόχρηστο λογαριασμό Windows η αυτόματη δημιουργία θα χρέωνε τις
      // ενέργειες όλων σε ένα πρόσωπο. Αποφασίζει ο άνθρωπος.
      final resolved = await OperatorIdentity.resolveAndActivate(
        db,
        windowsAccount: 'VDrosos',
      );

      expect(resolved, isNull);
      expect(CurrentOperator.active, isNull);
      expect(await repository.count(), 0);
    });

    test('γνωστός λογαριασμός αναγνωρίζεται χωρίς ερώτηση', () async {
      final created = await OperatorIdentity.createAndActivate(
        db,
        displayName: 'Βασίλης',
        bindCurrentAccount: true,
        windowsAccount: 'VDrosos',
        now: DateTime(2026, 8, 20),
      );
      CurrentOperator.reset();

      final resolved = await OperatorIdentity.resolveAndActivate(
        db,
        windowsAccount: 'vdrosos',
        workstationNames: const <String>[],
      );

      expect(resolved!.id, created.id);
      expect(CurrentOperator.active?.id, created.id);
      expect(await repository.count(), 1);
    });

    test(
      'απενεργοποιημένο προφίλ δεν αναγνωρίζεται από τον λογαριασμό',
      () async {
        // Ο Παναγιώτης αποχώρησε και το προφίλ του απενεργοποιήθηκε. Στον δικό του
        // υπολογιστή, όπου ο λογαριασμός Windows ήταν δεμένος, η εφαρμογή δεν
        // επιτρέπεται να τον ξαναδώσει ως ταυτότητα: οι κλήσεις της ημέρας θα
        // γράφονταν στο όνομα ανθρώπου που έχει φύγει.
        await repository.insert(
          Operator(
            displayName: 'Παναγιώτης',
            windowsAccount: 'panagiotis',
            isActive: false,
            createdAt: DateTime(2026, 8, 20),
          ),
        );

        final resolved = await OperatorIdentity.resolveAndActivate(
          db,
          windowsAccount: 'panagiotis',
          workstationNames: const <String>[],
        );

        expect(resolved, isNull);
        expect(CurrentOperator.active, isNull);
      },
    );

    test('η γραφή του λογαριασμού δεν φτιάχνει δεύτερο πρόσωπο', () async {
      // Τα Windows δεν ξεχωρίζουν πεζά από κεφαλαία στα ονόματα λογαριασμών.
      await OperatorIdentity.createAndActivate(
        db,
        displayName: 'Βασίλης',
        bindCurrentAccount: true,
        windowsAccount: 'VDrosos',
        now: DateTime(2026, 8, 20),
      );

      expect(
        (await OperatorIdentity.resolveAndActivate(
          db,
          windowsAccount: 'ΝΟΣΟΚΟΜΕΙΟ\\VDROSOS',
          workstationNames: const <String>[],
        ))?.displayName,
        'Βασίλης',
      );
      expect(await repository.count(), 1);
    });

    test('χωρίς λογαριασμό δεν αναγνωρίζεται κανείς', () async {
      final resolved = await OperatorIdentity.resolveAndActivate(
        db,
        windowsAccount: '   ',
      );

      expect(resolved, isNull);
      expect(CurrentOperator.active, isNull);
    });

    test('η αναγνώριση μηδενίζει πρώτα τον προηγούμενο χρήστη', () async {
      // Μετά από αλλαγή βάσης τα προφίλ είναι άλλα: ο χρήστης της προηγούμενης
      // δεν επιτρέπεται να μείνει ενεργός.
      await OperatorIdentity.createAndActivate(
        db,
        displayName: 'Βασίλης',
        bindCurrentAccount: true,
        windowsAccount: 'vdrosos',
        now: DateTime(2026, 8, 20),
      );
      expect(CurrentOperator.active, isNotNull);

      await OperatorIdentity.resolveAndActivate(
        db,
        windowsAccount: '',
        workstationNames: const <String>[],
      );

      expect(CurrentOperator.active, isNull);
    });
  });

  group('Δημιουργία προφίλ από την οθόνη επιλογής', () {
    late Database db;
    late OperatorRepository repository;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      // Η μνήμη του σταθμού ζει στις τοπικές ρυθμίσεις: κάθε τεστ ξεκινά με
      // άδεια, αλλιώς η επιλογή του ενός θα ήταν η αφετηρία του επόμενου.
      SharedPreferences.setMockInitialValues(<String, Object>{});
      initSqfliteFfiForTests();
      db = await openDatabase(inMemoryDatabasePath, singleInstance: false);
      await onDatabaseUpgradeSquashed(db, 46, 47);
      // Το Ιστορικό υπάρχει από πολύ πριν την v47: κάθε αλλαγή προφίλ γράφει
      // εκεί, οπότε βάση χωρίς αυτόν τον πίνακα δεν αντιστοιχεί σε τίποτα
      // πραγματικό.
      await db.execute(kCreateAuditLogTable);
      repository = OperatorRepository(db);
      CurrentOperator.reset();
    });

    tearDown(() async {
      CurrentOperator.reset();
      await db.close();
    });

    test('με δέσιμο: η επόμενη εκκίνηση δεν ξαναρωτά', () async {
      await OperatorIdentity.createAndActivate(
        db,
        displayName: 'Βασίλης Δρόσος',
        bindCurrentAccount: true,
        windowsAccount: 'v.drosos',
        now: DateTime(2026, 8, 20),
      );
      CurrentOperator.reset();

      final resolved = await OperatorIdentity.resolveAndActivate(
        db,
        windowsAccount: 'v.drosos',
        workstationNames: const <String>[],
      );

      expect(resolved?.displayName, 'Βασίλης Δρόσος');
    });

    test('χωρίς δέσιμο: κοινόχρηστος υπολογιστής ξαναρωτά', () async {
      // Αλλιώς όλοι όσοι μοιράζονται τον λογαριασμό θα έμπαιναν ως ο πρώτος.
      await OperatorIdentity.createAndActivate(
        db,
        displayName: 'Γραφείο ΤΕΠ',
        bindCurrentAccount: false,
        windowsAccount: 'koino',
        now: DateTime(2026, 8, 20),
      );
      CurrentOperator.reset();

      expect(
        await OperatorIdentity.resolveAndActivate(
          db,
          windowsAccount: 'koino',
          workstationNames: const <String>[],
        ),
        isNull,
      );
      expect((await repository.getAll()).single.windowsAccount, isNull);
    });

    test('ο πρώτος που στήνει τη βάση σημειώνεται διαχειριστής', () async {
      final first = await OperatorIdentity.createAndActivate(
        db,
        displayName: 'Πρώτος',
        bindCurrentAccount: false,
        now: DateTime(2026, 8, 20),
      );
      final second = await OperatorIdentity.createAndActivate(
        db,
        displayName: 'Δεύτερος',
        bindCurrentAccount: false,
        now: DateTime(2026, 8, 20),
      );

      expect(first.isAdmin, isTrue);
      expect(second.isAdmin, isFalse);
    });

    test(
      'σε βάση με μόνο απενεργοποιημένα ο νέος γίνεται διαχειριστής',
      () async {
        // Δεν υπάρχει κανείς να ρωτηθεί «ποιος είναι ο διαχειριστής;»: όποιος
        // συστήνεται τώρα είναι η μόνη διέξοδος από το κλείδωμα.
        await repository.insert(
          Operator(
            displayName: 'Παναγιώτης',
            isAdmin: true,
            isActive: false,
            createdAt: DateTime(2026, 8, 20),
          ),
        );

        final created = await OperatorIdentity.createAndActivate(
          db,
          displayName: 'Βαρβάρα',
          bindCurrentAccount: false,
          now: DateTime(2026, 8, 26),
        );

        expect(created.isAdmin, isTrue);
      },
    );

    test('με ενεργά προφίλ ο νέος ΔΕΝ γίνεται σιωπηλά διαχειριστής', () async {
      // Εδώ υπάρχει ποιον να ρωτήσεις — τη σήμανση την αναλαμβάνει η ρητή
      // ερώτηση στο άνοιγμα, όχι μια σιωπηλή προαγωγή.
      await repository.insert(
        Operator(displayName: 'Παναγιώτης', createdAt: DateTime(2026, 8, 20)),
      );

      final created = await OperatorIdentity.createAndActivate(
        db,
        displayName: 'Βαρβάρα',
        bindCurrentAccount: false,
        now: DateTime(2026, 8, 26),
      );

      expect(created.isAdmin, isFalse);
    });

    test('η λίστα επιλογής κρύβει τους απενεργοποιημένους', () async {
      await repository.insert(
        Operator(displayName: 'Ενεργός', createdAt: DateTime(2026, 8, 20)),
      );
      await repository.insert(
        Operator(
          displayName: 'Απενεργοποιημένος',
          isActive: false,
          createdAt: DateTime(2026, 8, 20),
        ),
      );

      final selectable = await OperatorIdentity.selectableProfiles(db);

      expect(selectable.map((o) => o.displayName), ['Ενεργός']);
    });

    test('ο ήδη συνδεδεμένος δεν προσφέρεται προς επιλογή', () async {
      final me = await repository.insert(
        Operator(displayName: 'Βασίλης', createdAt: DateTime(2026, 8, 21)),
      );
      await repository.insert(
        Operator(displayName: 'Δοκιμαστικός', createdAt: DateTime(2026, 8, 21)),
      );
      CurrentOperator.activate(me);

      final selectable = await OperatorIdentity.selectableProfiles(db);

      expect(
        selectable.map((o) => o.displayName),
        ['Δοκιμαστικός'],
        reason:
            '«Αλλαγή χρήστη» σε αυτόν που είναι ήδη ο χρήστης δεν κάνει τίποτα',
      );
    });

    test('στην εκκίνηση, χωρίς συνδεδεμένο, προσφέρονται όλοι', () async {
      await repository.insert(
        Operator(displayName: 'Βασίλης', createdAt: DateTime(2026, 8, 21)),
      );
      await repository.insert(
        Operator(displayName: 'Δοκιμαστικός', createdAt: DateTime(2026, 8, 21)),
      );

      final selectable = await OperatorIdentity.selectableProfiles(db);

      expect(selectable, hasLength(2));
    });
  });

  group('Η επιστροφή από άδεια — ο λογαριασμός Windows διαψεύδει τη μνήμη', () {
    late Database db;
    late OperatorRepository repository;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues(<String, Object>{});
      initSqfliteFfiForTests();
      db = await openDatabase(inMemoryDatabasePath, singleInstance: false);
      await onDatabaseUpgradeSquashed(db, 46, 47);
      await db.execute(kCreateAuditLogTable);
      repository = OperatorRepository(db);
      CurrentOperator.reset();

      // Ο υπολογιστής του Βλάση: το προφίλ του είναι δεμένο στον λογαριασμό
      // του, όπως το έδεσε κάποτε η οθόνη «Χρήστες».
      await repository.insert(
        Operator(
          displayName: 'Βλάσης',
          windowsAccount: 'vl.oikonomou',
          createdAt: DateTime(2026, 8, 20),
        ),
      );
      await repository.insert(
        Operator(
          displayName: 'Βασίλης',
          windowsAccount: 'v.drosos',
          createdAt: DateTime(2026, 8, 20),
        ),
      );
    });

    tearDown(() async {
      CurrentOperator.reset();
      await db.close();
    });

    test(
      'ο Βλάσης γυρίζει και η εφαρμογή ΡΩΤΑ αντί να τον κάνει Βασίλη',
      () async {
        // Ο Βασίλης κάθισε εδώ πέντε μέρες και πάτησε «Εδώ κάθομαι μόνο εγώ»:
        // ο υπολογιστής θυμάται ΜΟΝΟ αυτόν. Ο Βλάσης ανοίγει τον δικό του
        // υπολογιστή, με τον δικό του λογαριασμό.
        final resolved = await OperatorIdentity.resolveAndActivate(
          db,
          windowsAccount: 'vl.oikonomou',
          workstationNames: const <String>['Βασίλης'],
        );

        expect(
          resolved,
          isNull,
          reason:
              'Πριν από αυτόν τον έλεγχο η εκκίνηση τον έβαζε μέσα ως Βασίλη, '
              'και οι κλήσεις του γράφονταν σε άλλο όνομα',
        );
        expect(CurrentOperator.active, isNull);
      },
    );

    test('η λίστα που θα δει τον βάζει ΠΡΩΤΟ', () async {
      final selectable = await loadSelectableProfiles(
        db,
        workstationNames: const <String>['Βασίλης'],
        windowsAccount: 'vl.oikonomou',
      );

      expect(selectable.profiles.first.displayName, 'Βλάσης');
    });

    test('ο ίδιος ο Βασίλης μπαίνει κανονικά, χωρίς ερώτηση', () async {
      final resolved = await OperatorIdentity.resolveAndActivate(
        db,
        windowsAccount: 'v.drosos',
        workstationNames: const <String>['Βασίλης'],
      );

      expect(resolved?.displayName, 'Βασίλης');
    });

    test('σε κοινόχρηστο λογαριασμό τίποτα δεν αλλάζει', () async {
      // Ο λογαριασμός δεν ανήκει σε κανένα προφίλ: η μνήμη του σταθμού μένει
      // η μόνη απάντηση, όπως πάντα.
      final resolved = await OperatorIdentity.resolveAndActivate(
        db,
        windowsAccount: 'tpo.koino',
        workstationNames: const <String>['Βασίλης'],
      );

      expect(resolved?.displayName, 'Βασίλης');
    });
  });

  group('Η σφραγίδα του Ιστορικού', () {
    setUp(CurrentOperator.reset);
    tearDown(CurrentOperator.reset);

    test('χωρίς αναγνωρισμένο χρήστη γράφεται παύλα', () async {
      expect(AuditService.performingUser(), '—');
    });

    test('με ενεργό χρήστη γράφεται το όνομά του', () async {
      activateTestOperator('Βασίλης Δρόσος');

      expect(AuditService.performingUser(), 'Βασίλης Δρόσος');
    });

    test('κενό όνομα δεν αφήνει κενή σφραγίδα', () async {
      CurrentOperator.activate(
        Operator(displayName: '   ', createdAt: DateTime(2026, 1, 1)),
      );

      expect(AuditService.performingUser(), '—');
    });
  });

  group('Η μνήμη του σταθμού', () {
    late Database db;
    late OperatorRepository repository;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues(<String, Object>{});
      initSqfliteFfiForTests();
      db = await openDatabase(inMemoryDatabasePath, singleInstance: false);
      await onDatabaseUpgradeSquashed(db, 46, 47);
      await db.execute(kCreateAuditLogTable);
      repository = OperatorRepository(db);
      CurrentOperator.reset();
    });

    tearDown(() async {
      CurrentOperator.reset();
      await db.close();
    });

    /// Δύο προφίλ, το καθένα δεμένο στον δικό του λογαριασμό Windows.
    ///
    /// **Τα τεστ εδώ δουλεύουν με λογαριασμό που δεν ανήκει σε κανένα προφίλ**
    /// («tpo.koino», ο κοινόχρηστος του τμήματος). Αλλιώς θα έμπαινε στη μέση
    /// ο έλεγχος διάψευσης: όταν ο λογαριασμός δείχνει σε **άλλο** προφίλ από
    /// αυτό που θυμάται ο σταθμός, η εκκίνηση ρωτά αντί να μαντέψει — δες την
    /// ομάδα «Η επιστροφή από άδεια». Εδώ το ζητούμενο είναι άλλο: ότι η ρητή
    /// επιλογή του ανθρώπου επιβιώνει της επανεκκίνησης.
    Future<void> seedTwoProfiles() async {
      await repository.insert(
        Operator(
          displayName: 'Βασίλης',
          windowsAccount: 'v.drosos',
          isAdmin: true,
          createdAt: DateTime(2026, 8, 20),
        ),
      );
      await repository.insert(
        Operator(
          displayName: 'Bacilic',
          windowsAccount: 'bacilic',
          createdAt: DateTime(2026, 8, 20),
        ),
      );
    }

    test('η αλλαγή χρήστη επιβιώνει της επανεκκίνησης', () async {
      await seedTwoProfiles();

      // Πριν διαλέξει άνθρωπος, ο κοινόχρηστος λογαριασμός δεν λέει τίποτα.
      expect(
        await OperatorIdentity.resolveAndActivate(
          db,
          windowsAccount: 'tpo.koino',
        ),
        isNull,
      );

      // Ο άνθρωπος διαλέγει ρητά ποιος είναι.
      final vasilis = (await repository.getAll()).firstWhere(
        (operator) => operator.displayName == 'Βασίλης',
      );
      await OperatorIdentity.chooseForSession(vasilis);

      // Επανεκκίνηση: η επιλογή του κρατά, χωρίς δεύτερη ερώτηση.
      expect(
        (await OperatorIdentity.resolveAndActivate(
          db,
          windowsAccount: 'tpo.koino',
        ))?.displayName,
        'Βασίλης',
      );
      expect(CurrentOperator.active?.displayName, 'Βασίλης');
    });

    test('δύο άνθρωποι στον ίδιο σταθμό: η εκκίνηση ρωτά', () async {
      await seedTwoProfiles();
      final all = await repository.getAll();
      for (final operator in all) {
        await OperatorIdentity.chooseForSession(operator);
      }

      final resolved = await OperatorIdentity.resolveAndActivate(
        db,
        windowsAccount: 'tpo.koino',
      );

      expect(resolved, isNull, reason: 'όπου εναλλάσσονται πρόσωπα, ρωτάει');
      expect(CurrentOperator.active, isNull);
    });

    test('«Εδώ κάθομαι μόνο εγώ» σταματά την ερώτηση', () async {
      await seedTwoProfiles();
      final all = await repository.getAll();
      for (final operator in all) {
        await OperatorIdentity.chooseForSession(operator);
      }

      await WorkstationOperators.keepOnly('Βασίλης');

      expect(
        (await OperatorIdentity.resolveAndActivate(
          db,
          windowsAccount: 'tpo.koino',
        ))?.displayName,
        'Βασίλης',
      );
    });

    test('όνομα άλλης βάσης αγνοείται και αποφασίζει ο λογαριασμός', () async {
      // Μετά από αλλαγή βάσης τα προφίλ είναι άλλα: ένα όνομα που δεν υπάρχει
      // δεν επιτρέπεται ούτε να ενεργοποιήσει κάποιον, ούτε να μπλοκάρει.
      await seedTwoProfiles();

      expect(
        (await OperatorIdentity.resolveAndActivate(
          db,
          windowsAccount: 'bacilic',
          workstationNames: const <String>['Κάποιος Άλλος'],
        ))?.displayName,
        'Bacilic',
        reason:
            'Η μνήμη δεν ταίριαξε σε κανέναν, οπότε αποφασίζει ο λογαριασμός',
      );
    });

    test('η αυτόματη αναγνώριση δεν γεμίζει τη μνήμη του σταθμού', () async {
      // Αλλιώς ο πρώτος που αναγνωρίστηκε αυτόματα θα έμενε για πάντα στη
      // λίστα και ο σταθμός θα ρωτούσε αιώνια μετά την πρώτη αλλαγή χρήστη.
      await seedTwoProfiles();

      await OperatorIdentity.resolveAndActivate(db, windowsAccount: 'bacilic');

      expect(await WorkstationOperators.names(), isEmpty);
    });
  });
}
