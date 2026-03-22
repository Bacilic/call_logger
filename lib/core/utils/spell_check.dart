import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Ενεργοποιεί native spell check μόνο σε πλατφόρμες με σταθερή υποστήριξη.
SpellCheckConfiguration? get platformSpellCheckConfiguration {
  if (kIsWeb) return null;
  // Το `flutter test` ορίζει FLUTTER_TEST=true — χωρίς εγγενή orthography υπηρεσία στα desktop tests.
  try {
    if (Platform.environment['FLUTTER_TEST'] == 'true') {
      return const SpellCheckConfiguration.disabled();
    }
  } catch (_) {}
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
      return const SpellCheckConfiguration();
    case TargetPlatform.fuchsia:
    case TargetPlatform.linux:
    case TargetPlatform.macOS:
    case TargetPlatform.windows:
      // Σε desktop/test χωρίς native υπηρεσία, ρητή απενεργοποίηση αποφεύγει assertion στα τεστ.
      return const SpellCheckConfiguration.disabled();
  }
}
