import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Intent για γρήγορη καταγραφή κλήσης εκτός κύριας φόρμας.
class QuickCaptureIntent extends Intent {
  const QuickCaptureIntent();
}

/// Intent για την Αναφορά Lansweeper με τις σημερινές κλήσεις.
class LansweeperReportIntent extends Intent {
  const LansweeperReportIntent();
}

/// Καθολικές συντομεύσεις της εφαρμογής.
///
/// Κάθε συνδυασμός δηλώνεται **δύο φορές**: με λογικό πλήκτρο για την αγγλική
/// διάταξη και με χαρακτήρα για την ελληνική. Χωρίς τη δεύτερη εγγραφή η
/// συντόμευση σιωπά όσο ο χρήστης γράφει ελληνικά — δηλαδή τις μισές ώρες.
Map<ShortcutActivator, Intent> get appKeyboardShortcuts =>
    <ShortcutActivator, Intent>{
      SingleActivator(LogicalKeyboardKey.keyN, control: true, shift: true):
          const QuickCaptureIntent(),
      const CharacterActivator('N', control: true): const QuickCaptureIntent(),
      const CharacterActivator('Ν', control: true): const QuickCaptureIntent(),
      SingleActivator(LogicalKeyboardKey.keyL, control: true, shift: true):
          const LansweeperReportIntent(),
      const CharacterActivator('L', control: true):
          const LansweeperReportIntent(),
      const CharacterActivator('Λ', control: true):
          const LansweeperReportIntent(),
    };
