import 'package:call_logger/core/database/old_database/lamp_cross_check_snapshot.dart';
import 'package:call_logger/features/calls/models/equipment_model.dart';
import 'package:call_logger/features/calls/models/user_model.dart';
import 'package:call_logger/features/directory/models/department_model.dart';
import 'package:call_logger/features/directory/models/lamp_cross_check_finding.dart';
import 'package:call_logger/features/directory/models/lamp_cross_check_rules.dart';
import 'package:call_logger/features/directory/services/lamp_cross_check_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Η διασταύρωση Καταλόγου και Λάμπας: τι θεωρείται απόκλιση, τι σιωπά, και
/// τι λέει η κάθε πλευρά στο εύρημα.
void main() {
  // Πώς γράφτηκε η «Άννα» στη Λάμπα: το κεφαλαίο άλφα με τόνο χάλασε στην
  // παλιά εξαγωγή και έγινε τροποποιητής αποστρόφου. Ο χαρακτήρας μπαίνει ως
  // κωδικός, ώστε να μη χαθεί σε καμία μετατροπή αρχείου.
  const lampAnna = '\u02BCννα';
  LampOwnerRecord owner(
    int id,
    String last,
    String first, {
    int? officeId,
    List<String> phones = const [],
  }) {
    return LampOwnerRecord(
      id: id,
      lastName: last,
      firstName: first,
      officeId: officeId,
      phones: phones,
    );
  }

  LampOfficeRecord office(int id, String name, {List<String> phones = const []}) {
    return LampOfficeRecord(
      id: id,
      name: name,
      departmentName: '',
      phones: phones,
    );
  }

  LampEquipmentRecord machine(
    int code, {
    int? ownerId,
    int? officeId,
    String state = 'Σε λειτουργία',
    String category = '',
  }) {
    return LampEquipmentRecord(
      code: code,
      ownerId: ownerId,
      officeId: officeId,
      stateName: state,
      categoryName: category,
    );
  }

  /// Το σύνορο του μητρώου βγαίνει μόνο του από τα μηχανήματα, όπως και στην
  /// πραγματική ανάγνωση της βάσης.
  LampCrossCheckSnapshot snapshot({
    List<LampOfficeRecord> offices = const [],
    List<LampOwnerRecord> owners = const [],
    List<LampEquipmentRecord> equipment = const [],
  }) {
    return LampCrossCheckSnapshot(
      offices: {for (final o in offices) o.id: o},
      owners: {for (final o in owners) o.id: o},
      equipmentByCode: {for (final e in equipment) '${e.code}': e},
      lastEquipmentCode: equipment.isEmpty
          ? null
          : equipment.map((e) => e.code).reduce((a, b) => a > b ? a : b),
    );
  }

  List<LampCrossCheckFinding> compare(
    LampCrossCheckRules rules, {
    List<UserModel> users = const [],
    List<DepartmentModel> departments = const [],
    List<EquipmentModel> equipment = const [],
    required LampCrossCheckSnapshot lamp,
    Map<int, List<String>> sharedPhones = const {},
    Map<int, List<int>> owners = const {},
  }) {
    return LampCrossCheckService(rules).compare(
      users: users,
      departments: departments,
      equipment: equipment,
      snapshot: lamp,
      sharedPhonesByDepartmentId: sharedPhones,
      ownerUserIdsByEquipmentId: owners,
    );
  }

  group('υπάλληλοι', () {
    test('διαφορετική γραφή ονόματος: εύρημα με τις δύο πλευρές', () {
      final findings = compare(
        const LampCrossCheckRules(),
        users: [UserModel(id: 1, lastName: 'Πατσαρίκα', firstName: 'Άννα')],
        lamp: snapshot(
          owners: [owner(10, 'Πατσαρίκα', lampAnna)],
        ),
      );
      final finding = findings.single;
      expect(finding.kind, LampCrossCheckKind.userNameSpelling);
      expect(finding.catalogValue, 'Πατσαρίκα Άννα');
      expect(finding.lampValue, 'Πατσαρίκα $lampAnna');
      expect(finding.entityId, 1);
      expect(finding.focusedField, 'lastName');
    });

    test('κλειστός διακόπτης: καμία γραμμή για την ίδια απόκλιση', () {
      final findings = compare(
        const LampCrossCheckRules(userNameSpellingEnabled: false),
        users: [UserModel(id: 1, lastName: 'Πατσαρίκα', firstName: 'Άννα')],
        lamp: snapshot(
          owners: [owner(10, 'Πατσαρίκα', lampAnna)],
        ),
      );
      expect(findings, isEmpty);
    });

    test('σκέτη διαφορά τόνου δεν είναι απόκλιση', () {
      final findings = compare(
        const LampCrossCheckRules(),
        users: [UserModel(id: 1, lastName: 'Πατσαρίκα', firstName: 'Άννα')],
        lamp: snapshot(owners: [owner(10, 'Πατσαρικα', 'Αννα')]),
      );
      expect(findings, isEmpty);
    });

    test('απών από τη Λάμπα: σιωπά στις προεπιλογές, μιλά όταν ανάψει', () {
      final user = UserModel(id: 1, lastName: 'Νομικού', firstName: 'Τίνα');
      expect(
        compare(const LampCrossCheckRules(), users: [user], lamp: snapshot()),
        isEmpty,
      );
      final findings = compare(
        const LampCrossCheckRules(userMissingInLampEnabled: true),
        users: [user],
        lamp: snapshot(),
      );
      expect(findings.single.kind, LampCrossCheckKind.userMissing);
      expect(findings.single.lampValue, isNull);
    });

    test('άλλο τμήμα στις δύο βάσεις: εύρημα με τα δύο ονόματα', () {
      final findings = compare(
        const LampCrossCheckRules(userDepartmentEnabled: true),
        users: [
          UserModel(
            id: 1,
            lastName: 'Ψαρρά',
            firstName: 'Σοφία',
            departmentId: 5,
          ),
        ],
        departments: [DepartmentModel(id: 5, name: 'Γραμματεία ΤΕΠ')],
        lamp: snapshot(
          offices: [office(20, 'Αιματολογικό')],
          owners: [owner(10, 'Ψαρρά', 'Σοφία', officeId: 20)],
        ),
      );
      final finding = findings.single;
      expect(finding.kind, LampCrossCheckKind.userDepartment);
      expect(finding.catalogValue, 'Γραμματεία ΤΕΠ');
      expect(finding.lampValue, 'Αιματολογικό');
    });

    test('κενό τμήμα στη μία πλευρά δεν είναι απόκλιση', () {
      final findings = compare(
        const LampCrossCheckRules(userDepartmentEnabled: true),
        users: [UserModel(id: 1, lastName: 'Ψαρρά', firstName: 'Σοφία')],
        lamp: snapshot(
          offices: [office(20, 'Αιματολογικό')],
          owners: [owner(10, 'Ψαρρά', 'Σοφία', officeId: 20)],
        ),
      );
      expect(findings, isEmpty);
    });

    test('οι δύο κατευθύνσεις τηλεφώνου ανάβουν ξεχωριστά', () {
      final user = UserModel(
        id: 1,
        lastName: 'Ψαρρά',
        firstName: 'Σοφία',
        phones: const ['2534'],
      );
      final lamp = snapshot(
        owners: [owner(10, 'Ψαρρά', 'Σοφία', phones: const ['2565'])],
      );

      final onlyLamp = compare(
        const LampCrossCheckRules(userPhoneOnlyInLampEnabled: true),
        users: [user],
        lamp: lamp,
      );
      expect(onlyLamp.single.kind, LampCrossCheckKind.userPhoneOnlyInLamp);
      expect(onlyLamp.single.lampValue, '2565');

      final onlyCatalog = compare(
        const LampCrossCheckRules(userPhoneOnlyInCatalogEnabled: true),
        users: [user],
        lamp: lamp,
      );
      expect(
        onlyCatalog.single.kind,
        LampCrossCheckKind.userPhoneOnlyInCatalog,
      );
      expect(onlyCatalog.single.catalogValue, '2534');
    });
  });

  group('εξοπλισμός', () {
    test('κωδικός που λείπει από τη Λάμπα: εύρημα με μία πλευρά', () {
      final findings = compare(
        const LampCrossCheckRules(),
        equipment: [EquipmentModel(id: 7, code: '5151')],
        // Το μητρώο φτάνει πιο ψηλά από τον κωδικό: η απουσία είναι αληθινή.
        lamp: snapshot(equipment: [machine(3257), machine(5200)]),
      );
      final finding = findings.single;
      expect(finding.kind, LampCrossCheckKind.equipmentMissing);
      expect(finding.title, contains('5151'));
      expect(finding.lampValue, isNull);
      expect(finding.focusedField, 'code');
      // Ο κωδικός λέγεται ήδη στον τίτλο και στην ετικέτα· η πλευρά του
      // Καταλόγου κρατά ό,τι ΑΛΛΟ ξέρει, και το λέει όταν δεν ξέρει τίποτα.
      expect(finding.catalogValue, 'Χωρίς είδος και τμήμα');
    });

    test('όταν υπάρχουν είδος και τμήμα, η πλευρά του Καταλόγου τα δείχνει', () {
      final findings = compare(
        const LampCrossCheckRules(),
        departments: [DepartmentModel(id: 5, name: 'Ακτινολογικό')],
        equipment: [
          EquipmentModel(
            id: 7,
            code: '5151',
            type: 'Εκτυπωτής',
            departmentId: 5,
          ),
        ],
        lamp: snapshot(),
      );
      expect(findings.single.catalogValue, 'Εκτυπωτής · Ακτινολογικό');
    });

    test('κωδικός πάνω από τον τελευταίο της Λάμπας: καμία γραμμή', () {
      final findings = compare(
        const LampCrossCheckRules(),
        equipment: [EquipmentModel(id: 7, code: '5151')],
        lamp: snapshot(equipment: [machine(5126)]),
      );
      // Καταγράφηκε αφότου η Λάμπα πάγωσε — δεν επρόκειτο ποτέ να βρεθεί εκεί.
      expect(findings, isEmpty);
    });

    test('ο ίδιος ο τελευταίος κωδικός εξακολουθεί να ελέγχεται', () {
      final findings = compare(
        const LampCrossCheckRules(),
        equipment: [EquipmentModel(id: 7, code: '5126')],
        lamp: snapshot(equipment: [machine(5126, state: 'Καταστράφηκε')]),
      );
      // Το σύνορο δεν σβήνει τους ελέγχους πάνω σε ό,τι υπάρχει στο μητρώο.
      expect(findings.single.kind, LampCrossCheckKind.equipmentRetired);
    });

    test('κωδικός που δεν είναι αριθμός δεν σιωπά από το σύνορο', () {
      final findings = compare(
        const LampCrossCheckRules(),
        equipment: [EquipmentModel(id: 7, code: '5151α')],
        lamp: snapshot(equipment: [machine(5126)]),
      );
      // Ακριβώς η λάθος πληκτρολόγηση που ψάχνει ο έλεγχος.
      expect(findings.single.kind, LampCrossCheckKind.equipmentMissing);
    });

    test('εκτός χρήσης στη Λάμπα: εύρημα με την κατάσταση', () {
      final findings = compare(
        const LampCrossCheckRules(),
        equipment: [EquipmentModel(id: 7, code: '3257')],
        lamp: snapshot(equipment: [machine(3257, state: 'Καταστράφηκε')]),
      );
      expect(findings.single.kind, LampCrossCheckKind.equipmentRetired);
      expect(findings.single.lampValue, 'Καταστράφηκε');
    });

    test('προσωρινή κατάσταση δεν μετρά ως απόσυρση', () {
      final findings = compare(
        const LampCrossCheckRules(),
        equipment: [EquipmentModel(id: 7, code: '3257')],
        lamp: snapshot(equipment: [machine(3257, state: 'Προς επισκευή')]),
      );
      expect(findings, isEmpty);
    });

    test('διαφορετικό είδος: εύρημα· ίδιο είδος: σιωπή', () {
      final findings = compare(
        const LampCrossCheckRules(),
        equipment: [EquipmentModel(id: 7, code: '3257', type: 'Εκτυπωτής')],
        lamp: snapshot(
          equipment: [machine(3257, category: 'Υπολογιστής')],
        ),
      );
      expect(findings.single.kind, LampCrossCheckKind.equipmentType);

      expect(
        compare(
          const LampCrossCheckRules(),
          equipment: [EquipmentModel(id: 7, code: '3257', type: 'Εκτυπωτής')],
          lamp: snapshot(equipment: [machine(3257, category: 'Εκτυπωτής')]),
        ),
        isEmpty,
      );
    });

    test('άλλος κάτοχος: εύρημα με τα δύο ονόματα', () {
      final findings = compare(
        const LampCrossCheckRules(equipmentOwnerEnabled: true),
        users: [
          UserModel(id: 1, lastName: 'Ψαρρά', firstName: 'Σοφία'),
        ],
        equipment: [EquipmentModel(id: 7, code: '3257')],
        lamp: snapshot(
          owners: [
            owner(10, 'Ψαρρά', 'Σοφία'),
            owner(11, 'Κοτρότσος', 'Νίκος'),
          ],
          equipment: [machine(3257, ownerId: 11)],
        ),
        owners: const {
          7: [1],
        },
      );
      final finding = findings.single;
      expect(finding.kind, LampCrossCheckKind.equipmentOwner);
      expect(finding.catalogValue, 'Ψαρρά Σοφία');
      expect(finding.lampValue, 'Κοτρότσος Νίκος');
    });

    test('διαφορά μόνο στη γραφή δεν παριστάνει αλλαγή κατόχου', () {
      final findings = compare(
        const LampCrossCheckRules(
          equipmentOwnerEnabled: true,
          userNameSpellingEnabled: false,
        ),
        users: [
          UserModel(id: 1, lastName: 'Πατσαρίκα', firstName: 'Άννα'),
        ],
        equipment: [EquipmentModel(id: 7, code: '3257')],
        lamp: snapshot(
          owners: [owner(10, 'Πατσαρίκα', lampAnna)],
          equipment: [machine(3257, ownerId: 10)],
        ),
        owners: const {
          7: [1],
        },
      );
      expect(findings, isEmpty);
    });
  });

  group('τμήματα', () {
    test('τηλέφωνο που ξέρει μόνο η Λάμπα', () {
      final findings = compare(
        const LampCrossCheckRules(departmentPhoneOnlyInLampEnabled: true),
        departments: [DepartmentModel(id: 5, name: 'Αιματολογικό')],
        lamp: snapshot(
          offices: [office(20, 'Αιματολογικό', phones: const ['2565'])],
        ),
        sharedPhones: const {
          5: ['2534'],
        },
      );
      final finding = findings.single;
      expect(finding.kind, LampCrossCheckKind.departmentPhoneOnlyInLamp);
      expect(finding.lampValue, '2565');
      expect(finding.focusedField, 'phones');
    });

    test('τμήμα που δεν βρέθηκε: σιωπά στις προεπιλογές', () {
      expect(
        compare(
          const LampCrossCheckRules(),
          departments: [DepartmentModel(id: 5, name: 'Γραφείο Κίνησης')],
          lamp: snapshot(offices: [office(20, 'Αιματολογικό')]),
        ),
        isEmpty,
      );
    });
  });

  test('όλοι οι διακόπτες κλειστοί: η κατάσταση είναι αναγνωρίσιμη', () {
    const rules = LampCrossCheckRules(
      userNameSpellingEnabled: false,
      userAmbiguousMatchEnabled: false,
      departmentNameSpellingEnabled: false,
      equipmentMissingInLampEnabled: false,
      equipmentRetiredInLampEnabled: false,
      equipmentTypeEnabled: false,
    );
    expect(rules.allDisabled, isTrue);
    expect(const LampCrossCheckRules().allDisabled, isFalse);
  });

  test('οι προεπιλογές επιβιώνουν σε κύκλο αποθήκευσης και ανάγνωσης', () {
    const rules = LampCrossCheckRules(
      userMissingInLampEnabled: true,
      equipmentTypeEnabled: false,
    );
    final restored = LampCrossCheckRules.fromRawJson(rules.toRawJson());
    expect(restored.userMissingInLampEnabled, isTrue);
    expect(restored.equipmentTypeEnabled, isFalse);
    expect(restored.userNameSpellingEnabled, isTrue);
  });

  test('άκυρο JSON δίνει τις προεπιλογές αντί να σκάσει', () {
    final restored = LampCrossCheckRules.fromRawJson('όχι json');
    expect(restored.userNameSpellingEnabled, isTrue);
    expect(restored.userMissingInLampEnabled, isFalse);
  });
}
