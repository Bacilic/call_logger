// Τι λέει η καρτέλα του υπαλλήλου τη στιγμή που αλλάζει το τμήμα του.
//
// Όπως και στην αλλαγή Είδους μιας καρτέλας, η γραμμή μιλά για ΜΕΤΑΒΑΣΕΙΣ:
// υπάλληλος που ήταν ήδη σε εταιρεία δεν «χάνει» τώρα τον εξοπλισμό του — τον
// είχε ήδη χάσει.
//
//   flutter test test/features/directory/user_move_consequences_test.dart

import 'package:call_logger/features/directory/models/department_kind.dart';
import 'package:call_logger/features/directory/services/user_move_consequences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  UserMoveConsequences judge({
    required DepartmentKind from,
    required DepartmentKind to,
    int equipment = 0,
    bool lansweeperIsEmpty = false,
  }) => judgeUserMove(
    previousKind: from,
    targetKind: to,
    carriedEquipmentCount: equipment,
    lansweeperIsEmpty: lansweeperIsEmpty,
  );

  String? message(DepartmentKind kind, UserMoveConsequences consequences) =>
      userMoveConsequencesMessage(targetKind: kind, consequences: consequences);

  group('Πότε δεν λέγεται τίποτα', () {
    test('ίδιο Είδος τμήματος: καμία αλλαγή', () {
      final result = judge(
        from: DepartmentKind.hospital,
        to: DepartmentKind.hospital,
        equipment: 3,
        lansweeperIsEmpty: true,
      );

      expect(result.hasAnything, isFalse);
      expect(message(DepartmentKind.hospital, result), isNull);
    });

    test('προς εταιρεία χωρίς μηχανήματα: τίποτα να χαθεί', () {
      final result = judge(
        from: DepartmentKind.hospital,
        to: DepartmentKind.company,
      );

      expect(message(DepartmentKind.company, result), isNull);
    });

    test('εταιρεία προς εξωτερική μονάδα: τον είχε ήδη χάσει', () {
      final result = judge(
        from: DepartmentKind.company,
        to: DepartmentKind.externalUnit,
        equipment: 2,
      );

      expect(
        result.equipmentLeftBehind,
        0,
        reason:
            'Η εταιρεία δεν κρατούσε ποτέ μηχανήματα — τίποτα δεν μένει πίσω '
            'τώρα. Και η εξωτερική μονάδα τα κρατά κανονικά.',
      );
    });

    test('επιστροφή σε νοσοκομείο ΜΕ αναγνωριστικό: τίποτα', () {
      final result = judge(
        from: DepartmentKind.company,
        to: DepartmentKind.hospital,
      );

      expect(message(DepartmentKind.hospital, result), isNull);
    });
  });

  group('Προς Είδος που δεν κρατά μηχανήματα', () {
    test('ένα μηχάνημα: ενικός', () {
      final result = judge(
        from: DepartmentKind.hospital,
        to: DepartmentKind.company,
        equipment: 1,
      );

      expect(
        message(DepartmentKind.company, result),
        '1 μηχάνημα δεν μπορεί να ακολουθήσει στην εταιρεία — μένει στο τμήμα '
        'που αφήνει',
      );
    });

    test('πολλά μηχανήματα: πληθυντικός και στα δύο ρήματα', () {
      final result = judge(
        from: DepartmentKind.hospital,
        to: DepartmentKind.company,
        equipment: 3,
      );

      expect(
        message(DepartmentKind.company, result),
        '3 μηχανήματα δεν μπορούν να ακολουθήσουν στην εταιρεία — μένουν στο '
        'τμήμα που αφήνει',
      );
    });

    test('η εξωτερική μονάδα κρατά μηχανήματα: καμία απώλεια', () {
      final result = judge(
        from: DepartmentKind.hospital,
        to: DepartmentKind.externalUnit,
        equipment: 4,
      );

      expect(result.equipmentLeftBehind, 0);
    });
  });

  group('Η επιστροφή στο νοσοκομείο', () {
    test('χωρίς αναγνωριστικό: το λέει', () {
      final result = judge(
        from: DepartmentKind.company,
        to: DepartmentKind.hospital,
        lansweeperIsEmpty: true,
      );

      expect(
        message(DepartmentKind.hospital, result),
        'Ως υπάλληλος του νοσοκομείου θα ζητηθεί αναγνωριστικό Lansweeper — '
        'όσο λείπει, θα εμφανίζεται στον Έλεγχο δεδομένων.',
      );
    });

    test('από εξωτερική μονάδα: ίδια απαίτηση', () {
      final result = judge(
        from: DepartmentKind.externalUnit,
        to: DepartmentKind.hospital,
        lansweeperIsEmpty: true,
      );

      expect(result.startsExpectingLansweeper, isTrue);
    });

    test('προς εξωτερική μονάδα: καμία απαίτηση αναγνωριστικού', () {
      final result = judge(
        from: DepartmentKind.hospital,
        to: DepartmentKind.externalUnit,
        lansweeperIsEmpty: true,
      );

      expect(
        result.startsExpectingLansweeper,
        isFalse,
        reason: 'Ούτε η εξωτερική μονάδα φτάνει ποτέ ως αιτών στο Lansweeper.',
      );
    });
  });

  test('και τα δύο μαζί δεν συμβαίνουν ποτέ', () {
    // Η μία κατεύθυνση αφαιρεί, η άλλη προσθέτει: δεν υπάρχει μετάβαση που να
    // κάνει και τα δύο. Το τεστ φυλάει ότι η γραμμή δεν θα γίνει σεντόνι.
    for (final from in DepartmentKind.values) {
      for (final to in DepartmentKind.values) {
        final result = judge(
          from: from,
          to: to,
          equipment: 2,
          lansweeperIsEmpty: true,
        );
        expect(
          result.equipmentLeftBehind > 0 && result.startsExpectingLansweeper,
          isFalse,
          reason: 'από $from προς $to',
        );
      }
    }
  });
}
