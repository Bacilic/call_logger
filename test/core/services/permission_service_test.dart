import 'package:call_logger/core/models/app_permission.dart';
import 'package:call_logger/core/models/operator.dart';
import 'package:call_logger/core/services/current_operator.dart';
import 'package:call_logger/core/services/permission_service.dart';
import 'package:flutter_test/flutter_test.dart';

Operator _operator(
  int id, {
  bool isAdmin = false,
  Map<String, bool> overrides = const <String, bool>{},
}) => Operator(
  id: id,
  displayName: 'Χρήστης $id',
  isAdmin: isAdmin,
  permissionOverrides: overrides,
  createdAt: DateTime(2026, 8, 21),
);

void main() {
  const gate = PermissionService.instance;

  setUp(CurrentOperator.reset);
  tearDown(CurrentOperator.reset);

  group('Χωρίς συνδεδεμένο χρήστη', () {
    test('όλα επιτρέπονται, ακόμη και όσα έχουν προεπιλογή «όχι»', () {
      for (final permission in AppPermission.values) {
        expect(
          gate.can(permission),
          isTrue,
          reason:
              'Τα δικαιώματα είναι ζώνη ασφαλείας από λάθη, όχι κλειδαριά: '
              'χωρίς ταυτότητα κανείς δεν κλειδώνεται έξω από την εφαρμογή. '
              'Έσπασε στο «${permission.label}».',
        );
      }
    });
  });

  group('Διαχειριστής', () {
    test('περνά χωρίς να κοιταχτεί η λίστα', () {
      CurrentOperator.activate(_operator(1, isAdmin: true));
      expect(gate.can(AppPermission.fullBackup), isTrue);
    });

    test('ρητή άρνηση στη λίστα του ΔΕΝ τον σταματά', () {
      CurrentOperator.activate(
        _operator(
          1,
          isAdmin: true,
          overrides: {AppPermission.browseDatabase.key: false},
        ),
      );
      expect(gate.can(AppPermission.browseDatabase), isTrue);
    });
  });

  group('Απλός χρήστης', () {
    test('χωρίς παράκαμψη ακολουθεί την προεπιλογή του δικαιώματος', () {
      CurrentOperator.activate(_operator(2));
      expect(gate.can(AppPermission.browseDatabase), isTrue);
      expect(gate.can(AppPermission.fullBackup), isFalse);
    });

    test('ρητή άρνηση κερδίζει προεπιλογή «ναι»', () {
      CurrentOperator.activate(
        _operator(2, overrides: {AppPermission.browseDatabase.key: false}),
      );
      expect(gate.can(AppPermission.browseDatabase), isFalse);
    });

    test('ρητή άδεια κερδίζει προεπιλογή «όχι»', () {
      CurrentOperator.activate(
        _operator(2, overrides: {AppPermission.fullBackup.key: true}),
      );
      expect(gate.can(AppPermission.fullBackup), isTrue);
    });

    test('παράκαμψη άλλου δικαιώματος δεν επηρεάζει το ζητούμενο', () {
      CurrentOperator.activate(
        _operator(
          2,
          overrides: {AppPermission.manageEquipmentTypes.key: false},
        ),
      );
      expect(gate.can(AppPermission.browseDatabase), isTrue);
    });
  });

  group('Διαχείριση χρηστών — μόνο ο διαχειριστής', () {
    test('χωρίς ταυτότητα επιτρέπεται', () {
      expect(
        gate.canManageOperators(),
        isTrue,
        reason:
            'Σε άδεια ή άγνωστη βάση κάποιος πρέπει να μπορεί να στήσει τα '
            'προφίλ — αλλιώς δεν θα υπήρχε ποτέ πρώτος διαχειριστής.',
      );
    });

    test('ο διαχειριστής επιτρέπεται', () {
      CurrentOperator.activate(_operator(1, isAdmin: true));
      expect(gate.canManageOperators(), isTrue);
    });

    test('ο απλός χρήστης ΔΕΝ επιτρέπεται', () {
      CurrentOperator.activate(_operator(2));
      expect(gate.canManageOperators(), isFalse);
    });

    test('κανένα τικ του καταλόγου δεν το ξεκλειδώνει', () {
      // Αν αρκούσε ένα τικ, όποιος το έπαιρνε θα μπορούσε να δώσει στον εαυτό
      // του και όλα τα υπόλοιπα — το τικ θα ισοδυναμούσε σιωπηλά με «όλα».
      final everything = <String, bool>{
        for (final permission in AppPermission.values) permission.key: true,
      };
      CurrentOperator.activate(_operator(2, overrides: everything));
      expect(gate.canManageOperators(), isFalse);
    });
  });

  test('ο ρητός χρήστης του ορίσματος υπερισχύει του συνδεδεμένου', () {
    CurrentOperator.activate(_operator(1, isAdmin: true));
    final other = _operator(
      2,
      overrides: {AppPermission.browseDatabase.key: false},
    );
    expect(gate.can(AppPermission.browseDatabase, operator: other), isFalse);
  });

  group('Ο κατάλογος', () {
    test('μοναδική προεπιλεγμένη απαγόρευση: το πλήρες αντίγραφο', () {
      // Φυλάει ότι δεν θα γλιστρήσει σιωπηλά δεύτερη προεπιλεγμένη απαγόρευση.
      // Κάθε νέα θα άλλαζε τη συμπεριφορά όλων των υπαρχόντων προφίλ μονομιάς,
      // αφού αποθηκεύονται μόνο οι παρακάμψεις.
      for (final permission in AppPermission.values) {
        expect(
          permission.allowedByDefault,
          permission == AppPermission.fullBackup ? isFalse : isTrue,
          reason: permission.key,
        );
      }
    });

    test('κάθε δικαίωμα του καταλόγου επιβάλλεται όντως', () {
      // Απόφαση 21/08/2026: ό,τι δεν πρόκειται να επιβληθεί δεν μπαίνει στον
      // κατάλογο. Το πού μπαίνει ο έλεγχος το φυλάει το
      // app_permission_enforcement_test· εδώ φυλάγεται η ίδια η δήλωση.
      expect(
        AppPermission.notYetEnforced,
        isEmpty,
        reason:
            'Τικ που δεν ισχύει είναι υπόσχεση που δεν τηρείται. Είτε βάλτε '
            'σημείο ελέγχου, είτε βγάλτε το δικαίωμα από τον κατάλογο.',
      );
    });
  });

  group('Αποθηκευμένο περιεχόμενο', () {
    test('άγνωστο κλειδί αγνοείται αντί να ρίξει την εφαρμογή', () {
      // Συμβαίνει κανονικά: δικαιώματα που αφαιρέθηκαν επιβιώνουν σε παλιά
      // προφίλ, και μια νεότερη έκδοση μπορεί να έγραψε κλειδιά που η τρέχουσα
      // δεν γνωρίζει.
      final stored = decodePermissionOverrides('{"κλειδι_που_εφυγε": false}');
      CurrentOperator.activate(_operator(2, overrides: stored));

      expect(gate.can(AppPermission.browseDatabase), isTrue);
    });

    test('χαλασμένο περιεχόμενο δίνει προεπιλογές, όχι σφάλμα', () {
      expect(decodePermissionOverrides('όχι-json'), isEmpty);
      expect(decodePermissionOverrides(null), isEmpty);
      expect(decodePermissionOverrides('[]'), isEmpty);
    });
  });
}
