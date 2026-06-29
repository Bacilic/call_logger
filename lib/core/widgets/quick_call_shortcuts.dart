import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Intent για γρήγορη καταγραφή κλήσης εκτός κύριας φόρμας.
class QuickCaptureIntent extends Intent {
  const QuickCaptureIntent();
}

/// Συντομεύσεις γρήγορης κλήσης — μόνο Ctrl+Shift+N (EN + EL διάταξη).
Map<ShortcutActivator, Intent> get quickCallShortcuts =>
    <ShortcutActivator, Intent>{
      SingleActivator(LogicalKeyboardKey.keyN, control: true, shift: true):
          const QuickCaptureIntent(),
      const CharacterActivator('N', control: true):
          const QuickCaptureIntent(),
      const CharacterActivator('Ν', control: true):
          const QuickCaptureIntent(),
    };
