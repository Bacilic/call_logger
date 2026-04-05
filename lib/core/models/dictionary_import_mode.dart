/// Τρόπος εισαγωγής στον πίνακα `full_dictionary`.
enum DictionaryImportMode {
  /// INSERT OR IGNORE — δεν αντικαθιστά υπάρχουσες λέξεις.
  enrich,

  /// Διαγραφή όλου του `full_dictionary` πριν την εισαγωγή (το `user_dictionary` δεν αγγίζεται).
  replace,
}
