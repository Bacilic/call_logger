/// Η κατάσταση του πεδίου «Τοποθεσία» στη φόρμα εξοπλισμού.
///
/// Ζει έξω από το widget επειδή είναι μηχανή καταστάσεων με τρεις μεταβάσεις
/// και δύο παγίδες: το τσεκάρισμα δεν πρέπει να καταπίνει τη δική του τιμή, και
/// η αποθήκευση δεν πρέπει να γράφει αντίγραφο της τιμής του κατόχου.
class EquipmentLocationFieldState {
  const EquipmentLocationFieldState({
    required this.followsOwner,
    required this.ownText,
    required this.ownerLocation,
  });

  /// Αρχική κατάσταση από τη βάση: κενό `location` σημαίνει «ακολουθεί».
  factory EquipmentLocationFieldState.fromStored({
    String? storedLocation,
    String? ownerLocation,
  }) {
    final own = (storedLocation ?? '').trim();
    return EquipmentLocationFieldState(
      followsOwner: own.isEmpty,
      ownText: own,
      ownerLocation: (ownerLocation ?? '').trim(),
    );
  }

  final bool followsOwner;

  /// Η δική του τοποθεσία — θυμάται ακόμα κι όσο ο διακόπτης είναι αναμμένος,
  /// ώστε το ξετσεκάρισμα να λειτουργεί ως αναίρεση.
  final String ownText;

  final String ownerLocation;

  /// Το κείμενο που βλέπει ο χρήστης μέσα στο πεδίο.
  String get displayText => followsOwner ? ownerLocation : ownText;

  /// Τι γράφεται στη βάση: `null` σημαίνει «ακολουθεί τον κάτοχο».
  ///
  /// Τιμή ταυτόσημη με του κατόχου **δεν** αποθηκεύεται ως δική του: θα ήταν
  /// αντίγραφο που παγώνει, και μια μετακόμιση του ανθρώπου θα το άφηνε πίσω.
  String? get valueToStore {
    if (followsOwner) return null;
    if (ownText.isEmpty) return null;
    if (ownText == ownerLocation) return null;
    return ownText;
  }

  /// True όταν ο εξοπλισμός θα καταλήξει με δική του, διαφορετική θέση.
  bool get diverges => valueToStore != null;

  /// Άναμμα του διακόπτη — η δική του τιμή μπαίνει στην άκρη, δεν χάνεται.
  EquipmentLocationFieldState follow() => EquipmentLocationFieldState(
    followsOwner: true,
    ownText: ownText,
    ownerLocation: ownerLocation,
  );

  /// Σβήσιμο του διακόπτη.
  ///
  /// Αν υπήρχε δική του τιμή, επιστρέφει — το τσεκάρισμα/ξετσεκάρισμα είναι
  /// αναίρεση. Αν δεν υπήρξε ποτέ, ξεκινά από τη θέση του κατόχου ώστε ο
  /// χρήστης να τη διορθώσει αντί να γράψει από λευκή σελίδα.
  EquipmentLocationFieldState unfollow() => EquipmentLocationFieldState(
    followsOwner: false,
    ownText: ownText.isEmpty ? ownerLocation : ownText,
    ownerLocation: ownerLocation,
  );

  /// Πληκτρολόγηση: ό,τι γράφει ο χρήστης γίνεται η δική του τιμή.
  EquipmentLocationFieldState typed(String text) => EquipmentLocationFieldState(
    followsOwner: false,
    ownText: text.trim(),
    ownerLocation: ownerLocation,
  );

  /// Αλλαγή κατόχου: η δική του τιμή μένει, η αναφορά αλλάζει.
  EquipmentLocationFieldState withOwnerLocation(String? location) =>
      EquipmentLocationFieldState(
        followsOwner: followsOwner,
        ownText: ownText,
        ownerLocation: (location ?? '').trim(),
      );
}
