// Το εσωτερικό του δικού μας κέντρου δεν ακολουθεί άνθρωπο που φεύγει από το
// νοσοκομείο.
//
// Ίδιο συμβόλαιο με τον εξοπλισμό — διαφορετικό κριτήριο: η εξωτερική μονάδα
// κρατά δικά μας μηχανήματα, αλλά έχει δεκαψήφια, όχι δικό μας τετραψήφιο.
//
// Η γνώση «τι είναι εσωτερικό» διαβάζει ΜΟΝΟ τις αριθμητικές τιμές — ποτέ τους
// διακόπτες των προειδοποιήσεων, που σβήνουν με το επίπεδο αυστηρότητας.
//
//   flutter test test/features/directory/phone_transfer_split_test.dart

import 'package:call_logger/features/directory/models/catalog_validation_rules.dart';
import 'package:call_logger/features/directory/models/department_kind.dart';
import 'package:call_logger/features/directory/services/phone_transfer_split.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const rules = CatalogValidationRules();

  PhoneTransferSplit split(
    List<String> phones,
    DepartmentKind to, {
    CatalogValidationRules withRules = rules,
  }) => splitPhonesForDepartmentChange(
    phones: phones,
    targetKind: to,
    rules: withRules,
  );

  group('Η γνώση «είναι δικό μας εσωτερικό;»', () {
    test('τετραψήφιο με πρόθεμα 22-29: ναι', () {
      expect(rules.looksLikeHospitalInternalPhone('2986'), isTrue);
      expect(rules.looksLikeHospitalInternalPhone('2200'), isTrue);
      expect(rules.looksLikeHospitalInternalPhone('2999'), isTrue);
    });

    test('τετραψήφιο εκτός προθέματος: όχι', () {
      expect(rules.looksLikeHospitalInternalPhone('3841'), isFalse);
      expect(rules.looksLikeHospitalInternalPhone('2199'), isFalse);
    });

    test('δεκαψήφιο: όχι', () {
      expect(rules.looksLikeHospitalInternalPhone('2741022667'), isFalse);
      expect(rules.looksLikeHospitalInternalPhone('2108056700'), isFalse);
    });

    test('οι διακόπτες των προειδοποιήσεων ΔΕΝ την αγγίζουν', () {
      // Το επίπεδο «Ελάχιστοι έλεγχοι» σβήνει τον κανόνα προειδοποίησης —
      // αλλά τα ψηφία και το πρόθεμα μένουν, άρα η γνώση επιβιώνει.
      final minimal = rules.withStrictness(CatalogStrictnessLevel.minimal);

      expect(minimal.companyInternalPhoneEnabled, isFalse);
      expect(
        minimal.looksLikeHospitalInternalPhone('2986'),
        isTrue,
        reason:
            'Οι διακόπτες αποφασίζουν αν θα εμφανιστεί προειδοποίηση, όχι αν '
            'το 2986 είναι εσωτερικό.',
      );
    });

    test('ακολουθεί τις τιμές του χρήστη', () {
      const custom = CatalogValidationRules(
        internalPhoneDigits: 3,
        internalPrefixFrom: 50,
        internalPrefixTo: 59,
      );

      expect(custom.looksLikeHospitalInternalPhone('512'), isTrue);
      expect(custom.looksLikeHospitalInternalPhone('2986'), isFalse);
    });
  });

  group('Προς τμήμα του νοσοκομείου', () {
    test('όλα ρωτιούνται, όπως πάντα', () {
      final result = split(['2986', '2741022667'], DepartmentKind.hospital);

      expect(result.forcedToStay, isEmpty);
      expect(result.negotiable, ['2986', '2741022667']);
      expect(result.asksAnything, isTrue);
    });
  });

  group('Προς εταιρεία', () {
    test('μόνο εσωτερικά: καμία ερώτηση, όλα μένουν', () {
      final result = split(['2986', '2503'], DepartmentKind.company);

      expect(result.forcedToStay, ['2986', '2503']);
      expect(result.negotiable, isEmpty);
      expect(
        result.asksAnything,
        isFalse,
        reason: 'Δεν υπάρχει τίποτα να αποφασιστεί — 80 στους 83 υπαλλήλους.',
      );
    });

    test('μικτός: ρωτιέται μόνο το εξωτερικό', () {
      final result = split(['2503', '2741022667'], DepartmentKind.company);

      expect(result.forcedToStay, [
        '2503',
      ], reason: 'Το εσωτερικό μένει χωρίς να ρωτηθεί.');
      expect(result.negotiable, [
        '2741022667',
      ], reason: 'Το προσωπικό της μπορεί όντως να την ακολουθήσει.');
    });

    test('μόνο εξωτερικά: τίποτα αναγκαστικό', () {
      final result = split(['2741022667'], DepartmentKind.company);

      expect(result.hasForced, isFalse);
      expect(result.negotiable, ['2741022667']);
    });
  });

  group('Προς εξωτερική μονάδα', () {
    test('ισχύει ο ΙΔΙΟΣ κανόνας με την εταιρεία', () {
      final result = split(['2986'], DepartmentKind.externalUnit);

      expect(
        result.forcedToStay,
        ['2986'],
        reason:
            'Η εξωτερική μονάδα κρατά δικά μας μηχανήματα, αλλά έχει '
            'δεκαψήφια — δικό μας εσωτερικό δεν χτυπά ποτέ εκεί.',
      );
    });

    test('διαφέρει από τον εξοπλισμό: εκεί επιτρέπεται', () {
      expect(DepartmentKind.externalUnit.canOwnEquipment, isTrue);
      expect(DepartmentKind.externalUnit.canHoldHospitalInternalPhone, isFalse);
      expect(DepartmentKind.hospital.canHoldHospitalInternalPhone, isTrue);
      expect(DepartmentKind.company.canHoldHospitalInternalPhone, isFalse);
    });
  });

  group('Η αναγγελία', () {
    String? message(
      PhoneTransferSplit s,
      DepartmentKind kind, {
      String? source,
    }) => forcedPhoneStayMessage(
      split: s,
      targetKind: kind,
      sourceDepartmentName: source,
    );

    test('ένα τηλέφωνο, με όνομα τμήματος', () {
      final result = split(['2986'], DepartmentKind.company);

      expect(
        message(result, DepartmentKind.company, source: 'Γραφείο Κίνησης'),
        'Το 2986 είναι εσωτερικό του νοσοκομείου και δεν ακολουθεί στην '
        'εταιρεία — μένει στο τμήμα «Γραφείο Κίνησης»',
      );
    });

    test('πολλά τηλέφωνα: πληθυντικός και στα δύο ρήματα', () {
      final result = split(['2986', '2503'], DepartmentKind.company);

      expect(
        message(result, DepartmentKind.company, source: 'Γραφείο Κίνησης'),
        'Τα 2986, 2503 είναι εσωτερικά του νοσοκομείου και δεν ακολουθούν '
        'στην εταιρεία — μένουν στο τμήμα «Γραφείο Κίνησης»',
      );
    });

    test('χωρίς όνομα τμήματος: η μαζική μεταφορά', () {
      final result = split(['2986'], DepartmentKind.company);

      expect(
        message(result, DepartmentKind.company),
        contains('μένει στο τμήμα που αφήνει'),
        reason:
            'Στη μαζική οι υπάλληλοι μπορεί να προέρχονται από διαφορετικά '
            'τμήματα — ένα όνομα θα ήταν ψέμα για τους μισούς.',
      );
    });

    test('τίποτα αναγκαστικό: καμία αναγγελία', () {
      final result = split(['2741022667'], DepartmentKind.company);

      expect(message(result, DepartmentKind.company), isNull);
    });
  });
}
