import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Όταν αυξάνεται, η καρτέλα «Διάφορα» ανοίγει την υπο-οθόνη «Απομακρυσμένα
/// Εργαλεία».
///
/// Περνά από δίαυλο και όχι από callback του γονέα, ώστε όποιος ζητά τη
/// μετάβαση να μην χρειάζεται να ξέρει ότι βρίσκεται μέσα στο hub — ίδιος
/// τρόπος με τους υπόλοιπους προορισμούς διόρθωσης διαδρομών.
class RemoteToolsViewRequestNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void request() {
    state = state + 1;
  }
}

final remoteToolsViewRequestProvider =
    NotifierProvider<RemoteToolsViewRequestNotifier, int>(
      RemoteToolsViewRequestNotifier.new,
    );
