// Οι κανόνες του εικονιδίου χρήστη, από τη δημιουργία ως την αποθήκευση.
//
//   flutter test test/features/operators/operator_avatar_rules_test.dart

import 'package:call_logger/core/database/database_schema_migrations.dart';
import 'package:call_logger/core/database/database_v1_schema.dart';
import 'package:call_logger/core/database/operator_avatar_backfill.dart';
import 'package:call_logger/core/database/operator_repository.dart';
import 'package:call_logger/core/models/operator.dart';
import 'package:call_logger/core/services/current_operator.dart';
import 'package:call_logger/features/operators/avatars/operator_avatar_catalog.dart';
import 'package:call_logger/features/operators/services/operator_management.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  group('Εικονίδιο χρήστη', () {
    late Database db;
    late OperatorRepository repository;
    late OperatorManagement management;

    setUp(() async {
      initSqfliteFfiForTests();
      db = await openDatabase(inMemoryDatabasePath, singleInstance: false);
      await onDatabaseUpgradeSquashed(db, 46, 47);
      await db.execute(kCreateAuditLogTable);
      repository = OperatorRepository(db);
      management = OperatorManagement(repository);
      CurrentOperator.reset();
    });

    tearDown(() async {
      CurrentOperator.reset();
      await db.close();
    });

    Future<Operator> create(String name, {String? avatar}) async {
      final result = await management.create(
        displayName: name,
        avatarKey: avatar,
      );
      expect(result.allowed, isTrue, reason: result.message);
      return result.operator!;
    }

    test('κάθε νέο προφίλ γεννιέται με εικονίδιο', () async {
      final created = await create('Βασίλης');

      expect(created.avatarKey, isNotNull);
      expect(findAvatar(created.avatarKey), isNotNull);
    });

    test('δύο προφίλ δεν παίρνουν ποτέ το ίδιο εικονίδιο', () async {
      // Όσοι χωράνε στον κατάλογο: κανένα ζευγάρι δεν επιτρέπεται να συμπέσει.
      final keys = <String>[];
      for (var i = 0; i < kOperatorAvatars.length; i++) {
        keys.add((await create('Χρήστης $i')).avatarKey!);
      }

      expect(keys.toSet().length, kOperatorAvatars.length);
    });

    test('όταν τελειώσουν τα εικονίδια, το προφίλ φτιάχνεται χωρίς', () async {
      for (var i = 0; i < kOperatorAvatars.length; i++) {
        await create('Χρήστης $i');
      }

      // Ο επόμενος περνά κανονικά — απλώς χωρίς πρόσωπο.
      final overflow = await create('Ο επιπλέον');

      expect(overflow.avatarKey, isNull);
    });

    test('το απενεργοποιημένο προφίλ κρατά το εικονίδιο, αλλά δεν το '
        'δεσμεύει', () async {
      final first = await create('Πρώτος', avatar: 'gorilla');
      await management.save(
        first,
        displayName: first.displayName,
        windowsAccount: null,
        isAdmin: false,
        isActive: false,
      );

      // Ο επόμενος μπορεί να πάρει τον γορίλα, γιατί ο κάτοχός του δεν δουλεύει
      // πια εδώ — απόφαση Διευθυντή.
      final second = await create('Δεύτερος', avatar: 'gorilla');
      expect(second.avatarKey, 'gorilla');

      // Και ο απενεργοποιημένος συνεχίζει να φαίνεται με τον δικό του, ώστε οι
      // παλιές εγγραφές του να μη μείνουν χωρίς πρόσωπο.
      final stored = await repository.findById(first.id!);
      expect(stored!.avatarKey, 'gorilla');
    });

    test(
      'η δημιουργία απορρίπτεται όταν το εικονίδιο είναι πιασμένο',
      () async {
        await create('Πρώτος', avatar: 'angel');

        final blocked = await management.create(
          displayName: 'Δεύτερος',
          avatarKey: 'angel',
        );

        expect(blocked.allowed, isFalse);
        expect(blocked.message, contains('εικονίδιο'));
      },
    );

    test('η αποθήκευση απορρίπτεται όταν το εικονίδιο πιάστηκε στο '
        'μεταξύ', () async {
      await create('Πρώτος', avatar: 'ninja');
      final second = await create('Δεύτερος', avatar: 'chef');

      final blocked = await management.save(
        second,
        displayName: second.displayName,
        windowsAccount: null,
        isAdmin: false,
        isActive: true,
        avatarKey: 'ninja',
      );

      expect(blocked.allowed, isFalse);
      expect(blocked.message, contains('εικονίδιο'));
    });

    test('ο χρήστης μπορεί να επιστρέψει στο κλασικό ανθρωπάκι', () async {
      final person = await create('Βασίλης', avatar: 'pirate');

      final saved = await management.save(
        person,
        displayName: person.displayName,
        windowsAccount: null,
        isAdmin: false,
        isActive: true,
        clearAvatarKey: true,
      );

      expect(saved.allowed, isTrue, reason: saved.message);
      expect((await repository.findById(person.id!))!.avatarKey, isNull);
    });

    test('η αλλαγή εικονιδίου επιβιώνει της αποθήκευσης', () async {
      final person = await create('Βασίλης', avatar: 'woman');

      await management.save(
        person,
        displayName: person.displayName,
        windowsAccount: null,
        isAdmin: false,
        isActive: true,
        avatarKey: 'platypus',
      );

      expect((await repository.findById(person.id!))!.avatarKey, 'platypus');
    });

    group('μετάπτωση παλιάς βάσης', () {
      test('τα υπάρχοντα προφίλ αποκτούν ξεχωριστά εικονίδια', () async {
        for (var i = 0; i < 3; i++) {
          await repository.insert(
            Operator(displayName: 'Παλιός $i', createdAt: DateTime(2026, 1, 1)),
          );
        }

        final assigned = await assignAvatarsToExistingOperators(db);
        expect(assigned, 3);

        final keys = [
          for (final operator in await repository.getAll()) operator.avatarKey,
        ];
        expect(keys, everyElement(isNotNull));
        expect(keys.toSet().length, 3);
      });

      test('όποιος έχει ήδη διαλέξει δεν χάνει την επιλογή του', () async {
        final chosen = await repository.insert(
          Operator(
            displayName: 'Διάλεξε',
            avatarKey: 'gorilla',
            createdAt: DateTime(2026, 1, 1),
          ),
        );

        await assignAvatarsToExistingOperators(db);

        expect((await repository.findById(chosen.id!))!.avatarKey, 'gorilla');
      });

      test('ξανατρέχει χωρίς να αλλάξει τίποτα', () async {
        await repository.insert(
          Operator(displayName: 'Παλιός', createdAt: DateTime(2026, 1, 1)),
        );

        await assignAvatarsToExistingOperators(db);
        final afterFirst = (await repository.getAll()).single.avatarKey;

        final second = await assignAvatarsToExistingOperators(db);

        expect(second, 0);
        expect((await repository.getAll()).single.avatarKey, afterFirst);
      });
    });
  });
}
