import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/core/utils/phone_list_parser.dart';
import 'package:call_logger/features/calls/models/equipment_model.dart';
import 'package:call_logger/features/calls/models/user_model.dart';
import 'package:call_logger/features/calls/provider/smart_entity_selector_provider.dart';
import 'package:call_logger/features/calls/screens/widgets/smart_entity_equipment_initial_suggestions.dart';
import 'package:call_logger/features/calls/screens/widgets/smart_entity_selector_equipment_models.dart';
import 'package:call_logger/features/directory/models/department_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_reporter.dart';

/*
 * Αρχικές προτάσεις εξοπλισμού — sourceLabel για εξοπλισμό καλούντα (όχι τηλέφωνο).
 *
 * Ολόκληρο αρχείο:
 *   flutter test test/features/calls/smart_entity_equipment_initial_suggestions_test.dart
 */

const _kDepartmentId = 1;
const _kDepartmentName = 'Τμήμα Δοκιμών';
const _kOwnerUserId = 10;
const _kOwnerFirstName = 'Γιάννης';
const _kOwnerLastName = 'Παπαδόπουλος';
const _kOwnedEquipmentId = 100;
const _kOwnedEquipmentCode = 'PC-USER';
const _kSharedEquipmentId = 200;
const _kSharedEquipmentCode = 'PC-SHARED';

UserModel _ownerUser() {
  return UserModel(
    id: _kOwnerUserId,
    firstName: _kOwnerFirstName,
    lastName: _kOwnerLastName,
    departmentId: _kDepartmentId,
  );
}

EquipmentModel _ownedEquipment() {
  return EquipmentModel(
    id: _kOwnedEquipmentId,
    code: _kOwnedEquipmentCode,
    type: 'PC',
  );
}

EquipmentModel _sharedDepartmentEquipment() {
  return EquipmentModel(
    id: _kSharedEquipmentId,
    code: _kSharedEquipmentCode,
    type: 'PC',
    departmentId: _kDepartmentId,
  );
}

LookupService _lookupWithDepartmentCatalog() {
  final lookup = LookupService.forTest();
  lookup.injectInMemoryCatalogForTests(
    users: [_ownerUser()],
    equipment: [_ownedEquipment(), _sharedDepartmentEquipment()],
    departmentRows: [
      DepartmentModel(id: _kDepartmentId, name: _kDepartmentName),
    ],
    userToEquipmentIds: {
      _kOwnerUserId: [_kOwnedEquipmentId],
    },
  );
  return lookup;
}

String? _sourceLabelForCode(
  List<SmartEntityEquipmentSuggestion> suggestions,
  String code,
) {
  for (final suggestion in suggestions) {
    if (suggestion.equipment.code == code) {
      return suggestion.sourceLabel;
    }
  }
  return null;
}

