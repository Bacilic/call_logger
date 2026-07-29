// Ο κάτοχος εξοπλισμού δένει ΜΟΝΟ σε υπαρκτό υπάλληλο: καμία σιωπηλή
// δημιουργία, καμία «μαντεψιά πρώτου αποτελέσματος», ρητή στάση σε συνωνυμία.
//
//   flutter test test/features/directory/equipment_owner_binding_test.dart

import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/core/utils/phone_list_parser.dart';
import 'package:call_logger/features/calls/models/user_model.dart';
import 'package:call_logger/features/directory/models/department_model.dart';
import 'package:call_logger/features/directory/screens/widgets/equipment_form_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

const _kGrammateia = 10;
const _kMageireio = 20;

UserModel _user(int id, String first, String last, {int? deptId}) => UserModel(
  id: id,
  firstName: first,
  lastName: last,
  departmentId: deptId,
  phones: PhoneListParser.splitPhones(''),
);

/// Κατάλογος: ένας μοναδικός υπάλληλος + δύο ομώνυμοι σε διαφορετικά τμήματα.
LookupService _catalog() {
  final svc = LookupService.instance;
  svc.resetForReload();
  svc.injectInMemoryCatalogForTests(
    users: [
      _user(1, 'Αλεξάνδρα', 'Νικολάου', deptId: _kGrammateia),
      _user(2, 'Γιώργος', 'Παππάς', deptId: _kGrammateia),
      _user(3, 'Γιώργος', 'Παππάς', deptId: _kMageireio),
    ],
    equipment: const [],
    departmentRows: [
      DepartmentModel(id: _kGrammateia, name: 'Γραμματεία'),
      DepartmentModel(id: _kMageireio, name: 'Μαγειρείο'),
    ],
  );
  return svc;
}

/// Το State της φόρμας εκθέτει το `resolveOwnerBinding` — το ίδιο που καλεί
/// η αποθήκευση στην παραγωγή.
EquipmentFormDialogState _formState() => EquipmentFormDialogState();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Δέσιμο κατόχου εξοπλισμού', () {
    test('κενό κείμενο → χωρίς κάτοχο, χωρίς σφάλμα', () {
      final result = _formState().resolveOwnerBinding('   ', _catalog());
      expect(result.userId, isNull);
      expect(result.error, isNull);
    });

    test('ακριβές μοναδικό όνομα → δένει στον σωστό υπάλληλο', () {
      final result = _formState().resolveOwnerBinding(
        'Αλεξάνδρα Νικολάου',
        _catalog(),
      );
      expect(result.userId, 1);
      expect(result.error, isNull);
    });

    test('όνομα με «(Τμήμα)» από τη λίστα → δένει κανονικά', () {
      final result = _formState().resolveOwnerBinding(
        'Αλεξάνδρα Νικολάου (Γραμματεία)',
        _catalog(),
      );
      expect(result.userId, 1);
      expect(result.error, isNull);
    });

    test('τυπογραφικό λάθος → ΣΤΑΜΑΤΑ, δεν δημιουργεί υπάλληλο', () {
      final catalog = _catalog();
      final before = catalog.users.length;

      final result = _formState().resolveOwnerBinding('Αλεξάνδραα', catalog);

      expect(result.userId, isNull);
      expect(result.error, contains('Δεν υπάρχει υπάλληλος'));
      expect(
        catalog.users.length,
        before,
        reason: 'Καμία σιωπηλή δημιουργία υπαλλήλου-φαντάσματος',
      );
    });

    test('μερικό όνομα → ΣΤΑΜΑΤΑ, δεν μαντεύει το πρώτο αποτέλεσμα', () {
      // Το «Παππ» ταιριάζει σε δύο υπαλλήλους στην αναζήτηση· η παλιά λογική
      // επέστρεφε σιωπηλά τον πρώτο.
      final result = _formState().resolveOwnerBinding('Παππ', _catalog());
      expect(result.userId, isNull);
      expect(result.error, isNotNull);
    });

    test('συνωνυμία χωρίς επιλογή από λίστα → ΣΤΑΜΑΤΑ με σαφές μήνυμα', () {
      final result = _formState().resolveOwnerBinding(
        'Γιώργος Παππάς',
        _catalog(),
      );
      expect(result.userId, isNull);
      expect(result.error, contains('2 υπάλληλοι'));
      expect(result.error, contains('από τη λίστα'));
    });

    test('συνωνυμία ΜΕ επιλογή από λίστα → δένει στον επιλεγμένο', () {
      final state = _formState()..selectedUserId = 3;
      final result = state.resolveOwnerBinding('Γιώργος Παππάς', _catalog());
      expect(
        result.userId,
        3,
        reason: 'Η ρητή επιλογή από τη λίστα ξεχωρίζει τους ομώνυμους',
      );
      expect(result.error, isNull);
    });

    test('κατάλογος που δεν φόρτωσε → ΣΤΑΜΑΤΑ αντί για σιωπηλό null', () {
      final result = _formState().resolveOwnerBinding('Οποιοσδήποτε', null);
      expect(result.userId, isNull);
      expect(result.error, isNotNull);
    });
  });
}
