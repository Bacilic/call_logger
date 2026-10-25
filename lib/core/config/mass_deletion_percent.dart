// Το όριο της προειδοποίησης μαζικής διαγραφής — κοινή ρύθμιση της βάσης.
//
// Ζει στο core επειδή το διαβάζει η υπηρεσία ρυθμίσεων· ο κανόνας που το
// χρησιμοποιεί είναι στο `features/directory/services/mass_deletion_guard.dart`.

/// Το ποσοστό του καταλόγου από το οποίο και πάνω μια διαγραφή προειδοποιεί.
const int kDefaultMassDeletionPercent = 50;
const int kMinMassDeletionPercent = 10;

/// Το 100% δεν ρυθμίζεται: έχει δική του, πιο αυστηρή προειδοποίηση.
const int kMaxMassDeletionPercent = 90;

/// Η τιμή που ισχύει: ό,τι λείπει γίνεται η προεπιλογή, ό,τι βγαίνει έξω από
/// τα όρια κόβεται στο πλησιέστερο.
int normalizeMassDeletionPercent(int? value) {
  if (value == null) return kDefaultMassDeletionPercent;
  return value.clamp(kMinMassDeletionPercent, kMaxMassDeletionPercent);
}
