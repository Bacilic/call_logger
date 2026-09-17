// Ποιος βλέπει το Ιστορικό Εφαρμογής — και ποιος δεν βλέπει καν το κουμπί.
//
// Το Ιστορικό Εφαρμογής δείχνει κάθε ενέργεια κάθε ανθρώπου, ονομαστικά. Είναι
// εργαλείο διάγνωσης, όχι καθημερινή δουλειά, και από 17/09/2026 ξεκινά
// **κλειστό**: μόνο ο διαχειριστής, ή όποιος πάρει ρητό τικ.
//
// Δύο πράγματα φυλάει αυτό το αρχείο:
// 1. Την κρίση «επιτρέπεται;» — το ένα σημείο απ' όπου ρωτούν όλες οι πύλες.
// 2. Ότι η **αφαίρεση** του δικαιώματος βγάζει κάποιον έξω από ανοιχτή προβολή.
//    Χωρίς αυτό, ο επόμενος που θα καθίσει μετά από «Αλλαγή χρήστη» θα έμενε
//    μέσα σε οθόνη που δεν δικαιούται.
//
//   flutter test test/features/history/application_audit_permission_test.dart

import 'package:call_logger/core/models/app_permission.dart';
import 'package:call_logger/core/models/operator.dart';
import 'package:call_logger/core/providers/history_audit_immersive_provider.dart';
import 'package:call_logger/core/services/current_operator.dart';
import 'package:call_logger/features/history/providers/history_application_audit_view_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_reporter.dart';

Operator _operator(
  int id, {
  bool isAdmin = false,
  Map<String, bool> overrides = const <String, bool>{},
}) => Operator(
  id: id,
  displayName: 'Χρήστης $id',
  isAdmin: isAdmin,
  permissionOverrides: overrides,
  createdAt: DateTime(2026, 9, 17),
);

const String _key = 'view_application_audit';

void main() {
  setUp(CurrentOperator.reset);
  tearDown(CurrentOperator.reset);

  group('Ποιος το βλέπει', () {
    test('χωρίς συνδεδεμένο χρήστη φαίνεται', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(applicationAuditVisibleProvider),
        isTrue,
        reason: greekExpectMsg(
          'Ζώνη ασφαλείας από λάθη, όχι κλειδαριά: χωρίς ταυτότητα τίποτα δεν '
          'κρύβεται — αλλιώς μια βάση χωρίς προφίλ θα έκρυβε τη διάγνωση από '
          'όλους',
        ),
      );
    });

    test('ο απλός χρήστης ΔΕΝ το βλέπει από προεπιλογή', () {
      CurrentOperator.activate(_operator(2));
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(applicationAuditVisibleProvider),
        isFalse,
        reason: greekExpectMsg(
          'Απόφαση 17/09/2026: ξεκινά κλειστό, ανοίγει με ρητό τικ',
        ),
      );
    });

    test('ο διαχειριστής το βλέπει χωρίς να χρειάζεται τικ', () {
      CurrentOperator.activate(_operator(1, isAdmin: true));
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(applicationAuditVisibleProvider), isTrue);
    });

    test('με ρητό τικ το βλέπει και ο απλός χρήστης', () {
      CurrentOperator.activate(
        _operator(2, overrides: <String, bool>{_key: true}),
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(applicationAuditVisibleProvider), isTrue);
    });

    test('το κλειδί του δικαιώματος δεν άλλαξε όνομα', () {
      // Τα αποθηκευμένα προφίλ το αναφέρουν ονομαστικά: μια μετονομασία θα
      // έσβηνε σιωπηλά κάθε τικ που έχει δώσει ο διαχειριστής.
      expect(AppPermission.viewApplicationAudit.key, _key);
      expect(AppPermission.viewApplicationAudit.allowedByDefault, isFalse);
    });
  });

  group('Η αλλαγή χρήστη βγάζει έξω όποιον δεν δικαιούται', () {
    /// Καλεί την **πραγματική** συνάρτηση που τρέχει στην αλλαγή χρήστη —
    /// όχι αντίγραφο της λογικής της. Αν αύριο αλλάξει ο κανόνας εκεί, αυτός ο
    /// έλεγχος το μαθαίνει· ένα αντίγραφο θα έμενε πράσινο και μόνο του.
    void closeIfNotAllowed(ProviderContainer container) {
      closeApplicationAuditIfNotAllowed(
        allowed: container.read(applicationAuditVisibleProvider),
        view: container.read(historyApplicationAuditViewProvider.notifier),
        immersive: container.read(historyAuditImmersiveProvider.notifier),
      );
    }

    test('ο επόμενος δεν μένει μέσα στην ανοιχτή προβολή', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Ο διαχειριστής άνοιξε το Ιστορικό Εφαρμογής, σε πλήρη οθόνη.
      CurrentOperator.activate(_operator(1, isAdmin: true));
      container.read(historyApplicationAuditViewProvider.notifier).set(true);
      container.read(historyAuditImmersiveProvider.notifier).setTrue();
      expect(container.read(historyApplicationAuditViewProvider), isTrue);

      // «Αλλαγή χρήστη» σε κάποιον χωρίς το δικαίωμα.
      CurrentOperator.activate(_operator(2));
      container.invalidate(applicationAuditVisibleProvider);
      closeIfNotAllowed(container);

      expect(
        container.read(historyApplicationAuditViewProvider),
        isFalse,
        reason: greekExpectMsg(
          'Αλλιώς θα καθόταν σε οθόνη που δεν δικαιούται, με το κουμπί '
          'επιστροφής ορατό και το κουμπί ανοίγματος κρυμμένο',
        ),
      );
      expect(container.read(historyAuditImmersiveProvider), isFalse);
    });

    test('όποιος δικαιούται μένει εκεί που ήταν', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      CurrentOperator.activate(_operator(1, isAdmin: true));
      container.read(historyApplicationAuditViewProvider.notifier).set(true);

      // Αλλαγή σε άλλον διαχειριστή: καμία διακοπή στη δουλειά του.
      CurrentOperator.activate(_operator(3, isAdmin: true));
      container.invalidate(applicationAuditVisibleProvider);
      closeIfNotAllowed(container);

      expect(container.read(historyApplicationAuditViewProvider), isTrue);
    });
  });
}
