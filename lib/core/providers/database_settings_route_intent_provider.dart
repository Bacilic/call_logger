import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Ποια καρτέλα των «Ρυθμίσεων βάσης δεδομένων» ζητήθηκε — και μια αύξουσα
/// σφραγίδα, ώστε δύο διαδοχικά αιτήματα για την ίδια καρτέλα να ξεχωρίζουν.
class DatabaseSettingsRouteRequest {
  const DatabaseSettingsRouteRequest({
    required this.tabIndex,
    required this.sequence,
  });

  final int tabIndex;
  final int sequence;
}

/// Αίτημα ανοίγματος των «Ρυθμίσεων βάσης δεδομένων» σε συγκεκριμένη καρτέλα.
///
/// Ο διάλογος είναι αυτόνομος, οπότε δεν χρειάζεται αλλαγή οθόνης: ανοίγει
/// **πάνω** από εκεί που στέκεται ο χρήστης. Έτσι κρατά τη δουλειά του — ένας
/// έλεγχος διαδρομών που μόλις έτρεξε δεν σβήνεται για να δει μια ρύθμιση.
///
/// Το άνοιγμα το κάνει το κέλυφος και όχι ο καλών, γιατί μόνο εκείνο κρατά τον
/// χειριστή «άλλαξε η βάση»: ανοιγμένος με κενό χειριστή, ο διάλογος θα άλλαζε
/// αρχείο βάσης χωρίς να το μάθει η υπόλοιπη εφαρμογή.
class DatabaseSettingsRouteIntentNotifier
    extends Notifier<DatabaseSettingsRouteRequest?> {
  int _sequence = 0;

  @override
  DatabaseSettingsRouteRequest? build() => null;

  void openTab(int tabIndex) {
    _sequence += 1;
    state = DatabaseSettingsRouteRequest(
      tabIndex: tabIndex,
      sequence: _sequence,
    );
  }

  void clear() {
    state = null;
  }
}

final databaseSettingsRouteIntentProvider =
    NotifierProvider<
      DatabaseSettingsRouteIntentNotifier,
      DatabaseSettingsRouteRequest?
    >(DatabaseSettingsRouteIntentNotifier.new);