void main() {
  group('Αρχικές προτάσεις εξοπλισμού — sourceLabel καλούντα', () {
    late LookupService lookup;

    setUp(() {
      lookup = _lookupWithDepartmentCatalog();
    });

    test(
      'εξοπλισμός χρήστη και κοινόχρηστος τμήματος δείχνουν σωστή πηγή (όχι «Όνομα»)',
      () {
        final header = SmartEntitySelectorState(
          equipmentCandidates: [
            _ownedEquipment(),
            _sharedDepartmentEquipment(),
          ],
        );

        final suggestions = buildInitialEquipmentSuggestions(header, lookup);

        expect(
          suggestions,
          hasLength(2),
          reason: greekExpectMsg(
            'Και οι δύο εγγραφές εξοπλισμού εμφανίζονται στις αρχικές προτάσεις',
          ),
        );

        expect(
          _sourceLabelForCode(suggestions, _kOwnedEquipmentCode),
          '$_kOwnerFirstName $_kOwnerLastName',
          reason: greekExpectMsg(
            'Ο εξοπλισμός με κάτοχο εμφανίζει το ονοματεπώνυμο του χρήστη',
          ),
        );
        expect(
          _sourceLabelForCode(suggestions, _kSharedEquipmentCode),
          'Κοινόχρηστο',
          reason: greekExpectMsg(
            'Ο κοινόχρηστος εξοπλισμός τμήματος χωρίς κάτοχο εμφανίζει «Κοινόχρηστο»',
          ),
        );
      },
    );

    test(
      'εξοπλισμός με πολλαπλούς κατόχους ενώνει τα ονοματεπώνυμα με κόμμα',
      () {
        const secondOwnerId = 11;
        lookup.injectInMemoryCatalogForTests(
          users: [
            _ownerUser(),
            UserModel(
              id: secondOwnerId,
              firstName: 'Μαρία',
              lastName: 'Δοκίμου',
              departmentId: _kDepartmentId,
            ),
          ],
          equipment: [_ownedEquipment()],
          departmentRows: [
            DepartmentModel(id: _kDepartmentId, name: _kDepartmentName),
          ],
          userToEquipmentIds: {
            _kOwnerUserId: [_kOwnedEquipmentId],
            secondOwnerId: [_kOwnedEquipmentId],
          },
        );

        final header = SmartEntitySelectorState(
          equipmentCandidates: [_ownedEquipment()],
        );
        final suggestions = buildInitialEquipmentSuggestions(header, lookup);

        expect(
          _sourceLabelForCode(suggestions, _kOwnedEquipmentCode),
          '$_kOwnerFirstName $_kOwnerLastName, Μαρία Δοκίμου',
          reason: greekExpectMsg(
            'Πολλαπλοί κάτοχοι εμφανίζονται ως λίστα ονομάτων διαχωρισμένη με κόμμα',
          ),
        );
      },
    );

    test(
      'κοινόχρηστος εξοπλισμός με κάτοχο υπερισχύει το ονοματεπώνυμο του υπαλλήλου',
      () {
        final sharedWithOwner = EquipmentModel(
          id: 300,
          code: 'PC-MIXED',
          type: 'PC',
          departmentId: _kDepartmentId,
        );
        lookup.injectInMemoryCatalogForTests(
          users: [_ownerUser()],
          equipment: [sharedWithOwner],
          departmentRows: [
            DepartmentModel(id: _kDepartmentId, name: _kDepartmentName),
          ],
          userToEquipmentIds: {
            _kOwnerUserId: [300],
          },
        );

        final header = SmartEntitySelectorState(
          equipmentCandidates: [sharedWithOwner],
        );
        final suggestions = buildInitialEquipmentSuggestions(header, lookup);

        expect(
          _sourceLabelForCode(suggestions, 'PC-MIXED'),
          '$_kOwnerFirstName $_kOwnerLastName',
          reason: greekExpectMsg(
            'Όταν υπάρχει κάτοχος, δεν εμφανίζεται «Κοινόχρηστο» ακόμη κι αν έχει department_id',
          ),
        );
      },
    );

    test(
      'εξοπλισμός μόνο από τηλέφωνο διατηρεί ετικέτα «Τηλέφωνο»',
      () {
        final userWithPhone = UserModel(
          id: 20,
          firstName: 'Τηλ',
          lastName: 'Φωνο',
          phones: PhoneListParser.splitPhones('2101234567'),
          departmentId: _kDepartmentId,
        );
        final phoneEquipment = EquipmentModel(
          id: 400,
          code: 'PC-PHONE',
          type: 'PC',
        );
        lookup.injectInMemoryCatalogForTests(
          users: [userWithPhone],
          equipment: [phoneEquipment],
          departmentRows: [
            DepartmentModel(id: _kDepartmentId, name: _kDepartmentName),
          ],
          userToEquipmentIds: {20: [400]},
        );

        final header = SmartEntitySelectorState(
          selectedPhone: '2101234567',
        );
        final suggestions = buildInitialEquipmentSuggestions(header, lookup);

        expect(
          _sourceLabelForCode(suggestions, 'PC-PHONE'),
          'Τηλέφωνο',
          reason: greekExpectMsg(
            'Η ροή τηλεφώνου δεν επηρεάζεται από τη διόρθωση καλούντα',
          ),
        );
      },
    );
  });
}
