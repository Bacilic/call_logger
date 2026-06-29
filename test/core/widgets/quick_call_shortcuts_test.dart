// Έλεγχοι συντομεύσεων γρήγορης κλήσης.
//
//   flutter test test/core/widgets/quick_call_shortcuts_test.dart

import 'package:call_logger/core/widgets/quick_call_shortcuts.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Συντομεύσεις γρήγορης κλήσης', () {
    test('μόνο Ctrl+Shift+N (EN/EL) — όχι Ctrl+Alt+L/C', () {
      final shortcuts = quickCallShortcuts;

      expect(shortcuts.length, 3);
      expect(
        shortcuts.keys.whereType<SingleActivator>().any(
          (a) =>
              a.trigger == LogicalKeyboardKey.keyN &&
              a.control &&
              a.shift &&
              !a.alt,
        ),
        isTrue,
      );
      expect(
        shortcuts.keys.whereType<CharacterActivator>().any(
          (a) => a.character == 'N' && a.control && !a.alt,
        ),
        isTrue,
      );
      expect(
        shortcuts.keys.whereType<CharacterActivator>().any(
          (a) => a.character == 'Ν' && a.control && !a.alt,
        ),
        isTrue,
      );
      expect(
        shortcuts.keys.whereType<SingleActivator>().any(
          (a) =>
              a.trigger == LogicalKeyboardKey.keyL && a.control && a.alt,
        ),
        isFalse,
      );
      for (final intent in shortcuts.values) {
        expect(intent, isA<QuickCaptureIntent>());
      }
    });
  });
}
