import 'package:call_logger/features/directory/services/equipment_deletion_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatEquipmentDeletionLines', () {
    test('πλήρης γραμμή με κάτοχο, τηλέφωνο και ιστορικό', () {
      final lines = formatEquipmentDeletionLines([
        const EquipmentDeletionSummary(
          code: '2113',
          ownerName: 'Αναστασία Φούφα',
          phone: '2898',
          historyCount: 12,
        ),
      ]);
      expect(
        lines,
        [
          '2113 → Αναστασία Φούφα · τηλ. 2898 · 12 εγγραφές ιστορικού',
        ],
      );
    });

    test('παραλείπει τηλέφωνο όταν λείπει', () {
      final lines = formatEquipmentDeletionLines([
        const EquipmentDeletionSummary(
          code: '2113',
          ownerName: 'Αναστασία Φούφα',
          phone: null,
          historyCount: 12,
        ),
      ]);
      expect(
        lines.single,
        '2113 → Αναστασία Φούφα · 12 εγγραφές ιστορικού',
      );
    });

    test('χωρίς κάτοχο: μόνο κωδικός και ιστορικό', () {
      final lines = formatEquipmentDeletionLines([
        const EquipmentDeletionSummary(
          code: '3974',
          ownerName: null,
          phone: null,
          historyCount: 0,
        ),
      ]);
      expect(lines.single, '3974 · 0 εγγραφές ιστορικού');
    });

    test('μία εγγραφή ιστορικού (ενικός)', () {
      final lines = formatEquipmentDeletionLines([
        const EquipmentDeletionSummary(
          code: '1001',
          ownerName: 'Μαρία Α',
          phone: '2200',
          historyCount: 1,
        ),
      ]);
      expect(
        lines.single,
        '1001 → Μαρία Α · τηλ. 2200 · 1 εγγραφή ιστορικού',
      );
    });

    test('πολλές περίληψεις → μία γραμμή ανά εξοπλισμό', () {
      final lines = formatEquipmentDeletionLines([
        const EquipmentDeletionSummary(
          code: 'A',
          ownerName: 'Υ1',
          phone: '1',
          historyCount: 2,
        ),
        const EquipmentDeletionSummary(
          code: 'B',
          historyCount: 0,
        ),
      ]);
      expect(lines, [
        'A → Υ1 · τηλ. 1 · 2 εγγραφές ιστορικού',
        'B · 0 εγγραφές ιστορικού',
      ]);
    });
  });
}
