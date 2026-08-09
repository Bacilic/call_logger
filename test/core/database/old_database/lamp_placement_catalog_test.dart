// Ομαδοποίηση υπαλλήλων για τον ορισμό τοποθέτησης.
//
// Τα δεδομένα είναι αληθινά, από τη Μαιευτική-Γυναικολογική Κλινική της
// Λάμπας: το γραφείο 27 έχει έναν υπάλληλο με ΜΗΔΕΝ εξοπλισμούς, ενώ ο
// διευθυντής του τμήματος χρεώνεται έντεκα. Αυτό είναι ο κανόνας του
// νοσοκομείου, όχι σφάλμα — γι' αυτό υπάρχει η ενδιάμεση ομάδα.
//
//   flutter test test/core/database/old_database/lamp_placement_catalog_test.dart

import 'package:call_logger/core/database/old_database/lamp_placement_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../test_reporter.dart';

void main() {
  const gynecology = 'Μαιευτική-Γυναικολογική Κλινική';

  const catalog = LampPlacementCatalog(
    offices: <LampPlacementOffice>[
      LampPlacementOffice(
        id: 27,
        officeName: 'Γραφείο Ιατρών Γυναικολογικής',
        departmentName: gynecology,
      ),
      LampPlacementOffice(
        id: 182,
        officeName: 'Διευθυντής Γυναικολογικής',
        departmentName: gynecology,
      ),
      LampPlacementOffice(
        id: 20,
        officeName: 'Πληροφορική',
        departmentName: 'Πληροφορικής',
      ),
    ],
    owners: <LampPlacementOwner>[
      LampPlacementOwner(
        id: 337,
        name: 'Ζούκας Λάμπρος',
        officeId: 27,
        officeName: 'Γραφείο Ιατρών Γυναικολογικής',
        departmentName: gynecology,
      ),
      LampPlacementOwner(
        id: 81,
        name: 'Καμπάς Νικόλαος',
        officeId: 182,
        officeName: 'Διευθυντής Γυναικολογικής',
        departmentName: gynecology,
        equipmentCount: 11,
      ),
      LampPlacementOwner(
        id: 318,
        name: 'Λέκκα-Ρέμμα Αργυρώ',
        officeId: 171,
        officeName: 'Προϊσταμένη Γυναικολογικής',
        departmentName: gynecology,
        equipmentCount: 5,
      ),
      LampPlacementOwner(
        id: 26,
        name: 'Δασκαλοπούλου Ιωάννα',
        officeId: 20,
        officeName: 'Πληροφορική',
        departmentName: 'Πληροφορικής',
        equipmentCount: 3,
      ),
    ],
  );

  group('τρεις ομάδες', () {
    test('γραφείο, τμήμα, υπόλοιπη βάση', () {
      final groups = catalog.ownerGroups(officeId: 27);

      expect(groups, hasLength(3));
      expect(groups[0].title, 'Σε αυτό το γραφείο · 1');
      expect(groups[0].owners.single.id, 337);
      expect(groups[1].title, contains(gynecology));
      expect(groups[1].owners.map((o) => o.id), <int>[81, 318]);
      expect(groups[2].title, startsWith('Υπόλοιπη βάση'));
      expect(groups[2].owners.single.id, 26);
    });

    test('ο υπάλληλος με τους περισσότερους εξοπλισμούς προηγείται', () {
      final department = catalog.ownerGroups(officeId: 27)[1];

      expect(
        department.owners.first.id,
        81,
        reason: greekExpectMsg(
          'Τους εξοπλισμούς ενός τμήματος τους χρεώνεται συνήθως ο '
          'διευθυντής ή η προϊσταμένη — αυτοί πρέπει να φαίνονται πρώτοι',
        ),
      );
    });

    test('μηδέν εξοπλισμοί δεν αποκλείουν κανέναν', () {
      final inOffice = catalog.ownerGroups(officeId: 27).first;

      expect(
        inOffice.owners.single.equipmentCount,
        0,
        reason: greekExpectMsg(
          'Υπάλληλος γραφείου χωρίς χρεωμένο εξοπλισμό είναι κανονική '
          'κατάσταση στο νοσοκομείο, όχι σκουπιδο-εγγραφή',
        ),
      );
    });

    test('χωρίς επιλεγμένο γραφείο υπάρχει μόνο η γενική ομάδα', () {
      final groups = catalog.ownerGroups();

      expect(groups, hasLength(1));
      expect(groups.single.title, startsWith('Όλοι οι υπάλληλοι'));
      expect(groups.single.owners.first.id, 81);
    });
  });

  group('αναζήτηση', () {
    test('το φιλτράρισμα κρατά τις ομάδες', () {
      final groups = catalog.ownerGroups(officeId: 27, query: 'καμπ');

      expect(groups, hasLength(1));
      expect(groups.single.owners.single.id, 81);
    });

    test('βρίσκει υπάλληλο εκτός τμήματος — όλη η βάση παραμένει διαθέσιμη', () {
      final groups = catalog.ownerGroups(officeId: 27, query: 'δασκαλοπουλου');

      expect(
        groups.single.owners.single.id,
        26,
        reason: greekExpectMsg(
          'Το φίλτρο του γραφείου βοηθά, δεν κλειδώνει: ο σωστός κάτοχος '
          'μπορεί να ανήκει αλλού',
        ),
      );
    });

    test('η αναζήτηση αγνοεί τόνους και πεζά-κεφαλαία', () {
      expect(catalog.searchOffices('ΓΥΝΑΙΚΟΛΟΓΙΚΗΣ'), hasLength(2));
      expect(catalog.searchOffices('πληροφορικη').single.id, 20);
    });

    test('κενό ερώτημα φέρνει όλα τα γραφεία', () {
      expect(catalog.searchOffices(''), hasLength(3));
    });
  });

  test('η ετικέτα γραφείου δεν επαναλαμβάνει το τμήμα', () {
    const same = LampPlacementOffice(
      id: 5,
      officeName: 'Πρωτόκολλο',
      departmentName: 'Πρωτόκολλο',
    );
    expect(same.label, '5 · Πρωτόκολλο');
    expect(
      catalog.officeById(27)!.label,
      '27 · Γραφείο Ιατρών Γυναικολογικής · $gynecology',
    );
  });
}
