// Ετικέτες διαγραφής εξοπλισμού: ποιος τον κρατά και τι αφήνει πίσω του.
//
// Ολόκληρο αρχείο (από ρίζα έργου):
//   flutter test test/features/directory/equipment_deletion_label_test.dart

import 'package:call_logger/features/directory/services/equipment_deletion_summary.dart';
import 'package:flutter_test/flutter_test.dart';

EquipmentDeletionSummary _summary({
  String code = '2113',
  String? ownerName,
  String? departmentName,
  String? phone,
  int calls = 0,
  int tasks = 0,
  DateTime? lastCallAt,
  DateTime? lastTaskAt,
}) {
  return EquipmentDeletionSummary(
    equipmentId: 1,
    code: code,
    ownerName: ownerName,
    departmentName: departmentName,
    phone: phone,
    callCount: calls,
    taskCount: tasks,
    lastCallAt: lastCallAt,
    lastTaskAt: lastTaskAt,
  );
}

void main() {
  group('Ποιος κρατά τον εξοπλισμό', () {
    test('υπάλληλος-κάτοχος', () {
      expect(_summary(ownerName: 'Μαρία Α').titleLine, '2113 → Μαρία Α');
    });

    test('χωρίς υπάλληλο μπαίνει το τμήμα — αλλιώς είναι σκέτος αριθμός', () {
      expect(
        _summary(departmentName: 'Αιμοδοσία').titleLine,
        '2113 → τμήμα Αιμοδοσία',
      );
    });

    test('ο υπάλληλος υπερισχύει του τμήματος', () {
      expect(
        _summary(ownerName: 'Μαρία Α', departmentName: 'Αιμοδοσία').titleLine,
        '2113 → Μαρία Α',
      );
    });

    test('χωρίς κανένα από τα δύο το λέει ρητά', () {
      expect(_summary().titleLine, '2113 → χωρίς κάτοχο και τμήμα');
    });
  });

  group('Συντόμευση μεγάλου ονόματος', () {
    test('κοντό όνομα μένει ακέραιο', () {
      expect(equipmentOwnerLabel(ownerName: 'Μαρία Α'), 'Μαρία Α');
    });

    test('μεγάλο όνομα κρατά ακέραιο το επώνυμο', () {
      expect(
        equipmentOwnerLabel(ownerName: 'Κωνσταντίνα Παπαδοπούλου'),
        'Κω. Παπαδοπούλου',
      );
    });

    test('πολλά μικρά ονόματα συντομεύονται όλα', () {
      expect(
        compactPersonName('Άννα Μαρία Παπαδοπούλου'),
        'Άν. Μα. Παπαδοπούλου',
      );
    });

    test('μονολεκτικό όνομα μένει όπως είναι', () {
      expect(compactPersonName('Παπαδοπούλου'), 'Παπαδοπούλου');
    });
  });

  group('Τι αφήνει πίσω του', () {
    test('τηλέφωνο, κλήσεις και εκκρεμότητες με ημερομηνία', () {
      final lines = _summary(
        ownerName: 'Μαρία Α',
        phone: '2898',
        calls: 12,
        tasks: 1,
        lastCallAt: DateTime(2026, 6, 12),
        lastTaskAt: DateTime(2026, 7, 28),
      ).buildTraceLines();

      expect(lines, [
        'τηλ. 2898',
        '12 κλήσεις ιστορικού (τελευταία 12/06/2026)',
        '1 εκκρεμότητα (τελευταία 28/07/2026)',
      ]);
    });

    test('παραλείπει τα μηδενικά είδη', () {
      expect(
        _summary(calls: 1, lastCallAt: DateTime(2026, 6, 12)).buildTraceLines(),
        ['1 κλήση ιστορικού (τελευταία 12/06/2026)'],
      );
    });

    test('χωρίς ίχνη δεν γράφει τίποτα', () {
      final s = _summary(ownerName: 'Μαρία Α');

      expect(s.buildTraceLines(), isEmpty);
      expect(s.hasTraces, isFalse);
    });

    test('οι εκκρεμότητες μετράνε ως ίχνος, όχι μόνο οι κλήσεις', () {
      expect(_summary(tasks: 1).hasTraces, isTrue);
    });
  });
}
