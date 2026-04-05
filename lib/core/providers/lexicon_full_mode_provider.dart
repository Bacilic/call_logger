import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Πλήρης immersive προβολή λεξικού (χωρίς AppBar / NavigationRail).
class LexiconFullModeNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setTrue() => state = true;

  void setFalse() => state = false;
}

final lexiconFullModeProvider =
    NotifierProvider<LexiconFullModeNotifier, bool>(LexiconFullModeNotifier.new);
