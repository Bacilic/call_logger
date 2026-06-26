import 'package:call_logger/core/services/lansweeper_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LansweeperSyncService.buildTicketDescription', () {
    test('προσθέτει διάρκεια στο τέλος', () {
      final description = LansweeperSyncService.buildTicketDescription(
        notes: 'Πρόβλημα με εκτυπωτή',
        solution: 'Επανεκκίνηση',
        durationSeconds: 125,
      );

      expect(description, contains('Πρόβλημα με εκτυπωτή'));
      expect(description, contains('Λύση:\nΕπανεκκίνηση'));
      expect(description, endsWith('Χρόνος: 02:05'));
    });

    test('χωρίς διάρκεια δεν προσθέτει γραμμή Χρόνος', () {
      final description = LansweeperSyncService.buildTicketDescription(
        notes: 'Σημειώσεις',
        solution: '',
      );

      expect(description, 'Σημειώσεις');
      expect(description, isNot(contains('Χρόνος:')));
    });

    test('formatCallDurationLabel ώρες ως HH:MM', () {
      expect(
        LansweeperSyncService.formatCallDurationLabel(3725),
        '01:02',
      );
    });
  });
}
