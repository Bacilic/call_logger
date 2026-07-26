import 'package:call_logger/features/directory/screens/widgets/shared_asset_disconnect_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatAssetReferenceDeleteMessage', () {
    test('κενή λίστα → μήνυμα χωρίς συνδέσεις (τηλέφωνο)', () {
      expect(
        formatAssetReferenceDeleteMessage(
          isPhone: true,
          value: '2851',
          descriptions: const [],
        ),
        'Ο αριθμός 2851 δεν συνδέεται με άλλες εγγραφές. Να καταργηθεί;',
      );
    });

    test('κενή λίστα → μήνυμα χωρίς συνδέσεις (εξοπλισμός)', () {
      expect(
        formatAssetReferenceDeleteMessage(
          isPhone: false,
          value: '3601',
          descriptions: const [],
        ),
        'Ο εξοπλισμός 3601 δεν συνδέεται με άλλες εγγραφές. Να καταργηθεί;',
      );
    });

    test('≤4 περιγραφές → όλες με κουκκίδες', () {
      final text = formatAssetReferenceDeleteMessage(
        isPhone: true,
        value: '2851',
        descriptions: const [
          'Άννα Πατσαρίκα',
          'Πληροφορική',
          '2 εκκρεμότητες',
          '3 κλήσεις ιστορικού',
        ],
      );
      expect(
        text,
        'Ο αριθμός 2851 συνδέεται με:\n'
        '• Άννα Πατσαρίκα\n'
        '• Πληροφορική\n'
        '• 2 εκκρεμότητες\n'
        '• 3 κλήσεις ιστορικού\n'
        'Να καταργηθεί;',
      );
      expect(text.contains('ακόμα'), isFalse);
    });

    test('≥5 περιγραφές → 5 πρώτες + «…και M ακόμα»', () {
      final text = formatAssetReferenceDeleteMessage(
        isPhone: false,
        value: '3601',
        descriptions: const ['Α', 'Β', 'Γ', 'Δ', 'Ε', 'ΣΤ', 'Ζ'],
      );
      expect(
        text,
        'Ο εξοπλισμός 3601 συνδέεται με:\n'
        '• Α\n'
        '• Β\n'
        '• Γ\n'
        '• Δ\n'
        '• Ε\n'
        '…και 2 ακόμα\n'
        'Να καταργηθεί;',
      );
      expect(text.contains('• ΣΤ'), isFalse);
    });
  });
}
