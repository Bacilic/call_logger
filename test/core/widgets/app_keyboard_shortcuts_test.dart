// Έλεγχοι καθολικών συντομεύσεων πληκτρολογίου.
//
//   flutter test test/core/widgets/app_keyboard_shortcuts_test.dart

import 'package:call_logger/core/widgets/app_keyboard_shortcuts.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Τα intents στα οποία οδηγεί ο συνδυασμός με τον δεδομένο χαρακτήρα.
List<Intent> _intentsForCharacter(
  Map<ShortcutActivator, Intent> shortcuts,
  String character,
) => shortcuts.entries
    .where(
      (e) =>
          e.key is CharacterActivator &&
          (e.key as CharacterActivator).character == character &&
          (e.key as CharacterActivator).control &&
          !(e.key as CharacterActivator).alt,
    )
    .map((e) => e.value)
    .toList();

Intent? _intentForLogicalKey(
  Map<ShortcutActivator, Intent> shortcuts,
  LogicalKeyboardKey key,
) {
  for (final entry in shortcuts.entries) {
    final activator = entry.key;
    if (activator is SingleActivator &&
        activator.trigger == key &&
        activator.control &&
        activator.shift &&
        !activator.alt) {
      return entry.value;
    }
  }
  return null;
}

void main() {
  group('Γρήγορη κλήση — Ctrl+Shift+N', () {
    test('δηλωμένο και στις δύο διατάξεις πληκτρολογίου', () {
      final shortcuts = appKeyboardShortcuts;

      expect(
        _intentForLogicalKey(shortcuts, LogicalKeyboardKey.keyN),
        isA<QuickCaptureIntent>(),
      );
      expect(_intentsForCharacter(shortcuts, 'N'), [
        isA<QuickCaptureIntent>(),
      ]);
      expect(_intentsForCharacter(shortcuts, 'Ν'), [
        isA<QuickCaptureIntent>(),
      ]);
    });

    test('το παλιό Ctrl+Alt+L δεν επανήλθε', () {
      final shortcuts = appKeyboardShortcuts;

      expect(
        shortcuts.keys.whereType<SingleActivator>().any(
          (a) => a.trigger == LogicalKeyboardKey.keyL && a.control && a.alt,
        ),
        isFalse,
      );
    });
  });

  group('Αναφορά Lansweeper — Ctrl+Shift+L', () {
    test('δηλωμένο και στις δύο διατάξεις πληκτρολογίου', () {
      final shortcuts = appKeyboardShortcuts;

      expect(
        _intentForLogicalKey(shortcuts, LogicalKeyboardKey.keyL),
        isA<LansweeperReportIntent>(),
      );
      expect(_intentsForCharacter(shortcuts, 'L'), [
        isA<LansweeperReportIntent>(),
      ]);
      expect(_intentsForCharacter(shortcuts, 'Λ'), [
        isA<LansweeperReportIntent>(),
      ]);
    });
  });

  test('κάθε συνδυασμός οδηγεί σε ένα μόνο intent', () {
    final shortcuts = appKeyboardShortcuts;

    expect(shortcuts.length, 6);
  });
}
