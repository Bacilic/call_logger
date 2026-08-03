import 'package:call_logger/features/tasks/ui/task_due_quick_chips.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatTaskDuePreview', () {
    final now = DateTime(2026, 7, 31, 18, 43); // Παρασκευή

    test('ίδια ημέρα: μόνο ώρα', () {
      expect(formatTaskDuePreview(now, DateTime(2026, 7, 31, 19, 43)), '19:43');
    });

    test('μεσάνυχτα της ίδιας ημέρας: μόνο ώρα, με μηδενικά', () {
      expect(formatTaskDuePreview(now, DateTime(2026, 7, 31, 8, 5)), '08:05');
    });

    test('αύριο: τρίγραμμο ημέρας και ώρα', () {
      expect(
        formatTaskDuePreview(now, DateTime(2026, 8, 1, 8)),
        'ΣΑΒ 08:00',
      );
    });

    test('έκτη ημέρα μπροστά: ακόμη τρίγραμμο ημέρας', () {
      expect(
        formatTaskDuePreview(now, DateTime(2026, 8, 6, 8)),
        'ΠΕΜ 08:00',
      );
    });

    test('έβδομη ημέρα μπροστά: ημερομηνία, ώστε να μην μπερδεύεται η εβδομάδα', () {
      expect(
        formatTaskDuePreview(now, DateTime(2026, 8, 7, 8)),
        '07/08 08:00',
      );
    });

    test('παρελθόν: ημερομηνία', () {
      expect(
        formatTaskDuePreview(now, DateTime(2026, 7, 30, 8)),
        '30/07 08:00',
      );
    });
  });
}
