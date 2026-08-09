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

    test('με μόνο τον κανόνα εσωτερικών ενεργό, το μήνυμα δεν αναφέρει εξωτερικό', () {
      const s = CatalogValidationService(
        CatalogValidationRules(externalPhoneDigitsEnabled: false),
      );
      expect(
        s.phoneHint('25345'),
        'Το 25345 έχει 5 ψηφία — αναμένονται 4 (εσωτερικό)',
      );
    });

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
      expect(
        s.equipmentCodeHint('446'),
        'Το 446 έχει 3 ψηφία — αναμένονται 4',
      );
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
      const rules = CatalogValidationRules(personNameAllowedSymbols: '((( , --');
      expect(rules.personNameAllowedSymbolSet, {'(', '-'});
    });

    test('η σάρωση σέβεται τις εξαιρέσεις', () {
      const s = CatalogValidationService(CatalogValidationRules());
      final findings = s.scan(
        users: [
          UserModel(id: 1, lastName: 'Παπαγεωργίου', firstName: '(Γωγώ) Γεωργία'),
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
      expect(
        service.quickAddHints(equipmentCode: '25067'),
        ['Εξοπλισμός — Το 25067 έχει 5 ψηφία — αναμένονται 3 έως 4'],
      );
    });

    test('κενά και null πεδία αγνοούνται', () {
      expect(service.quickAddHints(), isEmpty);
      expect(
        service.quickAddHints(callerName: '', phones: '  '),
        isEmpty,
      );
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
        s.quickAddHints(callerName: '3π', phones: '3122', departmentName: '2545'),
        isEmpty,
      );
    });
  });

  group('scan — σάρωση υπαρχόντων δεδομένων', () {
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
      expect(f.kind, CatalogEntityKind.user);
      expect(f.entityId, 7);
      expect(f.entityLabel, 'Ψαρρά Σοφία');
      expect(f.fieldLabel, 'Τηλέφωνο');
      expect(f.focusedField, 'phone');
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
      expect(findings.every((f) => f.focusedField == 'phone'), isTrue);
    });

    test('όνομα και επώνυμο δίνουν ξεχωριστά ευρήματα με δική τους εστίαση', () {
      final findings = service.scan(
        users: [user(id: 3, lastName: '3π', firstName: '-Χ')],
        departments: const [],
        equipment: const [],
      );
      expect(findings, hasLength(2));
      expect(
        findings.map((f) => f.focusedField),
        containsAll(['lastName', 'firstName']),
      );
    });

    test('διαγραμμένος υπάλληλος και εξοπλισμός αγνοούνται', () {
      final findings = service.scan(
        users: [user(id: 1, lastName: '3π', phones: ['3122'], isDeleted: true)],
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
      expect(findings[0].focusedField, 'name');
      expect(findings[1].fieldLabel, 'Κοινόχρηστο τηλέφωνο');
      expect(findings[1].focusedField, 'phones');
      expect(findings.every((f) => f.entityLabel == '2545'), isTrue);
    });

    test('εξοπλισμός με λάθος πλήθος ψηφίων', () {
      final findings = service.scan(
        users: const [],
        departments: const [],
        equipment: [EquipmentModel(id: 42, code: '25067')],
      );
      expect(findings, hasLength(1));
      expect(findings.single.kind, CatalogEntityKind.equipment);
      expect(findings.single.entityId, 42);
      expect(findings.single.entityLabel, '25067');
      expect(findings.single.focusedField, 'code');
    });

    test('η σειρά είναι υπάλληλοι → τμήματα → εξοπλισμός', () {
      final findings = service.scan(
        users: [user(id: 1, lastName: '3π')],
        departments: [DepartmentModel(id: 2, name: '2545')],
        equipment: [EquipmentModel(id: 3, code: '25067')],
      );
      expect(
        findings.map((f) => f.kind),
        [
          CatalogEntityKind.user,
          CatalogEntityKind.department,
          CatalogEntityKind.equipment,
        ],
      );
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
        ),
      );
      final findings = s.scan(
        users: [user(id: 1, lastName: '3π', phones: ['3122'])],
        departments: [DepartmentModel(id: 2, name: '2545')],
        equipment: [EquipmentModel(id: 3, code: '25067')],
      );
      expect(findings, isEmpty);
    });

    test('εγγραφές χωρίς id αγνοούνται — δεν ανοίγει καρτέλα χωρίς ταυτότητα', () {
      final findings = service.scan(
        users: [UserModel(lastName: '3π', phones: const ['3122'])],
        departments: [DepartmentModel(name: '2545')],
        equipment: [EquipmentModel(code: '25067')],
      );
      expect(findings, isEmpty);
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
      );
      final restored = CatalogValidationRules.fromRawJson(
        original.toRawJson(),
      );
      expect(restored.toJson(), original.toJson());
    });

    test('παλιά αποθηκευμένη ρύθμιση χωρίς το νέο κλειδί παίρνει προεπιλογή', () {
      final rules = CatalogValidationRules.fromRawJson(
        '{"internal_prefix_from": 25}',
      );
      expect(
        rules.personNameAllowedSymbols,
        CatalogValidationRules.defaultPersonNameAllowedSymbols,
      );
      expect(rules.personNameAllowedSymbolSet, {'('});
    });

    test('ρητά κενές εξαιρέσεις διατηρούνται — δεν πέφτουν στην προεπιλογή', () {
      final rules = CatalogValidationRules.fromRawJson(
        '{"person_name_allowed_symbols": ""}',
      );
      expect(rules.personNameAllowedSymbols, '');
      expect(rules.personNameAllowedSymbolSet, isEmpty);
    });

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
}
