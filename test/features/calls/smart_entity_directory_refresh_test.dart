// Έλεγχος: μετά από directory mutations από smart entity selector, οι sibling
// κατάλογοι ανανεώνονται χωρίς χειροκίνητο reload.
//
//   flutter test test/features/calls/smart_entity_directory_refresh_test.dart

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/phone_repository.dart';
import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:call_logger/features/calls/provider/smart_entity_selector_provider.dart';
import 'package:call_logger/features/directory/providers/directory_provider.dart';
import 'package:call_logger/features/directory/providers/equipment_directory_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../helpers/association_two_step_runner.dart';
import '../../test_setup.dart';

Future<ProviderContainer> _containerWithFreshCatalog() async {
  await AssociationTwoStepRunner.resetCatalog();
  final container = ProviderContainer(
    overrides: callLoggerTestProviderOverrides(),
  );
  await container.read(lookupServiceProvider.future);
  return container;
}

Future<void> _preloadSiblingCatalogs(ProviderContainer container) async {
  await container.read(directoryProvider.notifier).loadUsers();
  await container.read(equipmentDirectoryProvider.notifier).load();
}

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  group('Smart entity — refreshDirectoryCaches sibling catalogs', () {
    test(
      'associateCurrentIfNeeded προσθέτει νέο χρήστη και εξοπλισμό στον κατάλογο',
      () async {
        final container = await _containerWithFreshCatalog();
        await _preloadSiblingCatalogs(container);

        final usersBefore = container.read(directoryProvider).allUsers.length;
        final equipmentBefore = container
            .read(equipmentDirectoryProvider)
            .allItems
            .length;

        const callerName = 'Νέος Κατάλογος';
        const phone = '208881';
        const equipmentCode = 'NEW-EQ-881';

        final notifier = container.read(callSmartEntityProvider.notifier);
        notifier.updateCallerDisplayText(callerName);
        notifier.checkContent(callerText: callerName);
        notifier.updatePhone(phone);
        notifier.checkContent(phoneText: phone);
        notifier.checkContent(equipmentText: equipmentCode);

        expect(
          container.read(callSmartEntityProvider).needsNewCallerCreation,
          isTrue,
        );

        final message = await notifier.associateCurrentIfNeeded();
        expect(message, isNotNull);
        expect(message!.contains('Σφάλμα'), isFalse);

        final usersAfter = container.read(directoryProvider).allUsers;
        expect(usersAfter.length, greaterThan(usersBefore));
        expect(
          usersAfter.any(
            (u) =>
                (u.name ?? '').contains('Νέος') &&
                (u.name ?? '').contains('Κατάλογος'),
          ),
          isTrue,
          reason:
              'directoryProvider πρέπει να περιέχει τον νέο χρήστη χωρίς loadUsers()',
        );

        final equipmentAfter = container
            .read(equipmentDirectoryProvider)
            .allItems;
        expect(equipmentAfter.length, greaterThan(equipmentBefore));
        expect(
          equipmentAfter.any(
            (row) => (row.$1.code ?? '').trim() == equipmentCode,
          ),
          isTrue,
          reason:
              'equipmentDirectoryProvider πρέπει να περιέχει τον νέο εξοπλισμό χωρίς load()',
        );

        container.dispose();
      },
    );

    test(
      'quickAddOrphanToDepartment προσθέτει κοινόχρηστο τηλέφωνο στον κατάλογο χρηστών',
      () async {
        final container = await _containerWithFreshCatalog();
        await _preloadSiblingCatalogs(container);

        const orphanPhone = '7771';
        const deptName = 'Τμήμα Κοινόχρηστου Τηλεφώνου';

        final phonesBefore = container
            .read(directoryProvider)
            .allNonUserPhones
            .length;

        final notifier = container.read(callSmartEntityProvider.notifier);
        notifier.updatePhone(orphanPhone);
        notifier.checkContent(phoneText: orphanPhone);
        notifier.updateDepartmentText(deptName);
        notifier.checkContent(departmentText: deptName);

        expect(
          container.read(callSmartEntityProvider).needsOrphanDepartmentQuickAdd,
          isTrue,
        );

        final result = await notifier.quickAddOrphanToDepartment(
          forceSharedOnConflict: true,
        );
        expect(result, isNotNull);
        expect(result!.requiresConfirmation, isFalse);
        expect(result.successMessage, isNotNull);

        final phonesAfter = container.read(directoryProvider).allNonUserPhones;
        expect(phonesAfter.length, greaterThan(phonesBefore));
        expect(
          phonesAfter.any((p) => p.number.contains(orphanPhone)),
          isTrue,
          reason:
              'directoryProvider.allNonUserPhones πρέπει να περιέχει το κοινόχρηστο τηλέφωνο χωρίς loadUsers()',
        );

        container.dispose();
      },
    );
  });

  group('Smart entity — δεύτερη συσχέτιση στον ίδιο καλούντα', () {
    test(
      'η αλλαγή κύριου τμήματος δεν σβήνει ψευδώνυμο, τοποθεσία και Lansweeper',
      () async {
        await AssociationTwoStepRunner.resetCatalog();
        final db = await DatabaseHelper.instance.database;
        Future<int> department(String name) => db.insert('departments', {
          'name': name,
          'name_key': SearchTextNormalizer.normalizeForSearch(name),
          'is_deleted': 0,
        });
        final secretariatId = await department('Γραμματεία');
        await department('Παθολογική');
        final userId = await db.insert('users', {
          'first_name': 'Γεωργία',
          'last_name': 'Παπαγεωργίου',
          'nickname': 'Γωγώ',
          'location': 'Γραφείο 12',
          'lansweeper_username': 'gpapageorgiou',
          'department_id': secretariatId,
          'is_deleted': 0,
        });

        LookupService.instance.resetForReload();
        await LookupService.instance.loadFromDatabase();
        final container = ProviderContainer(
          overrides: callLoggerTestProviderOverrides(),
        );
        final lookup = (await container.read(
          lookupServiceProvider.future,
        )).service;
        final gogo = lookup.findUserById(userId);
        expect(gogo?.nickname, 'Γωγώ');
        final notifier = container.read(callSmartEntityProvider.notifier);

        // Πρώτη συσχέτιση: νέο τηλέφωνο, και μετά η Γεωργία από τη λίστα.
        notifier.updatePhone('2999');
        notifier.checkContent(phoneText: '2999');
        notifier.setCaller(gogo);
        final first = await notifier.associateCurrentIfNeeded();
        expect(first?.contains('Σφάλμα') ?? false, isFalse);

        // Δεύτερη συσχέτιση: αλλαγή κύριου τμήματος.
        final lookupNow = (await container.read(
          lookupServiceProvider.future,
        )).service;
        notifier.selectDepartment(
          lookupNow.findDepartmentByName('Παθολογική')!,
        );
        final second = await notifier.associateCurrentIfNeeded(
          updatePrimaryDepartment: true,
        );
        expect(second?.contains('Σφάλμα') ?? false, isFalse);

        final row = (await db.query(
          'users',
          where: 'id = ?',
          whereArgs: [userId],
        )).single;
        final departmentName = (await db.query(
          'departments',
          where: 'id = ?',
          whereArgs: [row['department_id']],
        )).single['name'];
        expect(departmentName, 'Παθολογική');
        expect(
          row['nickname'],
          'Γωγώ',
          reason:
              'Η φόρμα γράφει μόνο ό,τι άλλαξε — ποτέ ένα αντίγραφο που έχει '
              'χάσει τα υπόλοιπα στοιχεία του υπαλλήλου',
        );
        expect(row['location'], 'Γραφείο 12');
        expect(row['lansweeper_username'], 'gpapageorgiou');
        final phones = await db.rawQuery(
          'SELECT p.number FROM user_phones up '
          'JOIN phones p ON p.id = up.phone_id WHERE up.user_id = ?',
          [userId],
        );
        expect(phones.map((r) => r['number']), contains('2999'));

        container.dispose();
      },
    );
    test(
      'νέο τηλέφωνο και αλλαγή τμήματος με ένα «+» κρατούν το τηλέφωνο',
      () async {
        await AssociationTwoStepRunner.resetCatalog();
        final db = await DatabaseHelper.instance.database;
        Future<int> department(String name) => db.insert('departments', {
          'name': name,
          'name_key': SearchTextNormalizer.normalizeForSearch(name),
          'is_deleted': 0,
        });
        final secretariatId = await department('Γραμματεία');
        await department('Παθολογική');
        final userId = await db.insert('users', {
          'first_name': 'Γεωργία',
          'last_name': 'Παπαγεωργίου',
          'department_id': secretariatId,
          'is_deleted': 0,
        });
        LookupService.instance.resetForReload();
        await LookupService.instance.loadFromDatabase();
        final container = ProviderContainer(
          overrides: callLoggerTestProviderOverrides(),
        );
        final lookup = (await container.read(
          lookupServiceProvider.future,
        )).service;
        final notifier = container.read(callSmartEntityProvider.notifier);

        notifier.updatePhone('2999');
        notifier.checkContent(phoneText: '2999');
        notifier.setCaller(lookup.findUserById(userId));
        notifier.selectDepartment(lookup.findDepartmentByName('Παθολογική')!);
        final message = await notifier.associateCurrentIfNeeded(
          updatePrimaryDepartment: true,
        );
        expect(message?.contains('Σφάλμα') ?? false, isFalse);

        final phones = await db.rawQuery(
          'SELECT p.number FROM user_phones up '
          'JOIN phones p ON p.id = up.phone_id WHERE up.user_id = ?',
          [userId],
        );
        expect(
          phones.map((r) => r['number']),
          contains('2999'),
          reason:
              'Το τηλέφωνο που μόλις δέθηκε δεν ξεδένεται από την εγγραφή '
              'του τμήματος στο ίδιο πάτημα',
        );

        container.dispose();
      },
    );
    test(
      'αποτυχία στη μέση του «+»: η φόρμα ξέρει ό,τι πρόλαβε να γραφτεί',
      () async {
        await AssociationTwoStepRunner.resetCatalog();
        final db = await DatabaseHelper.instance.database;
        Future<int> department(String name) => db.insert('departments', {
          'name': name,
          'name_key': SearchTextNormalizer.normalizeForSearch(name),
          'is_deleted': 0,
        });
        final secretariatId = await department('Γραμματεία');
        await department('Παθολογική');
        final userId = await db.insert('users', {
          'first_name': 'Γεωργία',
          'last_name': 'Παπαγεωργίου',
          'department_id': secretariatId,
          'is_deleted': 0,
        });
        LookupService.instance.resetForReload();
        await LookupService.instance.loadFromDatabase();
        final container = ProviderContainer(
          overrides: callLoggerTestProviderOverrides(),
        );
        final lookup = (await container.read(
          lookupServiceProvider.future,
        )).service;
        final notifier = container.read(callSmartEntityProvider.notifier);

        notifier.updatePhone('2999');
        notifier.checkContent(phoneText: '2999');
        notifier.setCaller(lookup.findUserById(userId));
        notifier.selectDepartment(lookup.findDepartmentByName('Παθολογική')!);
        // Η αλλαγή τμήματος αποτυγχάνει — όπως σε κλειδωμένη βάση — αφού
        // το τηλέφωνο έχει ήδη συνδεθεί.
        await db.execute(
          'CREATE TRIGGER refuse_department_change '
          'BEFORE UPDATE OF department_id ON users '
          "BEGIN SELECT RAISE(ABORT, 'database is locked'); END",
        );
        try {
          final message = await notifier.associateCurrentIfNeeded(
            updatePrimaryDepartment: true,
          );
          expect(message, startsWith('Σφάλμα αποθήκευσης'));
        } finally {
          await db.execute('DROP TRIGGER IF EXISTS refuse_department_change');
        }

        final linked = await db.rawQuery(
          'SELECT 1 FROM user_phones up JOIN phones p ON p.id = up.phone_id '
          "WHERE up.user_id = ? AND p.number = '2999'",
          [userId],
        );
        expect(linked, hasLength(1), reason: 'το τηλέφωνο πρόλαβε να γραφτεί');
        final lookupAfter = container
            .read(lookupServiceProvider)
            .value!
            .service;
        expect(
          lookupAfter.findUsersByPhone('2999').map((u) => u.id),
          contains(userId),
          reason:
              'Ο κατάλογος της φόρμας ξαναδιαβάζεται μετά την αποτυχία — '
              'αλλιώς το επόμενο «+» ρωτά ξανά για ό,τι ήδη υπάρχει',
        );

        container.dispose();
      },
    );
  });

  group('Smart entity — κοινόχρηστα του τμήματος του καλούντα', () {
    Future<({ProviderContainer container, int maria})> seed() async {
      await AssociationTwoStepRunner.resetCatalog();
      final db = await DatabaseHelper.instance.database;
      final treasuryId = await db.insert('departments', {
        'name': 'Χρηματικό',
        'name_key': SearchTextNormalizer.normalizeForSearch('Χρηματικό'),
        'is_deleted': 0,
      });
      await db.insert('phones', {
        'number': '2858',
        'department_id': treasuryId,
      });
      await db.insert('equipment', {
        'code_equipment': '3799',
        'department_id': treasuryId,
      });
      final maria = await db.insert('users', {
        'first_name': 'Μαρία',
        'last_name': 'Κυζιρίδου',
        'department_id': treasuryId,
        'is_deleted': 0,
      });
      LookupService.instance.resetForReload();
      await LookupService.instance.loadFromDatabase();
      final container = ProviderContainer(
        overrides: callLoggerTestProviderOverrides(),
      );
      await container.read(lookupServiceProvider.future);
      return (container: container, maria: maria);
    }

    test(
      'το κοινό τηλέφωνο του τμήματος δεν προτείνεται ως προσωπικό',
      () async {
        final seeded = await seed();
        final container = seeded.container;
        final lookup = (await container.read(
          lookupServiceProvider.future,
        )).service;
        final notifier = container.read(callSmartEntityProvider.notifier);

        notifier.updatePhone('2858');
        notifier.checkContent(phoneText: '2858');
        notifier.setCaller(lookup.findUserById(seeded.maria));

        final state = container.read(callSmartEntityProvider);
        expect(
          state.needsAssociation(lookup),
          isFalse,
          reason:
              'Η σύνδεση υπάρχει ήδη μέσω του τμήματος — το «+» θα έκανε το '
              'κοινό τηλέφωνο προσωπικό της Μαρίας',
        );
        container.dispose();
      },
    );

    test(
      'ο κοινόχρηστος εξοπλισμός του τμήματος δεν προτείνεται για δέσιμο',
      () async {
        final seeded = await seed();
        final container = seeded.container;
        final lookup = (await container.read(
          lookupServiceProvider.future,
        )).service;
        final notifier = container.read(callSmartEntityProvider.notifier);

        notifier.setCaller(lookup.findUserById(seeded.maria));
        notifier.checkContent(equipmentText: '3799');

        final state = container.read(callSmartEntityProvider);
        expect(state.equipmentText.trim(), '3799');
        expect(state.needsAssociation(lookup), isFalse);
        container.dispose();
      },
    );

    test('άγνωστο τηλέφωνο εξακολουθεί να προτείνεται', () async {
      final seeded = await seed();
      final container = seeded.container;
      final lookup = (await container.read(
        lookupServiceProvider.future,
      )).service;
      final notifier = container.read(callSmartEntityProvider.notifier);

      notifier.updatePhone('2859');
      notifier.checkContent(phoneText: '2859');
      notifier.setCaller(lookup.findUserById(seeded.maria));

      expect(
        container.read(callSmartEntityProvider).needsAssociation(lookup),
        isTrue,
      );
      container.dispose();
    });
  });

  group('Smart entity — ό,τι λέει το «+» είναι ό,τι έγινε', () {
    Future<({ProviderContainer container, int koika, int plakogianni})>
    seed() async {
      await AssociationTwoStepRunner.resetCatalog();
      final db = await DatabaseHelper.instance.database;
      Future<int> department(String name) => db.insert('departments', {
        'name': name,
        'name_key': SearchTextNormalizer.normalizeForSearch(name),
        'is_deleted': 0,
      });
      final leaves = await department('Άδειες');
      await department('Βιοχημικό');
      final biomedical = await department('Βιοϊατρική');
      final koika = await db.insert('users', {
        'first_name': 'Βασιλική',
        'last_name': 'Κόικα',
        'department_id': leaves,
        'is_deleted': 0,
      });
      final plakogianni = await db.insert('users', {
        'first_name': 'Ελένη',
        'last_name': 'Πλακογιάννη',
        'department_id': biomedical,
        'is_deleted': 0,
      });
      final eq = await db.insert('equipment', {
        'code_equipment': '3248',
        'is_deleted': 0,
      });
      await db.insert('user_equipment', {
        'user_id': plakogianni,
        'equipment_id': eq,
      });
      // 2600: ελεύθερο τηλέφωνο, χωρίς κάτοχο και χωρίς τμήμα.
      await db.insert('phones', {'number': '2600'});
      LookupService.instance.resetForReload();
      await LookupService.instance.loadFromDatabase();
      final container = ProviderContainer(
        overrides: callLoggerTestProviderOverrides(),
      );
      await container.read(lookupServiceProvider.future);
      return (container: container, koika: koika, plakogianni: plakogianni);
    }

    test(
      '«Όχι» στη μεταφορά: το μήνυμα και η εκκρεμότητα δεν αναφέρουν αλλαγή τμήματος',
      () async {
        final seeded = await seed();
        final container = seeded.container;
        final lookup = (await container.read(
          lookupServiceProvider.future,
        )).service;
        final notifier = container.read(callSmartEntityProvider.notifier);
        notifier.setCaller(lookup.findUserById(seeded.koika));
        notifier.selectDepartment(lookup.findDepartmentByName('Βιοχημικό')!);
        notifier.checkContent(equipmentText: '3000');

        final message = await notifier.associateCurrentIfNeeded();

        expect(message, contains('3000'));
        expect(
          message,
          isNot(contains('Αλλαγή τμήματος')),
          reason:
              'Το τμήμα δεν άλλαξε — το μήνυμα λέει ό,τι έγινε, όχι ό,τι '
              'προβλεπόταν',
        );
        final db = await DatabaseHelper.instance.database;
        final tasks = await db.query('tasks');
        expect(tasks, hasLength(1));
        expect(
          tasks.single['description'] as String,
          isNot(contains('Αλλαγή τμήματος')),
        );
        container.dispose();
      },
    );

    test(
      'νέος καλών: εξοπλισμός υπαλλήλου άλλου τμήματος δεν δένεται χωρίς ερώτηση',
      () async {
        final seeded = await seed();
        final container = seeded.container;
        final lookup = (await container.read(
          lookupServiceProvider.future,
        )).service;
        final notifier = container.read(callSmartEntityProvider.notifier);
        notifier.updateCallerDisplayText('Νέα Υπάλληλος');
        notifier.checkContent(callerText: 'Νέα Υπάλληλος');
        notifier.selectDepartment(lookup.findDepartmentByName('Άδειες')!);
        notifier.checkContent(equipmentText: '3248');
        expect(
          container.read(callSmartEntityProvider).needsNewCallerCreation,
          isTrue,
        );

        // Χωρίς οθόνη δεν υπάρχει ποιον να ρωτήσουμε: τίποτα δεν γράφεται.
        final message = await notifier.associateCurrentIfNeeded();
        expect(message, isNull);

        final db = await DatabaseHelper.instance.database;
        expect(await db.query('users', where: "first_name = 'Νέα'"), isEmpty);
        final owners = await db.rawQuery(
          'SELECT ue.user_id FROM user_equipment ue '
          'JOIN equipment e ON e.id = ue.equipment_id '
          "WHERE e.code_equipment = '3248'",
        );
        expect(owners.map((r) => r['user_id']), [seeded.plakogianni]);
        container.dispose();
      },
    );

    test(
      'εξοπλισμός υπαλλήλου άλλου τμήματος δεν δένεται χωρίς ερώτηση',
      () async {
        final seeded = await seed();
        final container = seeded.container;
        final lookup = (await container.read(
          lookupServiceProvider.future,
        )).service;
        final notifier = container.read(callSmartEntityProvider.notifier);
        notifier.setCaller(lookup.findUserById(seeded.koika));
        notifier.checkContent(equipmentText: '3248');

        // Χωρίς οθόνη δεν υπάρχει ποιον να ρωτήσουμε: τίποτα δεν γράφεται.
        final message = await notifier.associateCurrentIfNeeded();
        expect(message, isNull);

        final db = await DatabaseHelper.instance.database;
        final owners = await db.rawQuery(
          'SELECT ue.user_id FROM user_equipment ue '
          'JOIN equipment e ON e.id = ue.equipment_id '
          "WHERE e.code_equipment = '3248'",
        );
        expect(owners.map((r) => r['user_id']), [seeded.plakogianni]);
        container.dispose();
      },
    );

    // Κοινό μηχάνημα και αλλαγή τμήματος χωρίς οθόνη για ερώτηση: ισχύει η
    // συνηθισμένη απάντηση — το μηχάνημα μένει στο τμήμα του (03/10).
    test(
      'αλλαγή τμήματος χωρίς οθόνη: το κοινό μηχάνημα μένει στο τμήμα του',
      () async {
        final seeded = await seed();
        final container = seeded.container;
        final db = await DatabaseHelper.instance.database;
        final leaves = (await db.query(
          'departments',
          where: "name = 'Άδειες'",
        )).single['id'];
        final colleague = await db.insert('users', {
          'first_name': 'Ελένη',
          'last_name': 'Συνάδελφος',
          'department_id': leaves,
          'is_deleted': 0,
        });
        final shared = await db.insert('equipment', {
          'code_equipment': 'SH-1',
          'department_id': leaves,
          'is_deleted': 0,
        });
        for (final owner in [seeded.koika, colleague]) {
          await db.insert('user_equipment', {
            'user_id': owner,
            'equipment_id': shared,
          });
        }
        LookupService.instance.resetForReload();
        await LookupService.instance.loadFromDatabase();
        container.invalidate(lookupServiceProvider);
        final lookup = (await container.read(
          lookupServiceProvider.future,
        )).service;
        final notifier = container.read(callSmartEntityProvider.notifier);
        notifier.setCaller(lookup.findUserById(seeded.koika));
        notifier.selectDepartment(lookup.findDepartmentByName('Βιοχημικό')!);
        notifier.checkContent(equipmentText: '3000');

        await notifier.associateCurrentIfNeeded(updatePrimaryDepartment: true);

        final owners = (await db.query(
          'user_equipment',
          where: 'equipment_id = ?',
          whereArgs: [shared],
        )).map((r) => r['user_id']).toList();
        expect(owners, [
          colleague,
        ], reason: 'Μένει στο τμήμα του, με τη συνάδελφο — όχι μοιρασμένο');
        container.dispose();
      },
    );

    // Το ίδιο για κοινό τηλέφωνο (04/10): χωρίς οθόνη ο αριθμός μένει στους
    // συναδέλφους, αντί να ακολουθήσει και να μοιραστεί σε δύο τμήματα.
    test(
      'αλλαγή τμήματος χωρίς οθόνη: το κοινό τηλέφωνο μένει στη συνάδελφο',
      () async {
        final seeded = await seed();
        final container = seeded.container;
        final db = await DatabaseHelper.instance.database;
        final leaves = (await db.query(
          'departments',
          where: "name = 'Άδειες'",
        )).single['id'];
        final colleague = await db.insert('users', {
          'first_name': 'Ελένη',
          'last_name': 'Συνάδελφος',
          'department_id': leaves,
          'is_deleted': 0,
        });
        final phone = await db.insert('phones', {'number': '2534'});
        for (final owner in [seeded.koika, colleague]) {
          await db.insert('user_phones', {'user_id': owner, 'phone_id': phone});
        }
        LookupService.instance.resetForReload();
        await LookupService.instance.loadFromDatabase();
        container.invalidate(lookupServiceProvider);
        final lookup = (await container.read(
          lookupServiceProvider.future,
        )).service;
        final notifier = container.read(callSmartEntityProvider.notifier);
        notifier.setCaller(lookup.findUserById(seeded.koika));
        notifier.selectDepartment(lookup.findDepartmentByName('Βιοχημικό')!);
        notifier.checkContent(equipmentText: '3000');

        await notifier.associateCurrentIfNeeded(updatePrimaryDepartment: true);

        final holders = await PhoneRepository(db).holderUserIds('2534');
        expect(holders, [
          colleague,
        ], reason: 'Μένει στο τμήμα του, με τη συνάδελφο — όχι μοιρασμένο');
        container.dispose();
      },
    );

    test('νέος καλών σε νέο τμήμα: το μήνυμα απαριθμεί ό,τι έγινε, η αναίρεση '
        'μόνο ό,τι γεννήθηκε', () async {
      final seeded = await seed();
      final container = seeded.container;
      final notifier = container.read(callSmartEntityProvider.notifier);
      notifier.updateCallerDisplayText('Μαρία Δαμανάκη');
      notifier.checkContent(callerText: 'Μαρία Δαμανάκη');
      notifier.updateDepartmentText('Ακτινολογικό');
      notifier.checkContent(departmentText: 'Ακτινολογικό');
      notifier.updatePhone('2600');
      notifier.checkContent(phoneText: '2600');
      notifier.checkContent(equipmentText: '5555');

      final message = await notifier.associateCurrentIfNeeded();

      expect(message!.split('\n').take(4).toList(), [
        'Δημιουργήθηκε νέος χρήστης Μαρία Δαμανάκη στο τμήμα: Ακτινολογικό',
        'Δημιουργήθηκε νέο τμήμα: Ακτινολογικό',
        'Συσχετίστηκε τηλέφωνο: 2600',
        'Δημιουργήθηκε νέος εξοπλισμός: 5555',
      ]);
      final undo = notifier.lastQuickAddUndo;
      expect(undo.createdUserId, isNotNull);
      expect(undo.createdDepartmentName, 'Ακτινολογικό');
      expect(
        undo.createdPhone,
        isNull,
        reason: 'Το 2600 υπήρχε πριν — η αναίρεση δεν το σβήνει',
      );
      expect(undo.createdEquipmentCode, '5555');

      final db = await DatabaseHelper.instance.database;
      final user = (await db.query(
        'users',
        where: 'id = ?',
        whereArgs: [undo.createdUserId],
      )).single;
      expect(user['department_id'], undo.createdDepartmentId);
      final state = container.read(callSmartEntityProvider);
      expect(state.selectedCaller?.id, undo.createdUserId);
      expect(state.selectedEquipment?.id, isNotNull);
      container.dispose();
    });

    test('νέος καλών σε υπάρχον τμήμα: το τμήμα δεν δημιουργείται ούτε '
        'αναιρείται, το νέο τηλέφωνο ναι', () async {
      final seeded = await seed();
      final container = seeded.container;
      final lookup = (await container.read(
        lookupServiceProvider.future,
      )).service;
      final notifier = container.read(callSmartEntityProvider.notifier);
      notifier.updateCallerDisplayText('Μαρία Δαμανάκη');
      notifier.checkContent(callerText: 'Μαρία Δαμανάκη');
      notifier.selectDepartment(lookup.findDepartmentByName('Άδειες')!);
      notifier.updatePhone('2700');
      notifier.checkContent(phoneText: '2700');

      final message = await notifier.associateCurrentIfNeeded();

      expect(message!.split('\n').take(2).toList(), [
        'Δημιουργήθηκε νέος χρήστης Μαρία Δαμανάκη στο τμήμα: Άδειες',
        'Δημιουργήθηκε νέο τηλέφωνο: 2700',
      ]);
      expect(message, isNot(contains('νέο τμήμα')));
      final undo = notifier.lastQuickAddUndo;
      expect(undo.createdDepartmentId, isNull);
      expect(undo.createdPhone, '2700');
      expect(undo.createdEquipmentCode, isNull);
      container.dispose();
    });
  });
}
