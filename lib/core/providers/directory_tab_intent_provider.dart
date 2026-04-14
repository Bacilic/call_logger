import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Κατανάλωση από [DirectoryScreen]: animateTo στο TabController.
class DirectoryTabIntentNotifier extends Notifier<int?> {
  @override
  int? build() => null;

  void jumpTo(int index) {
    state = index;
  }

  void clear() {
    state = null;
  }
}

final directoryTabIntentProvider =
    NotifierProvider<DirectoryTabIntentNotifier, int?>(
  DirectoryTabIntentNotifier.new,
);
