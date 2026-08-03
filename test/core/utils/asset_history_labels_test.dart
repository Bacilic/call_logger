// Unit tests: διατύπωση ιστορικών συνδέσεων με ημερομηνία τελευταίας χρήσης.
//
//   flutter test test/core/utils/asset_history_labels_test.dart

import 'package:call_logger/core/utils/asset_history_labels.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('εκκρεμότητες', () {
    test('με χρονοσήμανση → πλήθος και πότε ήταν η τελευταία', () {
      expect(
        taskHistoryLabel(2, lastUsedAt: DateTime(2026, 6, 12)),
        '2 εκκρεμότητες (τελευταία 12/06/2026)',
      );
    });

    test('μία εκκρεμότητα → ενικός', () {
      expect(
        taskHistoryLabel(1, lastUsedAt: DateTime(2026, 6, 12)),
        '1 εκκρεμότητα (τελευταία 12/06/2026)',
      );
    });

    test('χωρίς χρονοσήμανση → μόνο το πλήθος, χωρίς παρένθεση', () {
      expect(taskHistoryLabel(3), '3 εκκρεμότητες');
    });
  });

  group('κλήσεις ιστορικού', () {
    test('με χρονοσήμανση → πλήθος και πότε ήταν η τελευταία', () {
      expect(
        callHistoryLabel(5, lastUsedAt: DateTime(2026, 6, 12)),
        '5 κλήσεις ιστορικού (τελευταία 12/06/2026)',
      );
    });

    test('μία κλήση → ενικός', () {
      expect(
        callHistoryLabel(1, lastUsedAt: DateTime(2020, 1, 3)),
        '1 κλήση ιστορικού (τελευταία 03/01/2020)',
      );
    });

    test('χωρίς χρονοσήμανση → μόνο το πλήθος, χωρίς παρένθεση', () {
      expect(callHistoryLabel(4), '4 κλήσεις ιστορικού');
    });
  });
}
