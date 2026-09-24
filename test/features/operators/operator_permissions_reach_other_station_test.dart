// Η αλλαγή δικαιωμάτων φτάνει στον σταθμό του συναδέλφου, χωρίς να κλείσει
// την εφαρμογή — και χωρίς να μιλήσει όταν δεν άλλαξε τίποτα.
//
//   flutter test test/features/operators/operator_permissions_reach_other_station_test.dart

import 'package:call_logger/core/database/database_schema_migrations.dart';
import 'package:call_logger/core/database/database_v1_schema.dart';
import 'package:call_logger/core/database/operator_repository.dart';
import 'package:call_logger/core/models/app_permission.dart';
import 'package:call_logger/core/models/operator.dart';
import 'package:call_logger/core/services/current_operator.dart';
import 'package:call_logger/core/services/operator_profile_refresh.dart';
import 'package:call_logger/core/services/permission_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  group('Δικαιώματα από άλλον σταθμό', () {
    late Database db;
    late OperatorRepository repository;

    /// Πόσες φορές μίλησε η ταυτότητα — δηλαδή πόσες φορές θα ξαναχτιζόταν
    /// οτιδήποτε κρίνεται από αυτήν.
    late int announcements;
    void countAnnouncement() => announcements++;

    setUp(() async {
      initSqfliteFfiForTests();
      db = await openDatabase(inMemoryDatabasePath, singleInstance: false);
      await onDatabaseUpgradeSquashed(db, 46, 47);
      await db.execute(kCreateAuditLogTable);
      repository = OperatorRepository(db);
      CurrentOperator.reset();
      announcements = 0;
      CurrentOperator.listenable.addListener(countAnnouncement);
    });

    tearDown(() async {
      CurrentOperator.listenable.removeListener(countAnnouncement);
      CurrentOperator.reset();
      await db.close();
    });

    /// Ο Βλάσης δουλεύει στον διπλανό υπολογιστή, με την εφαρμογή ανοιχτή.
    Future<Operator> seatVlasis() async {
      final vlasis = await repository.insert(
        Operator(displayName: 'Βλάσης', createdAt: DateTime(2026, 9, 1)),
      );
      CurrentOperator.activate(vlasis);
      announcements = 0;
      return vlasis;
    }

    test(
      'ο διαχειριστής ΔΙΝΕΙ πρόσβαση και ο συνάδελφος τη βλέπει χωρίς να κλείσει την εφαρμογή',
      () async {
        final vlasis = await seatVlasis();
        expect(
          PermissionService.instance.can(AppPermission.viewApplicationAudit),
          isFalse,
          reason: 'Το Ιστορικό Εφαρμογής είναι κλειστό από προεπιλογή',
        );

        // Ο διαχειριστής, από τον δικό ΤΟΥ σταθμό.
        await repository.update(
          vlasis.copyWith(
            permissionOverrides: {AppPermission.viewApplicationAudit.key: true},
          ),
          expected: vlasis,
        );

        final changed = await refreshCurrentOperatorProfile(db);

        expect(changed, isTrue);
        expect(
          PermissionService.instance.can(AppPermission.viewApplicationAudit),
          isTrue,
        );
        expect(announcements, 1);
      },
    );

    test(
      'ο διαχειριστής ΑΦΑΙΡΕΙ πρόσβαση και η προστασία αρχίζει να ισχύει',
      () async {
        final vlasis = await seatVlasis();
        await repository.update(
          vlasis.copyWith(
            permissionOverrides: {AppPermission.viewApplicationAudit.key: true},
          ),
          expected: vlasis,
        );
        await refreshCurrentOperatorProfile(db);
        expect(
          PermissionService.instance.can(AppPermission.viewApplicationAudit),
          isTrue,
        );

        // Και τώρα του το παίρνει πίσω — η φορά που μετράει περισσότερο.
        final withAccess = (await repository.findById(vlasis.id!))!;
        await repository.update(
          withAccess.copyWith(permissionOverrides: const <String, bool>{}),
          expected: withAccess,
        );

        expect(await refreshCurrentOperatorProfile(db), isTrue);
        expect(
          PermissionService.instance.can(AppPermission.viewApplicationAudit),
          isFalse,
        );
      },
    );

    test('η αιτία λέει «ο ίδιος άνθρωπος», όχι «κάθισε άλλος»', () async {
      final vlasis = await seatVlasis();
      await repository.update(
        vlasis.copyWith(
          permissionOverrides: {AppPermission.fullBackup.key: true},
        ),
        expected: vlasis,
      );

      await refreshCurrentOperatorProfile(db);

      // Από αυτή τη διάκριση κρέμεται το αν ο συνάδελφος χάνει τη δουλειά που
      // έχει ανοιχτή μπροστά του.
      expect(
        CurrentOperator.lastChangeCause,
        OperatorChangeCause.profileRefreshed,
      );
    });

    test('χωρίς αλλαγή, η ταυτότητα ΔΕΝ μιλά καθόλου', () async {
      await seatVlasis();

      // Ο κύκλος φρεσκάδας τρέχει κάθε φορά που γράφει οποιοσδήποτε — με το
      // σημάδι παρουσίας, κάθε μισό λεπτό. Αν μιλούσε η ταυτότητα σε κάθε
      // πέρασμα, θα έσερνε μαζί της ακύρωση caches σε δικτυακή βάση.
      for (var i = 0; i < 5; i++) {
        expect(await refreshCurrentOperatorProfile(db), isFalse);
      }

      expect(announcements, 0);
    });

    test('προφίλ που δεν βρίσκεται ΔΕΝ αφήνει τον χρήστη ανώνυμο', () async {
      final vlasis = await seatVlasis();
      await db.delete('operators', where: 'id = ?', whereArgs: [vlasis.id]);

      final changed = await refreshCurrentOperatorProfile(db);

      // Ένα `activate(null)` θα έδινε ΠΕΡΙΣΣΟΤΕΡΑ δικαιώματα από όσα υπήρχαν:
      // χωρίς ταυτότητα ο έλεγχος απαντά «ναι» σε όλα, και το Ιστορικό
      // σφραγίζεται με παύλα.
      expect(changed, isFalse);
      expect(CurrentOperator.active?.id, vlasis.id);
      expect(CurrentOperator.auditName, 'Βλάσης');
      expect(announcements, 0);
    });

    test('χωρίς συνδεδεμένο χρήστη δεν συμβαίνει τίποτα', () async {
      CurrentOperator.reset();
      announcements = 0;

      expect(await refreshCurrentOperatorProfile(db), isFalse);
      expect(announcements, 0);
    });
  });

  group('τι μετράει ως αλλαγή', () {
    Operator base() =>
        Operator(id: 7, displayName: 'Βλάσης', createdAt: DateTime(2026, 9, 1));

    test('ίδιο προφίλ, διαφορετικό αντικείμενο: καμία αλλαγή', () {
      // Το `Operator` δεν έχει ισότητα — κάθε ανάγνωση δίνει νέο αντικείμενο.
      // Αν αυτό μετρούσε ως αλλαγή, η ανανέωση θα μιλούσε σε κάθε πέρασμα.
      expect(operatorVisibleStateChanged(base(), base()), isFalse);
    });

    test('αλλαγή δικαιώματος μετράει', () {
      expect(
        operatorVisibleStateChanged(
          base(),
          base().copyWith(permissionOverrides: {'full_backup': true}),
        ),
        isTrue,
      );
    });

    test('αφαίρεση δικαιώματος μετράει', () {
      final withPermission = base().copyWith(
        permissionOverrides: {'full_backup': true},
      );
      expect(
        operatorVisibleStateChanged(
          withPermission,
          base().copyWith(permissionOverrides: const <String, bool>{}),
        ),
        isTrue,
      );
    });

    test('αντιστροφή τιμής στο ίδιο κλειδί μετράει', () {
      // Ίδιο πλήθος κλειδιών, αντίθετη απάντηση: μια σύγκριση μήκους θα το
      // έχανε ολόκληρο.
      expect(
        operatorVisibleStateChanged(
          base().copyWith(permissionOverrides: {'full_backup': true}),
          base().copyWith(permissionOverrides: {'full_backup': false}),
        ),
        isTrue,
      );
    });

    test('σήμανση διαχειριστή μετράει', () {
      expect(
        operatorVisibleStateChanged(base(), base().copyWith(isAdmin: true)),
        isTrue,
      );
    });

    test('απενεργοποίηση προφίλ μετράει', () {
      expect(
        operatorVisibleStateChanged(base(), base().copyWith(isActive: false)),
        isTrue,
      );
    });

    test(
      'μετονομασία και αλλαγή εικονιδίου μετρούν — φαίνονται στην οθόνη',
      () {
        expect(
          operatorVisibleStateChanged(
            base(),
            base().copyWith(displayName: 'Βλάσης Οικονόμου'),
          ),
          isTrue,
        );
        expect(
          operatorVisibleStateChanged(
            base(),
            base().copyWith(avatarKey: 'fox'),
          ),
          isTrue,
        );
      },
    );
  });
}
