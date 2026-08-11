import 'package:call_logger/features/calls/models/equipment_model.dart';
import 'package:call_logger/features/calls/models/user_model.dart';
import 'package:call_logger/features/directory/models/catalog_validation_finding.dart';
import 'package:call_logger/features/directory/models/catalog_validation_rules.dart';
import 'package:call_logger/features/directory/models/department_model.dart';
import 'package:call_logger/features/directory/services/catalog_validation_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const defaults = CatalogValidationRules();
  const service = CatalogValidationService(defaults);

  group('phoneHint — πλήθος ψηφίων', () {
    test('4ψήφιο εσωτερικό με σωστό πρόθεμα: καμία υπόδειξη', () {
      expect(service.phoneHint('2534'), isNull);
    });

    test('10ψήφιο εξωτερικό: καμία υπόδειξη', () {
      expect(service.phoneHint('2101234567'), isNull);
    });

    test('3ψήφιο: υπόδειξη μήκους με τα δύο αναμενόμενα', () {
      expect(
        service.phoneHint('253'),
        'Το 253 έχει 3 ψηφία — αναμένονται 4 (εσωτερικό) ή 10 (εξωτερικό)',
      );
    });

    test('κενό ή μη αριθμητικό: μένει ασχολίαστο', () {
      expect(service.phoneHint(''), isNull);
      expect(service.phoneHint('  '), isNull);
      expect(service.phoneHint('25α4'), isNull);
      expect(service.phoneHint('210-1234'), isNull);
    });

    test(
      'με μόνο τον κανόνα εσωτερικών ενεργό, το μήνυμα δεν αναφέρει εξωτερικό',
      () {
        const s = CatalogValidationService(
          CatalogValidationRules(externalPhoneDigitsEnabled: false),
        );
        expect(
          s.phoneHint('25345'),
          'Το 25345 έχει 5 ψηφία — αναμένονται 4 (εσωτερικό)',
        );
      },
    );

    test('με όλους τους κανόνες μήκους ανενεργούς: καμία υπόδειξη μήκους', () {
      const s = CatalogValidationService(
        CatalogValidationRules(
          internalPhoneDigitsEnabled: false,
          externalPhoneDigitsEnabled: false,
          internalPrefixEnabled: false,
        ),
      );
      expect(s.phoneHint('253'), isNull);
    });
  });

  group('phoneHint — πρόθεμα εσωτερικών', () {
    test('4ψήφιο εκτός εύρους 22–29: υπόδειξη προθέματος', () {
      expect(service.phoneHint('3122'), 'Το 3122 δεν ξεκινά από 22–29');
    });

    test('όρια του εύρους (22xx και 29xx): καμία υπόδειξη', () {
      expect(service.phoneHint('2200'), isNull);
      expect(service.phoneHint('2999'), isNull);
    });

    test('το πρόθεμα ΔΕΝ εξετάζεται σε μη-εσωτερικό μήκος', () {
      // 10ψήφιο που ξεκινά από 21 — εξωτερικό, το πρόθεμα δεν το αφορά.
      expect(service.phoneHint('2101234567'), isNull);
    });

    test('με ανενεργό πρόθεμα, το 4ψήφιο εκτός εύρους περνά καθαρό', () {
      const s = CatalogValidationService(
        CatalogValidationRules(internalPrefixEnabled: false),
      );
      expect(s.phoneHint('3122'), isNull);
    });

    test('το πρόθεμα ακολουθεί την αλλαγμένη τιμή ψηφίων εσωτερικού', () {
      // Εσωτερικά 5ψήφια: το πρόθεμα πλέον κοιτά τα 5ψήφια, όχι τα 4ψήφια.
      const s = CatalogValidationService(
        CatalogValidationRules(internalPhoneDigits: 5),
      );
      expect(s.phoneHint('31220'), 'Το 31220 δεν ξεκινά από 22–29');
      expect(s.phoneHint('25340'), isNull);
    });
  });

  group('phonesFieldHint — πολλαπλά τηλέφωνα με κόμμα', () {
    test('επιστρέφει την πρώτη υπόδειξη της λίστας', () {
      expect(
        service.phonesFieldHint('2534, 3122'),
        'Το 3122 δεν ξεκινά από 22–29',
      );
    });

    test('όλα σωστά: καμία υπόδειξη', () {
      expect(service.phonesFieldHint('2534, 2101234567'), isNull);
    });

    test('κενό πεδίο: καμία υπόδειξη', () {
      expect(service.phonesFieldHint(''), isNull);
    });
  });

  group('equipmentCodeHint — 3 έως 4 ψηφία', () {
    test('3ψήφιοι και 4ψήφιοι κωδικοί: καμία υπόδειξη', () {
      expect(service.equipmentCodeHint('446'), isNull);
      expect(service.equipmentCodeHint('5067'), isNull);
    });

    test('5ψήφιος: υπόδειξη εύρους', () {
      expect(
        service.equipmentCodeHint('25067'),
        'Το 25067 έχει 5 ψηφία — αναμένονται 3 έως 4',
      );
    });

    test('2ψήφιος: υπόδειξη εύρους', () {
      expect(
        service.equipmentCodeHint('25'),
        'Το 25 έχει 2 ψηφία — αναμένονται 3 έως 4',
      );
    });

    test('ίδιο ελάχιστο και μέγιστο: το μήνυμα λέει έναν αριθμό', () {
      const s = CatalogValidationService(
        CatalogValidationRules(equipmentMinDigits: 4, equipmentMaxDigits: 4),
      );
      expect(s.equipmentCodeHint('446'), 'Το 446 έχει 3 ψηφία — αναμένονται 4');
    });

    test('μη αριθμητικός κωδικός ή ανενεργός κανόνας: ασχολίαστο', () {
      expect(service.equipmentCodeHint('PC-25'), isNull);
      const s = CatalogValidationService(
        CatalogValidationRules(equipmentDigitsEnabled: false),
      );
      expect(s.equipmentCodeHint('25067'), isNull);
    });
  });

  group('departmentNameHint — όνομα που μοιάζει με αριθμό', () {
    test('σκέτος αριθμός (το ιστορικό λάθος): υπόδειξη', () {
      expect(
        service.departmentNameHint('2545'),
        'Το «2545» μοιάζει με αριθμό ή τηλέφωνο, όχι με όνομα τμήματος',
      );
    });

    test('κανονικό όνομα: καμία υπόδειξη', () {
      expect(service.departmentNameHint('Γραμματεία ΤΕΠ'), isNull);
    });

    test('όνομα με αριθμό ΚΑΙ γράμματα (π.χ. «ΤΕΠ 2»): θεμιτό', () {
      expect(service.departmentNameHint('ΤΕΠ 2'), isNull);
    });

    test('κενό ή ανενεργός κανόνας: ασχολίαστο', () {
      expect(service.departmentNameHint(''), isNull);
      const s = CatalogValidationService(
        CatalogValidationRules(departmentNameEnabled: false),
      );
      expect(s.departmentNameHint('2545'), isNull);
    });
  });

  group('personNameHint — όνομα/επώνυμο υπαλλήλου', () {
    test('ξεκινά από ψηφίο (η εταιρεία «3π»): υπόδειξη, όχι απαγόρευση', () {
      expect(
        service.personNameHint('3π'),
        'Ξεκινά από ψηφίο ή σύμβολο — σωστό μόνο αν πρόκειται για εταιρεία',
      );
    });

    test('ξεκινά από σύμβολο: υπόδειξη', () {
      expect(service.personNameHint('-Παπαδόπουλος'), isNotNull);
    });

    test('ελληνικό ή λατινικό γράμμα στην αρχή: καμία υπόδειξη', () {
      expect(service.personNameHint('Ψαρρά'), isNull);
      expect(service.personNameHint('Smith'), isNull);
    });

    test('κενό ή ανενεργός κανόνας: ασχολίαστο', () {
      expect(service.personNameHint(''), isNull);
      const s = CatalogValidationService(
        CatalogValidationRules(personNameEnabled: false),
      );
      expect(s.personNameHint('3π'), isNull);
    });
  });

  group('personNameHint — εξαιρέσεις συμβόλων', () {
    test('η ανοιχτή παρένθεση είναι προεπιλεγμένη εξαίρεση', () {
      expect(service.personNameHint('(Γωγώ) Γεωργία'), isNull);
    });

    test('σύμβολο εκτός λίστας εξακολουθεί να δίνει υπόδειξη', () {
      expect(service.personNameHint('-Παπαδόπουλος'), isNotNull);
    });

    test('πολλαπλές εξαιρέσεις χωρισμένες με κόμμα', () {
      const s = CatalogValidationService(
        CatalogValidationRules(personNameAllowedSymbols: '(, -, .'),
      );
      expect(s.personNameHint('(Γωγώ)'), isNull);
      expect(s.personNameHint('-Παπαδόπουλος'), isNull);
      expect(s.personNameHint('.Χ'), isNull);
      expect(s.personNameHint('#Χ'), isNotNull);
    });

    test('τα ψηφία ΔΕΝ εξαιρούνται ποτέ, ό,τι κι αν γραφτεί στο πεδίο', () {
      const s = CatalogValidationService(
        CatalogValidationRules(personNameAllowedSymbols: '3, 5, α'),
      );
      expect(s.personNameHint('3π'), isNotNull);
      expect(s.personNameHint('5ο όροφος'), isNotNull);
    });

    test('κενό πεδίο εξαιρέσεων: κανένα σύμβολο δεν περνά', () {
      const s = CatalogValidationService(
        CatalogValidationRules(personNameAllowedSymbols: ''),
      );
      expect(s.personNameHint('(Γωγώ)'), isNotNull);
    });

    test('κενά και περιττά κόμματα αγνοούνται', () {
      const rules = CatalogValidationRules(
        personNameAllowedSymbols: ' ( , , ,  - ',
      );
      expect(rules.personNameAllowedSymbolSet, {'(', '-'});
    });

    test('από πολυχαρακτηρο στοιχείο κρατιέται ο πρώτος χαρακτήρας', () {
      const rules = CatalogValidationRules(
        personNameAllowedSymbols: '((( , --',
      );
      expect(rules.personNameAllowedSymbolSet, {'(', '-'});
    });

    test('η σάρωση σέβεται τις εξαιρέσεις', () {
      const s = CatalogValidationService(CatalogValidationRules());
      final findings = s.scan(
        users: [
          UserModel(
            id: 1,
            lastName: 'Παπαγεωργίου',
            firstName: '(Γωγώ) Γεωργία',
          ),
        ],
        departments: const [],
        equipment: const [],
      );
      expect(findings, isEmpty);
    });
  });

  group('quickAddHints — υποδείξεις γρήγορης καταχώρησης', () {
    test('καθαρή καταχώρηση: καμία γραμμή', () {
      expect(
        service.quickAddHints(
          callerName: 'Ψαρρά Σοφία',
          phones: '2565',
          departmentName: 'Γραμματεία ΤΕΠ',
          equipmentCode: '5067',
        ),
        isEmpty,
      );
    });

    test('το σενάριο «3π / 3122 / 2545» δίνει τρεις γραμμές με σειρά', () {
      expect(
        service.quickAddHints(
          callerName: '3π',
          phones: '3122',
          departmentName: '2545',
        ),
        [
          'Όνομα — Ξεκινά από ψηφίο ή σύμβολο — σωστό μόνο αν πρόκειται '
              'για εταιρεία',
          'Τηλέφωνο — Το 3122 δεν ξεκινά από 22–29',
          'Τμήμα — Το «2545» μοιάζει με αριθμό ή τηλέφωνο, όχι με όνομα '
              'τμήματος',
        ],
      );
    });

    test('ο εξοπλισμός ελέγχεται κι αυτός', () {
      expect(service.quickAddHints(equipmentCode: '25067'), [
        'Εξοπλισμός — Το 25067 έχει 5 ψηφία — αναμένονται 3 έως 4',
      ]);
    });

    test('κενά και null πεδία αγνοούνται', () {
      expect(service.quickAddHints(), isEmpty);
      expect(service.quickAddHints(callerName: '', phones: '  '), isEmpty);
    });

    test('οι εξαιρέσεις συμβόλων ισχύουν και εδώ', () {
      expect(service.quickAddHints(callerName: '(Γωγώ) Γεωργία'), isEmpty);
    });

    test('ανενεργοί κανόνες: καμία γραμμή', () {
      const s = CatalogValidationService(
        CatalogValidationRules(
          internalPhoneDigitsEnabled: false,
          externalPhoneDigitsEnabled: false,
          internalPrefixEnabled: false,
          departmentNameEnabled: false,
          personNameEnabled: false,
        ),
      );
      expect(
        s.quickAddHints(
          callerName: '3π',
          phones: '3122',
          departmentName: '2545',
        ),
        isEmpty,
      );
    });
  });

  group('scan — σάρωση υπαρχόντων δεδομένων', () {
    // Ο κανόνας των κενών τμημάτων ελέγχεται στο δικό του group· εδώ θα ήταν
    // θόρυβος, γιατί τα τεστ στήνουν τμήματα χωρίς εξαρτήματα επίτηδες.
    const service = CatalogValidationService(
      CatalogValidationRules(emptyDepartmentEnabled: false),
    );

    UserModel user({
      required int id,
      String? lastName,
      String? firstName,
      List<String> phones = const [],
      bool isDeleted = false,
    }) {
      return UserModel(
        id: id,
        lastName: lastName,
        firstName: firstName,
        phones: phones,
        isDeleted: isDeleted,
      );
    }

    test('καθαρά δεδομένα δίνουν κενή λίστα ευρημάτων', () {
      final findings = service.scan(
        users: [
          user(id: 1, lastName: 'Ψαρρά', firstName: 'Σοφία', phones: ['2565']),
        ],
        departments: [DepartmentModel(id: 10, name: 'Γραμματεία ΤΕΠ')],
        equipment: [EquipmentModel(id: 20, code: '5067')],
      );
      expect(findings, isEmpty);
    });

    test('υπάλληλος με λάθος τηλέφωνο: εύρημα με εστίαση στο πεδίο', () {
      final findings = service.scan(
        users: [
          user(id: 7, lastName: 'Ψαρρά', firstName: 'Σοφία', phones: ['3122']),
        ],
        departments: const [],
        equipment: const [],
      );
      expect(findings, hasLength(1));
      final f = findings.single;
      expect(f.type, CatalogFindingType.fieldHint);
      expect(f.isConflict, isFalse);
      expect(f.primary.kind, CatalogEntityKind.user);
      expect(f.primary.entityId, 7);
      expect(f.primary.label, 'Ψαρρά Σοφία');
      expect(f.fieldLabel, 'Τηλέφωνο');
      expect(f.primary.focusedField, 'phone');
      expect(f.message, 'Το 3122 δεν ξεκινά από 22–29');
    });

    test('ένα εύρημα ανά προβληματικό τηλέφωνο του ίδιου υπαλλήλου', () {
      final findings = service.scan(
        users: [
          user(id: 7, lastName: 'Ψαρρά', phones: ['2565', '3122', '253']),
        ],
        departments: const [],
        equipment: const [],
      );
      expect(findings, hasLength(2));
      expect(findings.every((f) => f.primary.focusedField == 'phone'), isTrue);
    });

    test(
      'όνομα και επώνυμο δίνουν ξεχωριστά ευρήματα με δική τους εστίαση',
      () {
        final findings = service.scan(
          users: [user(id: 3, lastName: '3π', firstName: '-Χ')],
          departments: const [],
          equipment: const [],
        );
        expect(findings, hasLength(2));
        expect(
          findings.map((f) => f.primary.focusedField),
          containsAll(['lastName', 'firstName']),
        );
      },
    );

    test('διαγραμμένος υπάλληλος και εξοπλισμός αγνοούνται', () {
      final findings = service.scan(
        users: [
          user(id: 1, lastName: '3π', phones: ['3122'], isDeleted: true),
        ],
        departments: const [],
        equipment: [EquipmentModel(id: 2, code: '25067', isDeleted: true)],
      );
      expect(findings, isEmpty);
    });

    test('τμήμα: όνομα-αριθμός και κοινόχρηστο τηλέφωνο', () {
      final findings = service.scan(
        users: const [],
        departments: [DepartmentModel(id: 10, name: '2545')],
        equipment: const [],
        sharedPhonesByDepartmentId: {
          10: ['3122'],
        },
      );
      expect(findings, hasLength(2));
      expect(findings[0].fieldLabel, 'Όνομα');
      expect(findings[0].primary.focusedField, 'name');
      expect(findings[1].fieldLabel, 'Κοινόχρηστο τηλέφωνο');
      expect(findings[1].primary.focusedField, 'phones');
      expect(findings.every((f) => f.primary.label == '2545'), isTrue);
    });

    test('εξοπλισμός με λάθος πλήθος ψηφίων', () {
      final findings = service.scan(
        users: const [],
        departments: const [],
        equipment: [EquipmentModel(id: 42, code: '25067')],
      );
      expect(findings, hasLength(1));
      expect(findings.single.primary.kind, CatalogEntityKind.equipment);
      expect(findings.single.primary.entityId, 42);
      expect(findings.single.primary.label, '25067');
      expect(findings.single.primary.focusedField, 'code');
    });

    test('η σειρά είναι υπάλληλοι → τμήματα → εξοπλισμός', () {
      final findings = service.scan(
        users: [user(id: 1, lastName: '3π')],
        departments: [DepartmentModel(id: 2, name: '2545')],
        equipment: [EquipmentModel(id: 3, code: '25067')],
      );
      expect(findings.map((f) => f.primary.kind), [
        CatalogEntityKind.user,
        CatalogEntityKind.department,
        CatalogEntityKind.equipment,
      ]);
    });

    test('ανενεργοί κανόνες: η σάρωση δεν βρίσκει τίποτα', () {
      const s = CatalogValidationService(
        CatalogValidationRules(
          internalPhoneDigitsEnabled: false,
          externalPhoneDigitsEnabled: false,
          internalPrefixEnabled: false,
          equipmentDigitsEnabled: false,
          departmentNameEnabled: false,
          personNameEnabled: false,
          emptyDepartmentEnabled: false,
        ),
      );
      final findings = s.scan(
        users: [
          user(id: 1, lastName: '3π', phones: ['3122']),
        ],
        departments: [DepartmentModel(id: 2, name: '2545')],
        equipment: [EquipmentModel(id: 3, code: '25067')],
      );
      expect(findings, isEmpty);
    });

    test(
      'εγγραφές χωρίς id αγνοούνται — δεν ανοίγει καρτέλα χωρίς ταυτότητα',
      () {
        final findings = service.scan(
          users: [
            UserModel(lastName: '3π', phones: const ['3122']),
          ],
          departments: [DepartmentModel(name: '2545')],
          equipment: [EquipmentModel(code: '25067')],
        );
        expect(findings, isEmpty);
      },
    );
  });

  group('scan — τμήματα χωρίς κανένα εξάρτημα', () {
    UserModel user({required int id, int? departmentId}) {
      return UserModel(id: id, lastName: 'Ψαρρά', departmentId: departmentId);
    }

    test('τμήμα χωρίς υπάλληλο, τηλέφωνο και εξοπλισμό: εύρημα', () {
      final findings = service.scan(
        users: const [],
        departments: [DepartmentModel(id: 10, name: 'Ακτινολογικό')],
        equipment: const [],
      );
      expect(findings, hasLength(1));
      final f = findings.single;
      expect(f.isConflict, isFalse);
      expect(f.primary.kind, CatalogEntityKind.department);
      expect(f.primary.entityId, 10);
      expect(f.primary.label, 'Ακτινολογικό');
      expect(f.primary.focusedField, 'name');
      expect(f.fieldLabel, 'Εξαρτήματα');
      expect(
        f.message,
        'Δεν έχει κανέναν υπάλληλο, κοινόχρηστο τηλέφωνο ή εξοπλισμό',
      );
    });

    test('ένας υπάλληλος αρκεί για να ΜΗΝ είναι κενό', () {
      final findings = service.scan(
        users: [user(id: 1, departmentId: 10)],
        departments: [DepartmentModel(id: 10, name: 'Ακτινολογικό')],
        equipment: const [],
      );
      expect(findings, isEmpty);
    });

    test('ένα κοινόχρηστο τηλέφωνο αρκεί για να ΜΗΝ είναι κενό', () {
      final findings = service.scan(
        users: const [],
        departments: [DepartmentModel(id: 10, name: 'Ακτινολογικό')],
        equipment: const [],
        sharedPhonesByDepartmentId: {
          10: ['2534'],
        },
      );
      expect(findings, isEmpty);
    });

    test('ένας εξοπλισμός αρκεί για να ΜΗΝ είναι κενό', () {
      final findings = service.scan(
        users: const [],
        departments: [DepartmentModel(id: 10, name: 'Ακτινολογικό')],
        equipment: [EquipmentModel(id: 5, code: '5067', departmentId: 10)],
      );
      expect(findings, isEmpty);
    });

    test('διαγραμμένος υπάλληλος/εξοπλισμός ΔΕΝ κρατά το τμήμα ζωντανό', () {
      final findings = service.scan(
        users: [
          UserModel(
            id: 1,
            lastName: 'Ψαρρά',
            departmentId: 10,
            isDeleted: true,
          ),
        ],
        departments: [DepartmentModel(id: 10, name: 'Ακτινολογικό')],
        equipment: [
          EquipmentModel(
            id: 5,
            code: '5067',
            departmentId: 10,
            isDeleted: true,
          ),
        ],
      );
      expect(findings, hasLength(1));
      expect(findings.single.primary.entityId, 10);
    });

    test('κενή συμβολοσειρά τηλεφώνου δεν μετράει ως εξάρτημα', () {
      final findings = service.scan(
        users: const [],
        departments: [DepartmentModel(id: 10, name: 'Ακτινολογικό')],
        equipment: const [],
        sharedPhonesByDepartmentId: {
          10: ['  '],
        },
      );
      expect(findings, hasLength(1));
    });

    test('πολλά κενά τμήματα: ένα εύρημα το καθένα', () {
      final findings = service.scan(
        users: const [],
        departments: [
          DepartmentModel(id: 10, name: 'Ακτινολογικό'),
          DepartmentModel(id: 20, name: 'Μαγειρείο'),
        ],
        equipment: const [],
      );
      expect(findings, hasLength(2));
      expect(findings.map((f) => f.primary.label), [
        'Ακτινολογικό',
        'Μαγειρείο',
      ]);
    });

    test('ανενεργός κανόνας: τίποτα', () {
      const s = CatalogValidationService(
        CatalogValidationRules(emptyDepartmentEnabled: false),
      );
      final findings = s.scan(
        users: const [],
        departments: [DepartmentModel(id: 10, name: 'Ακτινολογικό')],
        equipment: const [],
      );
      expect(findings, isEmpty);
    });
  });

  group('scan — διασταυρώσεις δεδομένων', () {
    // Ίδιος λόγος με το προηγούμενο group: τα σενάρια εδώ στήνουν τμήματα που
    // συχνά μένουν κενά, και το ζητούμενο είναι η διασταύρωση.
    const service = CatalogValidationService(
      CatalogValidationRules(emptyDepartmentEnabled: false),
    );

    UserModel user({
      required int id,
      String? lastName,
      String? firstName,
      List<String> phones = const [],
      int? departmentId,
      bool isDeleted = false,
    }) {
      return UserModel(
        id: id,
        lastName: lastName,
        firstName: firstName,
        phones: phones,
        departmentId: departmentId,
        isDeleted: isDeleted,
      );
    }

    group('τηλέφωνο που ταυτίζεται με κωδικό εξοπλισμού', () {
      test(
        'τηλέφωνο υπαλλήλου ίδιο με κωδικό: ΜΙΑ κάρτα με υπάλληλο και εξοπλισμό',
        () {
          final findings = service.scan(
            users: [
              user(
                id: 1,
                lastName: 'Ψαρρά',
                firstName: 'Σοφία',
                phones: ['3685'],
              ),
            ],
            departments: const [],
            equipment: [EquipmentModel(id: 5, code: '3685')],
          );
          // Το 3685 πιάνεται ΚΑΙ από το πρόθεμα (36 ∉ 22–29) — η διένεξη
          // είναι ξεχωριστή κάρτα.
          final conflicts = findings.where((f) => f.isConflict).toList();
          expect(conflicts, hasLength(1));
          final f = conflicts.single;
          expect(f.type, CatalogFindingType.phoneEquipmentCode);
          expect(
            f.message,
            'Το 3685 είναι καταχωρημένος κωδικός εξοπλισμού — '
            'ίσως γράφτηκε σε λάθος πεδίο',
          );
          expect(f.records, hasLength(2));
          expect(f.records[0].kind, CatalogEntityKind.user);
          expect(f.records[0].entityId, 1);
          expect(f.records[0].focusedField, 'phone');
          expect(f.records[1].kind, CatalogEntityKind.equipment);
          expect(f.records[1].entityId, 5);
          expect(f.records[1].label, '3685');
          expect(f.records[1].focusedField, 'code');
        },
      );

      test(
        'κωδικός με σωστό πρόθεμα τηλεφώνου πιάνεται ΜΟΝΟ από τη διασταύρωση',
        () {
          // Το 2534 μοιάζει με πεντακάθαρο εσωτερικό — μόνο η διασταύρωση
          // αποκαλύπτει ότι είναι κωδικός εξοπλισμού.
          final findings = service.scan(
            users: [
              user(id: 1, lastName: 'Ψαρρά', phones: ['2534']),
            ],
            departments: const [],
            equipment: [EquipmentModel(id: 5, code: '2534')],
          );
          expect(findings, hasLength(1));
          expect(findings.single.isConflict, isTrue);
        },
      );

      test(
        'δύο κάτοχοι του ίδιου «τηλεφώνου»: ΜΙΑ κάρτα με τρεις εγγραφές',
        () {
          final findings = service.scan(
            users: [
              user(id: 1, lastName: 'Ψαρρά', phones: ['2534']),
              user(id: 2, lastName: 'Δρόσος', phones: ['2534']),
            ],
            departments: const [],
            equipment: [EquipmentModel(id: 5, code: '2534')],
          );
          expect(findings, hasLength(1));
          final f = findings.single;
          expect(f.records, hasLength(3));
          expect(f.records[0].entityId, 1);
          expect(f.records[1].entityId, 2);
          // Με δύο υπαλλήλους στην κάρτα, η νεότερη εγγραφή σημαδεύεται.
          expect(f.records[0].isNewest, isFalse);
          expect(f.records[1].isNewest, isTrue);
          expect(f.records[2].kind, CatalogEntityKind.equipment);
        },
      );

      test(
        'κοινόχρηστο τηλέφωνο τμήματος ίδιο με κωδικό: κάρτα με τμήμα και εξοπλισμό',
        () {
          final findings = service.scan(
            users: const [],
            departments: [DepartmentModel(id: 10, name: 'Γραμματεία ΤΕΠ')],
            equipment: [EquipmentModel(id: 5, code: '2534')],
            sharedPhonesByDepartmentId: {
              10: ['2534'],
            },
          );
          expect(findings, hasLength(1));
          final f = findings.single;
          expect(f.records[0].kind, CatalogEntityKind.department);
          expect(f.records[0].focusedField, 'phones');
          expect(f.records[0].details, 'κοινόχρηστα τηλ. 2534');
          expect(f.records[1].kind, CatalogEntityKind.equipment);
        },
      );

      test('διαγραμμένος εξοπλισμός δεν μετρά ως κωδικός', () {
        final findings = service.scan(
          users: [
            user(id: 1, lastName: 'Ψαρρά', phones: ['2534']),
          ],
          departments: const [],
          equipment: [EquipmentModel(id: 5, code: '2534', isDeleted: true)],
        );
        expect(findings, isEmpty);
      });

      test('ανενεργός κανόνας: καμία διασταύρωση', () {
        const s = CatalogValidationService(
          CatalogValidationRules(phoneEquipmentCodeEnabled: false),
        );
        final findings = s.scan(
          users: [
            user(id: 1, lastName: 'Ψαρρά', phones: ['2534']),
          ],
          departments: const [],
          equipment: [EquipmentModel(id: 5, code: '2534')],
        );
        expect(findings, isEmpty);
      });
    });

    group('ονόματα — πιθανό ίδιο πρόσωπο', () {
      test('ζεύγος με αντεστραμμένα πεδία: ΜΙΑ κάρτα με τις δύο εγγραφές', () {
        final findings = service.scan(
          users: [
            user(id: 1, lastName: 'Δρόσος', firstName: 'Βασίλης'),
            user(id: 2, lastName: 'Βασίλης', firstName: 'Δρόσος'),
          ],
          departments: const [],
          equipment: const [],
        );
        expect(findings, hasLength(1));
        final f = findings.single;
        expect(f.type, CatalogFindingType.nameConflict);
        expect(f.message, 'Πιθανό ίδιο πρόσωπο με αντεστραμμένα πεδία');
        expect(f.records, hasLength(2));
        expect(f.records[0].entityId, 1);
        expect(f.records[0].label, 'Δρόσος Βασίλης');
        expect(f.records[0].isNewest, isFalse);
        expect(f.records[1].entityId, 2);
        expect(f.records[1].label, 'Βασίλης Δρόσος');
        expect(f.records[1].isNewest, isTrue);
        expect(f.records.every((r) => r.focusedField == 'lastName'), isTrue);
      });

      test('η σύγκριση αγνοεί τόνους και κεφαλαία', () {
        final findings = service.scan(
          users: [
            user(id: 1, lastName: 'Δρόσος', firstName: 'Βασίλης'),
            user(id: 2, lastName: 'ΒΑΣΙΛΗΣ', firstName: 'ΔΡΟΣΟΣ'),
          ],
          departments: const [],
          equipment: const [],
        );
        expect(findings, hasLength(1));
        expect(findings.single.records, hasLength(2));
      });

      test('όνομα ίδιο με επώνυμο (Γιώργος Γιώργος) δεν σκάει μόνο του', () {
        final findings = service.scan(
          users: [user(id: 1, lastName: 'Γιώργος', firstName: 'Γιώργος')],
          departments: const [],
          equipment: const [],
        );
        expect(findings, isEmpty);
      });

      test('δύο ολόιδιες εγγραφές: ΜΙΑ κάρτα διπλοτύπου', () {
        final findings = service.scan(
          users: [
            user(id: 1, lastName: 'Δρόσος', firstName: 'Βασίλης'),
            user(id: 2, lastName: 'ΔΡΟΣΟΣ', firstName: 'ΒΑΣΙΛΗΣ'),
          ],
          departments: const [],
          equipment: const [],
        );
        expect(findings, hasLength(1));
        final f = findings.single;
        expect(
          f.message,
          'Ίδιο ονοματεπώνυμο σε 2 εγγραφές — πιθανό διπλότυπο',
        );
        expect(f.records, hasLength(2));
        expect(f.records[1].isNewest, isTrue);
      });

      test('τρεις εγγραφές ίδιο + αντεστραμμένο: ΜΙΑ κάρτα με τις τρεις', () {
        // Το σενάριο που γεννούσε 3 χωριστές κάρτες: δύο «Δρόσος Βασίλης»
        // και ένας «Βασίλης Δρόσος» είναι ΜΙΑ απόφαση.
        final findings = service.scan(
          users: [
            user(id: 10, lastName: 'Δρόσος', firstName: 'Βασίλης'),
            user(id: 13, lastName: 'Βασίλης', firstName: 'Δρόσος'),
            user(id: 14, lastName: 'Δρόσος', firstName: 'Βασίλης'),
          ],
          departments: const [],
          equipment: const [],
        );
        expect(findings, hasLength(1));
        final f = findings.single;
        expect(
          f.message,
          'Ίδιο ή αντεστραμμένο ονοματεπώνυμο σε 3 εγγραφές — '
          'πιθανό ίδιο πρόσωπο',
        );
        expect(f.records.map((r) => r.entityId), [10, 13, 14]);
        expect(f.records[2].isNewest, isTrue);
      });

      test('τριπλό πιστό διπλότυπο: ΜΙΑ κάρτα με τις τρεις εγγραφές', () {
        final findings = service.scan(
          users: [
            user(id: 1, lastName: 'Δρόσος', firstName: 'Βασίλης'),
            user(id: 2, lastName: 'Δρόσος', firstName: 'Βασίλης'),
            user(id: 3, lastName: 'Δρόσος', firstName: 'Βασίλης'),
          ],
          departments: const [],
          equipment: const [],
        );
        expect(findings, hasLength(1));
        expect(findings.single.records.map((r) => r.entityId), [1, 2, 3]);
      });

      test(
        'ίδιο επώνυμο μόνο (χωρίς όνομα και στους δύο) μετρά ως διπλότυπο',
        () {
          // Εταιρείες: επωνυμία στο επώνυμο, χωρίς όνομα — δύο ίδιες = διπλότυπο.
          final findings = service.scan(
            users: [
              user(id: 1, lastName: 'Datamed'),
              user(id: 2, lastName: 'DATAMED'),
            ],
            departments: const [],
            equipment: const [],
          );
          expect(findings, hasLength(1));
          expect(findings.single.records, hasLength(2));
        },
      );

      test('ίδιο επώνυμο με διαφορετικό όνομα ΔΕΝ είναι διπλότυπο', () {
        final findings = service.scan(
          users: [
            user(id: 1, lastName: 'Δρόσος', firstName: 'Βασίλης'),
            user(id: 2, lastName: 'Δρόσος', firstName: 'Γιώργος'),
          ],
          departments: const [],
          equipment: const [],
        );
        expect(findings, isEmpty);
      });

      test('μόνο διπλότυπα ενεργά: η κάρτα κρατά ΜΟΝΟ τα πιστά διπλότυπα', () {
        const s = CatalogValidationService(
          CatalogValidationRules(swappedNamesEnabled: false),
        );
        final findings = s.scan(
          users: [
            user(id: 10, lastName: 'Δρόσος', firstName: 'Βασίλης'),
            user(id: 13, lastName: 'Βασίλης', firstName: 'Δρόσος'),
            user(id: 14, lastName: 'Δρόσος', firstName: 'Βασίλης'),
          ],
          departments: const [],
          equipment: const [],
        );
        expect(findings, hasLength(1));
        final f = findings.single;
        expect(
          f.message,
          'Ίδιο ονοματεπώνυμο σε 2 εγγραφές — πιθανό διπλότυπο',
        );
        expect(f.records.map((r) => r.entityId), [10, 14]);
      });

      test(
        'μόνο αντεστραμμένα ενεργά: το πιστό διπλότυπο δεν βγάζει κάρτα',
        () {
          const s = CatalogValidationService(
            CatalogValidationRules(duplicateNamesEnabled: false),
          );
          final duplicatesOnly = s.scan(
            users: [
              user(id: 1, lastName: 'Δρόσος', firstName: 'Βασίλης'),
              user(id: 2, lastName: 'Δρόσος', firstName: 'Βασίλης'),
            ],
            departments: const [],
            equipment: const [],
          );
          expect(duplicatesOnly, isEmpty);

          final swappedPair = s.scan(
            users: [
              user(id: 1, lastName: 'Δρόσος', firstName: 'Βασίλης'),
              user(id: 2, lastName: 'Βασίλης', firstName: 'Δρόσος'),
            ],
            departments: const [],
            equipment: const [],
          );
          expect(swappedPair, hasLength(1));
        },
      );

      test('και οι δύο κανόνες ανενεργοί: τίποτα', () {
        const s = CatalogValidationService(
          CatalogValidationRules(
            swappedNamesEnabled: false,
            duplicateNamesEnabled: false,
          ),
        );
        final findings = s.scan(
          users: [
            user(id: 1, lastName: 'Δρόσος', firstName: 'Βασίλης'),
            user(id: 2, lastName: 'Βασίλης', firstName: 'Δρόσος'),
            user(id: 3, lastName: 'Δρόσος', firstName: 'Βασίλης'),
          ],
          departments: const [],
          equipment: const [],
        );
        expect(findings, isEmpty);
      });
    });

    group('ίδιο τηλέφωνο σε διαφορετικά τμήματα', () {
      final departments = [
        DepartmentModel(id: 10, name: 'Γραμματεία ΤΕΠ'),
        DepartmentModel(id: 20, name: 'Χειρουργική'),
      ];

      test('δύο υπάλληλοι άλλων τμημάτων: ΜΙΑ κάρτα με τους δύο', () {
        final findings = service.scan(
          users: [
            user(
              id: 1,
              lastName: 'Ψαρρά',
              firstName: 'Σοφία',
              phones: ['2534'],
              departmentId: 10,
            ),
            user(
              id: 2,
              lastName: 'Δρόσος',
              firstName: 'Βασίλης',
              phones: ['2534'],
              departmentId: 20,
            ),
          ],
          departments: departments,
          equipment: const [],
        );
        expect(findings, hasLength(1));
        final f = findings.single;
        expect(f.type, CatalogFindingType.crossDepartmentPhone);
        expect(
          f.message,
          'Το 2534 είναι καταχωρημένο σε 2 υπαλλήλους σε 2 τμήματα',
        );
        expect(f.records, hasLength(2));
        expect(f.records[0].entityId, 1);
        expect(f.records[0].details, contains('Γραμματεία ΤΕΠ'));
        expect(f.records[1].entityId, 2);
        expect(f.records[1].details, contains('Χειρουργική'));
        expect(f.records[1].isNewest, isTrue);
        expect(f.records.every((r) => r.focusedField == 'phone'), isTrue);
      });

      test('τρεις κάτοχοι σε δύο τμήματα: μία κάρτα με τους τρεις', () {
        final findings = service.scan(
          users: [
            user(id: 1, lastName: 'Ψαρρά', phones: ['2534'], departmentId: 10),
            user(
              id: 2,
              lastName: 'Μαρκάτου',
              phones: ['2534'],
              departmentId: 10,
            ),
            user(id: 3, lastName: 'Δρόσος', phones: ['2534'], departmentId: 20),
          ],
          departments: departments,
          equipment: const [],
        );
        expect(findings, hasLength(1));
        final f = findings.single;
        expect(
          f.message,
          'Το 2534 είναι καταχωρημένο σε 3 υπαλλήλους σε 2 τμήματα',
        );
        expect(f.records.map((r) => r.entityId), [1, 2, 3]);
      });

      test('ίδιο τμήμα: το κοινό τηλέφωνο βάρδιας είναι θεμιτό', () {
        final findings = service.scan(
          users: [
            user(id: 1, lastName: 'Ψαρρά', phones: ['2534'], departmentId: 10),
            user(id: 2, lastName: 'Δρόσος', phones: ['2534'], departmentId: 10),
          ],
          departments: departments,
          equipment: const [],
        );
        expect(findings, isEmpty);
      });

      test('υπάλληλος χωρίς τμήμα δεν συμμετέχει στη σύγκριση', () {
        final findings = service.scan(
          users: [
            user(id: 1, lastName: 'Ψαρρά', phones: ['2534'], departmentId: 10),
            user(id: 2, lastName: 'Δρόσος', phones: ['2534']),
          ],
          departments: departments,
          equipment: const [],
        );
        expect(findings, isEmpty);
      });

      test('ανενεργός κανόνας: τίποτα', () {
        const s = CatalogValidationService(
          CatalogValidationRules(crossDepartmentPhoneEnabled: false),
        );
        final findings = s.scan(
          users: [
            user(id: 1, lastName: 'Ψαρρά', phones: ['2534'], departmentId: 10),
            user(id: 2, lastName: 'Δρόσος', phones: ['2534'], departmentId: 20),
          ],
          departments: departments,
          equipment: const [],
        );
        expect(findings, isEmpty);
      });
    });

    group('εξοπλισμός χρεωμένος σε υπάλληλο άλλου τμήματος', () {
      final departments = [
        DepartmentModel(id: 10, name: 'Γραμματεία ΤΕΠ'),
        DepartmentModel(id: 20, name: 'Χειρουργική'),
      ];

      test('κάτοχος άλλου τμήματος: κάρτα με εξοπλισμό και κάτοχο', () {
        final findings = service.scan(
          users: [
            user(
              id: 1,
              lastName: 'Ψαρρά',
              firstName: 'Σοφία',
              departmentId: 10,
            ),
          ],
          departments: departments,
          equipment: [EquipmentModel(id: 5, code: '5067', departmentId: 20)],
          ownerUserIdsByEquipmentId: {
            5: [1],
          },
        );
        expect(findings, hasLength(1));
        final f = findings.single;
        expect(f.type, CatalogFindingType.equipmentOwnerDepartment);
        expect(
          f.message,
          'Χρεωμένος στην εγγραφή «Ψαρρά Σοφία» (Γραμματεία ΤΕΠ), '
          'ενώ ανήκει στο «Χειρουργική»',
        );
        expect(f.records, hasLength(2));
        expect(f.records[0].kind, CatalogEntityKind.equipment);
        expect(f.records[0].entityId, 5);
        expect(f.records[0].label, '5067');
        expect(f.records[0].details, contains('Χειρουργική'));
        expect(f.records[1].kind, CatalogEntityKind.user);
        expect(f.records[1].entityId, 1);
        expect(f.records[1].details, contains('Γραμματεία ΤΕΠ'));
        expect(f.records.every((r) => r.focusedField == 'department'), isTrue);
      });

      test('δύο ασύμφωνοι κάτοχοι: μία κάρτα με τους τρεις εμπλεκόμενους', () {
        final findings = service.scan(
          users: [
            user(id: 1, lastName: 'Ψαρρά', departmentId: 10),
            user(id: 2, lastName: 'Δρόσος', departmentId: 10),
          ],
          departments: departments,
          equipment: [EquipmentModel(id: 5, code: '5067', departmentId: 20)],
          ownerUserIdsByEquipmentId: {
            5: [1, 2],
          },
        );
        expect(findings, hasLength(1));
        final f = findings.single;
        expect(
          f.message,
          'Χρεωμένος σε 2 υπαλλήλους άλλων τμημάτων, '
          'ενώ ανήκει στο «Χειρουργική»',
        );
        expect(f.records, hasLength(3));
      });

      test('κάτοχος ίδιου τμήματος: καθαρό', () {
        final findings = service.scan(
          users: [user(id: 1, lastName: 'Ψαρρά', departmentId: 20)],
          departments: departments,
          equipment: [EquipmentModel(id: 5, code: '5067', departmentId: 20)],
          ownerUserIdsByEquipmentId: {
            5: [1],
          },
        );
        expect(findings, isEmpty);
      });

      test(
        'εξοπλισμός ή κάτοχος χωρίς τμήμα: καθαρό — δεν αποδεικνύεται ασυμφωνία',
        () {
          final findings = service.scan(
            users: [
              user(id: 1, lastName: 'Ψαρρά', departmentId: 10),
              user(id: 2, lastName: 'Δρόσος'),
            ],
            departments: departments,
            equipment: [
              EquipmentModel(id: 5, code: '5067'),
              EquipmentModel(id: 6, code: '446', departmentId: 20),
            ],
            ownerUserIdsByEquipmentId: {
              5: [1],
              6: [2],
            },
          );
          expect(findings, isEmpty);
        },
      );

      test('ανενεργός κανόνας: τίποτα', () {
        const s = CatalogValidationService(
          CatalogValidationRules(equipmentOwnerDepartmentEnabled: false),
        );
        final findings = s.scan(
          users: [user(id: 1, lastName: 'Ψαρρά', departmentId: 10)],
          departments: departments,
          equipment: [EquipmentModel(id: 5, code: '5067', departmentId: 20)],
          ownerUserIdsByEquipmentId: {
            5: [1],
          },
        );
        expect(findings, isEmpty);
      });
    });
  });
  group('CatalogValidationRules — αποθήκευση/φόρτωση', () {
    test('roundtrip JSON διατηρεί όλες τις τιμές', () {
      const original = CatalogValidationRules(
        internalPhoneDigitsEnabled: false,
        internalPhoneDigits: 5,
        externalPhoneDigitsEnabled: false,
        externalPhoneDigits: 11,
        internalPrefixEnabled: false,
        internalPrefixFrom: 30,
        internalPrefixTo: 45,
        equipmentDigitsEnabled: false,
        equipmentMinDigits: 2,
        equipmentMaxDigits: 6,
        departmentNameEnabled: false,
        personNameEnabled: false,
        personNameAllowedSymbols: '(, -, .',
        phoneEquipmentCodeEnabled: false,
        swappedNamesEnabled: false,
        duplicateNamesEnabled: false,
        crossDepartmentPhoneEnabled: false,
        equipmentOwnerDepartmentEnabled: false,
        emptyDepartmentEnabled: false,
      );
      final restored = CatalogValidationRules.fromRawJson(original.toRawJson());
      expect(restored.toJson(), original.toJson());
    });

    test(
      'παλιά αποθηκευμένη ρύθμιση χωρίς το νέο κλειδί παίρνει προεπιλογή',
      () {
        final rules = CatalogValidationRules.fromRawJson(
          '{"internal_prefix_from": 25}',
        );
        expect(
          rules.personNameAllowedSymbols,
          CatalogValidationRules.defaultPersonNameAllowedSymbols,
        );
        expect(rules.personNameAllowedSymbolSet, {'('});
        // Οι διασταυρώσεις προστέθηκαν αργότερα — παλιά ρύθμιση χωρίς τα
        // κλειδιά τους ξεκινά με όλες ενεργές.
        expect(rules.phoneEquipmentCodeEnabled, isTrue);
        expect(rules.swappedNamesEnabled, isTrue);
        expect(rules.duplicateNamesEnabled, isTrue);
        expect(rules.crossDepartmentPhoneEnabled, isTrue);
        expect(rules.equipmentOwnerDepartmentEnabled, isTrue);
        expect(rules.emptyDepartmentEnabled, isTrue);
      },
    );

    test(
      'ρητά κενές εξαιρέσεις διατηρούνται — δεν πέφτουν στην προεπιλογή',
      () {
        final rules = CatalogValidationRules.fromRawJson(
          '{"person_name_allowed_symbols": ""}',
        );
        expect(rules.personNameAllowedSymbols, '');
        expect(rules.personNameAllowedSymbolSet, isEmpty);
      },
    );

    test('null, κενό και σκουπίδια δίνουν τις προεπιλογές', () {
      for (final raw in [null, '', '  ', 'όχι json', '[1,2]']) {
        final rules = CatalogValidationRules.fromRawJson(raw);
        expect(rules.toJson(), const CatalogValidationRules().toJson());
      }
    });

    test('άγνωστα κλειδιά αγνοούνται, γνωστά διαβάζονται', () {
      final rules = CatalogValidationRules.fromRawJson(
        '{"internal_prefix_from": 25, "future_operator": "AND"}',
      );
      expect(rules.internalPrefixFrom, 25);
      expect(rules.internalPrefixTo, 29);
    });
  });

  // Τα αναγνωριστικά μπήκαν με αντιγραφή-επικόλληση χωρίς κανέναν έλεγχο —
  // ο κανόνας φέρνει τον ΙΔΙΟ κριτή των φορμών και στη μαζική σάρωση,
  // ώστε τα ήδη περασμένα λάθη να εντοπίζονται με ένα κλικ.
  group('Αναγνωριστικά Lansweeper', () {
    test('υπάλληλος: στοχευμένο μήνυμα ανά περίπτωση, έγκυρες/κενό → καμία',
        () {
      // Χωρίς σημάδι πρόθεσης → το γενικό μήνυμα (μόνο τότε).
      expect(
        service.lansweeperUserIdentifierHint('Βασίλης Δρόσος'),
        contains('Δεν μοιάζει ούτε με'),
      );
      // Με σημάδι πρόθεσης → το στοχευμένο λάθος, όχι το γενικό.
      expect(
        service.lansweeperUserIdentifierHint(r'mad\fdf\56'),
        contains('περισσότερες από μία'),
      );
      expect(
        service.lansweeperUserIdentifierHint('dro@fd'),
        contains('δεν μοιάζει πλήρης'),
      );
      expect(service.lansweeperUserIdentifierHint(r'gnk\v.drosos'), isNull);
      expect(
        service.lansweeperUserIdentifierHint('v.drosos@hospital.gr'),
        isNull,
      );
      expect(service.lansweeperUserIdentifierHint(''), isNull);
      expect(service.lansweeperUserIdentifierHint('   '), isNull);
    });

    test('τμήμα: ένα μήνυμα ΑΝΑ προβληματικό λογαριασμό — όχι συγκεντρωτικό',
        () {
      final problems = service.lansweeperDepartmentAccountProblems(
        r'Γραφείο Λοιμώξεων, Α = gnk\bio1, path@ gnk.g',
      );
      expect(problems, hasLength(2));
      expect(problems.first, contains('Γραφείο Λοιμώξεων'));
      expect(problems.first, contains('Δεν μοιάζει ούτε με'));
      expect(problems.last, contains('κενό'));

      expect(
        service.lansweeperDepartmentAccountProblems(r'gnk\loimokseis1'),
        isEmpty,
      );
      expect(service.lansweeperDepartmentAccountProblems(null), isEmpty);
      expect(service.lansweeperDepartmentAccountProblems('  '), isEmpty);
    });

    test('τμήμα: ήπια υποψία τομέα μόνο με μέτρο σύγκρισης', () {
      final mismatches = service.lansweeperDomainMismatchProblems(
        r'Α = 3gnk\TepPath1, Β = gnk\bio1',
        'gnk',
      );
      expect(mismatches, hasLength(1));
      expect(mismatches.single, contains('«3gnk»'));

      expect(
        service.lansweeperDomainMismatchProblems(r'Α = 3gnk\TepPath1', null),
        isEmpty,
      );
    });

    test(
      'scan: πράκτορας-email → μέτρο σύγκρισης ο πλειοψηφικός τομέας — '
      'το 3gnk σημαίνεται',
      () {
        const s = CatalogValidationService(
          CatalogValidationRules(emptyDepartmentEnabled: false),
        );
        final findings = s.scan(
          users: [
            UserModel(
              id: 1,
              lastName: 'Α',
              firstName: 'Α',
              lansweeperUsername: r'gnk\a',
            ),
            UserModel(
              id: 2,
              lastName: 'Β',
              firstName: 'Β',
              lansweeperUsername: r'gnk\b',
            ),
          ],
          departments: [
            DepartmentModel(
              id: 63,
              name: 'ΤΕΠ Παθολογικό',
              lansweeperUsernames: r'Γιατρός = 3gnk\TepPath1',
            ),
          ],
          equipment: const [],
          lansweeperAgentIdentity: 'v.drosos@hospkorinthos.gr',
        );
        expect(findings, hasLength(1));
        expect(findings.single.message, contains('«3gnk»'));
        expect(findings.single.message, contains('πιθανό τυπογραφικό'));
      },
    );

    test('ανενεργός κανόνας → σιωπή παντού', () {
      const s = CatalogValidationService(
        CatalogValidationRules(lansweeperIdentifierEnabled: false),
      );
      expect(s.lansweeperUserIdentifierHint('Βασίλης Δρόσος'), isNull);
      expect(
        s.lansweeperDepartmentAccountProblems('Γραφείο Λοιμώξεων'),
        isEmpty,
      );
      expect(
        s.lansweeperDomainMismatchProblems(r'Α = 3gnk\a', 'gnk'),
        isEmpty,
      );
    });

    test('scan: άκυρο αναγνωριστικό υπαλλήλου → εύρημα με εστίαση στο πεδίο',
        () {
      final findings = service.scan(
        users: [
          UserModel(
            id: 5,
            lastName: 'Βελέντζας',
            firstName: 'Κωνσταντίνος',
            phones: const ['2534'],
            lansweeperUsername: 'Κωνσταντίνος Βελέντζας',
          ),
        ],
        departments: const [],
        equipment: const [],
      );
      expect(findings, hasLength(1));
      final f = findings.single;
      expect(f.type, CatalogFindingType.fieldHint);
      expect(f.fieldLabel, 'Αναγνωριστικό Lansweeper');
      expect(f.primary.kind, CatalogEntityKind.user);
      expect(f.primary.entityId, 5);
      expect(f.primary.focusedField, 'lansweeperUsername');
    });

    test('scan: άκυρος λογαριασμός τμήματος → εύρημα με εστίαση στο πεδίο',
        () {
      const s = CatalogValidationService(
        CatalogValidationRules(emptyDepartmentEnabled: false),
      );
      final findings = s.scan(
        users: const [],
        departments: [
          DepartmentModel(
            id: 63,
            name: 'Λοιμώξεων',
            lansweeperUsernames: 'Γραφείο Λοιμώξεων',
          ),
        ],
        equipment: const [],
      );
      expect(findings, hasLength(1));
      final f = findings.single;
      expect(f.fieldLabel, 'Αναγνωριστικά Lansweeper');
      expect(f.primary.kind, CatalogEntityKind.department);
      expect(f.primary.entityId, 63);
      expect(f.primary.focusedField, 'lansweeperUsernames');
    });

    test('scan: έγκυρα αναγνωριστικά παντού → κανένα εύρημα', () {
      const s = CatalogValidationService(
        CatalogValidationRules(emptyDepartmentEnabled: false),
      );
      final findings = s.scan(
        users: [
          UserModel(
            id: 5,
            lastName: 'Βελέντζας',
            firstName: 'Κωνσταντίνος',
            phones: const ['2534'],
            lansweeperUsername: r'gnk\k.velentzas',
          ),
        ],
        departments: [
          DepartmentModel(
            id: 63,
            name: 'Λοιμώξεων',
            lansweeperUsernames: r'gnk\loimokseis1',
          ),
        ],
        equipment: const [],
      );
      expect(findings, isEmpty);
    });
  });
}
