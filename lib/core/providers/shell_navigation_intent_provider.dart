import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/main_nav_destination.dart';

/// Προορισμός μετά έξοδο από immersive λεξικό· διαβάζεται από το [MainShell].
class ShellNavigationIntentNotifier extends Notifier<MainNavDestination?> {
  @override
  MainNavDestination? build() => null;

  void setPending(MainNavDestination destination) {
    state = destination;
  }

  /// Επιστρέφει και μηδενίζει την τελευταία πρόθεση (μία χρήση ανά έξοδο).
  MainNavDestination? takePending() {
    final v = state;
    state = null;
    return v;
  }
}

final shellNavigationIntentProvider =
    NotifierProvider<ShellNavigationIntentNotifier, MainNavDestination?>(
  ShellNavigationIntentNotifier.new,
);
