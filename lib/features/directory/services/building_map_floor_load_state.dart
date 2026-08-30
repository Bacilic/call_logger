/// Τι ξέρει η καρτέλα τμήματος για τις κατόψεις του κτιρίου.
///
/// Ξεχωρίζει τρεις καταστάσεις που έμοιαζαν δύο όσο ταξίδευαν ως σκέτη σημαία
/// «ολοκληρώθηκε»: η **αποτυχία ανάγνωσης** σημαδευόταν ως ολοκληρωμένη
/// φόρτωση με άδεια λίστα, οπότε ο χαρτογραφημένος όροφος εμφανιζόταν ως
/// «δεν βρέθηκε κάτοψη» — και όποιος πίστευε το μήνυμα και επέλεγε «— χωρίς —»
/// έσβηνε θέση, διαστάσεις και περιστροφή του τμήματος στον χάρτη.
enum BuildingMapFloorLoadState {
  /// Δεν έχει απαντήσει ακόμη η βάση.
  loading,

  /// Διαβάστηκε — η λίστα λέει την αλήθεια, άδεια ή όχι.
  loaded,

  /// ΔΕΝ διαβάστηκε: η λίστα είναι άδεια από άγνοια, όχι από απουσία.
  failed;

  bool get isLoaded => this == BuildingMapFloorLoadState.loaded;

  /// Επιτρέπεται να αλλάξει ο χρήστης τον όροφο;
  ///
  /// Μόνο με διαβασμένες κατόψεις: όσο είναι άγνωστες, κάθε επιλογή θα γινόταν
  /// στα τυφλά — και η μόνη διαθέσιμη («— χωρίς —») σβήνει τη χαρτογράφηση.
  bool get allowsFloorChange => isLoaded;
}

/// Το μήνυμα κάτω από το πεδίο «Όροφος», ή `null` όταν δεν χρειάζεται.
///
/// Ζει έξω από το widget ώστε η υπόσχεση να ελέγχεται χωρίς να χτιστεί οθόνη.
String? buildingMapFloorLoadNotice(BuildingMapFloorLoadState state) {
  return switch (state) {
    BuildingMapFloorLoadState.loading => null,
    BuildingMapFloorLoadState.loaded => null,
    BuildingMapFloorLoadState.failed =>
      'Οι κάτοψεις δεν φορτώθηκαν — η βάση ήταν απασχολημένη. Ο όροφος του '
          'τμήματος μένει όπως είναι· ξανανοίξτε την καρτέλα για να τον '
          'αλλάξετε.',
  };
}

/// Πρέπει η αποθήκευση να σβήσει τη θέση του τμήματος στον χάρτη κτιρίου;
///
/// Σβήνει **μόνο** όταν ο χρήστης αφαίρεσε ηθελημένα τον όροφο από μια
/// καρτέλα που τον είχε — και μόνο με **διαβασμένες** κατόψεις. Με άγνωστες,
/// το κενό πεδίο δεν είναι επιλογή του χρήστη αλλά συνέπεια της αποτυχίας:
/// σβήνοντας τότε, θα χανόταν θέση, διαστάσεις και περιστροφή επειδή η βάση
/// ήταν στιγμιαία απασχολημένη.
///
/// Δεύτερη γραμμή άμυνας πίσω από το κλειδωμένο πεδίο — η επιλογή δεν φτάνει
/// καν εδώ, αλλά η αποθήκευση δεν στηρίζεται σε αυτό.
bool shouldClearBuildingMapPlacement({
  required bool isEdit,
  required int? selectedFloorId,
  required int? snapshotFloorId,
  required int? initialFloorId,
  required BuildingMapFloorLoadState floorLoadState,
}) {
  if (!isEdit) return false;
  if (!floorLoadState.isLoaded) return false;
  if (selectedFloorId != null) return false;
  return snapshotFloorId != null || initialFloorId != null;
}
