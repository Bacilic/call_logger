import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Οι καρτέλες των «Ρυθμίσεων βάσης δεδομένων», με τη σειρά που εμφανίζονται.
///
/// Υπάρχει επειδή ο δείκτης της καρτέλας ταξιδεύει ως **γυμνός αριθμός** από
/// τον καλούντα ως τον διάλογο. Με σκέτο `openTab(1)` σε κάθε σημείο, μια
/// μελλοντική αναδιάταξη των καρτελών θα έστελνε σιωπηλά τον χειριστή σε λάθος
/// οθόνη — χωρίς να σπάσει τίποτα και χωρίς να το προσέξει κανείς.
enum DatabaseSettingsTab {
  database('Βάση'),
  backups('Αντίγραφα ασφαλείας'),
  restore('Επαναφορά'),
  maintenance('Συντήρηση');

  const DatabaseSettingsTab(this.label);

  /// Η ετικέτα που βλέπει ο χειριστής. Ζει δίπλα στη σειρά ώστε το ένα να
  /// επαληθεύει το άλλο.
  final String label;
}

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

  /// Προτιμότερο από το [openTab]: ζητά καρτέλα με το όνομά της.
  void open(DatabaseSettingsTab tab) => openTab(tab.index);

  void clear() {
    state = null;
  }
}

final databaseSettingsRouteIntentProvider =
    NotifierProvider<
      DatabaseSettingsRouteIntentNotifier,
      DatabaseSettingsRouteRequest?
    >(DatabaseSettingsRouteIntentNotifier.new);
