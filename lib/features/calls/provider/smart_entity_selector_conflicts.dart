part of 'smart_entity_selector_provider.dart';

/// Σύνδεση της κατάστασης του επιλογέα με τη [ConflictEngine].
///
/// Εδώ **δεν** ζει κανένας κανόνας σύγκρουσης — μόνο η μετάφραση state →
/// στιγμιότυπο → state. Οι κανόνες ζουν στη μηχανή, ώστε να είναι τεστάριστοι
/// χωρίς provider.
mixin SmartEntitySelectorConflictsMixin on Notifier<SmartEntitySelectorState> {
  /// Τα ψηφία του πεδίου τηλεφώνου — κανονικοποιημένη μορφή για κάθε σύγκριση.
  String _phoneDigitsOfState() =>
      state.selectedPhone?.replaceAll(RegExp(r'[^0-9]'), '').trim() ?? '';

  ConflictSnapshot _snapshotOfState() => ConflictSnapshot(
    phoneDigits: _phoneDigitsOfState(),
    caller: state.selectedCaller,
    callerText: state.callerDisplayText,
    departmentId: state.selectedDepartmentId,
    departmentText: state.departmentText,
    equipment: state.selectedEquipment,
    equipmentText: state.equipmentText,
  );

  /// Νέα σειρά επικύρωσης: κρατά όσα πεδία παραμένουν **συμπληρωμένα**
  /// με την αρχική τους σειρά και προσθέτει στο τέλος το [committed] — το πεδίο
  /// που μόλις επικύρωσε ο χρήστης.
  ///
  /// Δεν απαιτείται το πεδίο να υπάρχει στη βάση. Πεδία που γέμισαν με autofill
  /// δεν φτάνουν ποτέ εδώ ως [committed], άρα δεν γίνονται ποτέ άγκυρα.
  List<SelectorField> _nextCommitOrder(
    SelectorField? committed,
    Set<SelectorField> filled,
  ) {
    final next = state.identificationOrder
        .where(filled.contains)
        .toList(growable: true);
    if (committed != null &&
        filled.contains(committed) &&
        !next.contains(committed)) {
      next.add(committed);
    }
    return next;
  }

  /// Επανυπολογισμός **όλων** των δεικτών εξ αρχής.
  ///
  /// Το [committed] δεν συμμετέχει στον υπολογισμό των σχέσεων — χρησιμεύει
  /// **μόνο** ως υποψήφια άγκυρα (§Α.6). Ίδιο state ⇒ ίδιοι δείκτες, όποιο κι
  /// αν είναι το [committed] (§Α.3, κανόνας ανεξαρτησίας από την εστίαση).
  void _recomputeConflicts(SelectorField? committed, LookupService? lookup) {
    if (lookup == null) {
      if (state.conflicts.isNotEmpty) {
        state = state.copyWith(clearConflicts: true);
      }
      return;
    }
    final result = ConflictEngine(
      snapshot: _snapshotOfState(),
      lookup: lookup,
    ).run();
    final order = _nextCommitOrder(committed, result.filledFields);
    state = state.copyWith(
      conflicts: result.conflicts,
      clearConflicts: result.conflicts.isEmpty,
      identificationOrder: order,
      clearIdentificationOrder: order.isEmpty,
    );
  }

  /// Επανυπολογισμός χωρίς νέα υποψήφια άγκυρα — για φόρτωση έτοιμης φόρμας
  /// (Ιστορικό/Εκκρεμότητες, §Α.6) όπου κανένα πεδίο δεν επικυρώθηκε.
  void _refreshConflictsWithoutAnchor() {
    _recomputeConflicts(null, ref.read(lookupServiceProvider).value?.service);
  }
}
