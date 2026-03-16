import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Ενεργοποιεί native spell check μόνο σε πλατφόρμες με σταθερή υποστήριξη.
SpellCheckConfiguration? get platformSpellCheckConfiguration {
  if (kIsWeb) return null;
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
      return const SpellCheckConfiguration();
    case TargetPlatform.fuchsia:
    case TargetPlatform.linux:
    case TargetPlatform.macOS:
    case TargetPlatform.windows:
      return null;
  }
}
