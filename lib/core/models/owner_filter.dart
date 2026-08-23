/// Ποιανού εγγραφές δείχνει μια λίστα — εκκρεμότητες, κλήσεις, ό,τι σφραγίζεται με χρήστη.
///
/// **Τρεις καταστάσεις, όχι δύο.** Πέρα από «όλοι» και «ένας συγκεκριμένος»
/// υπάρχει και το «όσες δεν ανήκουν σε κανέναν» — και αυτό δεν είναι απουσία
/// επιλογής, είναι επιλογή. Εκεί ζουν όλες οι εκκρεμότητες που γράφτηκαν πριν
/// αποκτήσει η εφαρμογή ταυτότητα χρήστη· αν δεν είχαν δικό τους ονομαστικό
/// φίλτρο, δεν θα υπήρχε τρόπος να βρεθούν.
class OwnerFilter {
  const OwnerFilter._(this.operatorId, this.unassignedOnly);

  /// Χωρίς περιορισμό — όλες οι εγγραφές, όποιος κι αν τις άνοιξε.
  static const OwnerFilter everyone = OwnerFilter._(null, false);

  /// Μόνο όσες δεν έχουν καταγεγραμμένο χρήστη.
  static const OwnerFilter unassigned = OwnerFilter._(null, true);

  /// Μόνο όσες άνοιξε ο συγκεκριμένος χρήστης.
  const OwnerFilter.byOperator(int id) : this._(id, false);

  /// Το id του χρήστη, όταν το φίλτρο δείχνει έναν συγκεκριμένο.
  final int? operatorId;

  /// True όταν το φίλτρο δείχνει τις αδέσποτες.
  final bool unassignedOnly;

  bool get isEveryone => operatorId == null && !unassignedOnly;

  /// Η μορφή που αποθηκεύεται στις προσωπικές ρυθμίσεις.
  ///
  /// Κείμενο και όχι αριθμός, ώστε οι τρεις καταστάσεις να ξεχωρίζουν χωρίς
  /// μαγικές τιμές: το `0` ή το `-1` ως «όλοι» θα ήταν id που κάποτε μπορεί να
  /// υπάρξει στ' αλήθεια.
  String get storageValue {
    if (unassignedOnly) return _unassignedToken;
    final id = operatorId;
    return id == null ? _everyoneToken : '$id';
  }

  /// Διαβάζει αποθηκευμένη επιλογή· `null` όταν δεν υπάρχει ή δεν διαβάζεται.
  ///
  /// Άγνωστο κείμενο δεν πέφτει σε προεπιλογή εδώ: ο καλών ξέρει τι σημαίνει
  /// «δεν έχω αποθηκευμένη τιμή» για τη δική του οθόνη.
  static OwnerFilter? fromStorage(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return null;
    if (value == _everyoneToken) return everyone;
    if (value == _unassignedToken) return unassigned;
    final id = int.tryParse(value);
    if (id == null) return null;
    return OwnerFilter.byOperator(id);
  }

  static const String _everyoneToken = 'all';
  static const String _unassignedToken = 'none';

  @override
  bool operator ==(Object other) =>
      other is OwnerFilter &&
      other.operatorId == operatorId &&
      other.unassignedOnly == unassignedOnly;

  @override
  int get hashCode => Object.hash(operatorId, unassignedOnly);

  @override
  String toString() => 'OwnerFilter($storageValue)';
}

/// Μία επιλογή του φίλτρου «χρήστης» — τιμή και ετικέτα οθόνης.
class OwnerFilterOption {
  const OwnerFilterOption({required this.value, required this.label});

  final OwnerFilter value;
  final String label;
}
