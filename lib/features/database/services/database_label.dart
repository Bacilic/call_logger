/// Κλειδί `app_settings` για το όνομα που έδωσε ο χρήστης στη βάση.
///
/// Ζει **μέσα** στη βάση, όχι στις τοπικές ρυθμίσεις: το όνομα ταξιδεύει μαζί
/// με το αρχείο. Ένα αντίγραφο που θα ανοίξει σε άλλο μηχάνημα εξακολουθεί να
/// ξέρει τι είναι — αυτό ακριβώς είναι το ζητούμενο όταν στον επιλογέα
/// διαδρομών υπάρχουν τρία αρχεία με ονόματα που δεν λένε τίποτα.
///
/// Η ανάγνωση και η εγγραφή ζουν στο `DatabaseIdentityRepository`· εδώ μένει
/// μόνο ο κανόνας καθαρισμού, χωρίς καμία εξάρτηση από τη βάση.
const String kDatabaseLabelSettingsKey = 'database_label';

/// Πόσο μακρύ επιτρέπεται να είναι το όνομα.
///
/// Δεν είναι περιγραφή· είναι ετικέτα που πρέπει να χωρά σε μία γραμμή δίπλα
/// στα υπόλοιπα στοιχεία.
const int kDatabaseLabelMaxLength = 40;

/// Καθαρίζει ό,τι πληκτρολόγησε ο χρήστης.
///
/// Κενό, μόνο κενά ή `null` σημαίνουν «χωρίς όνομα» — και επιστρέφουν `null`,
/// ώστε να υπάρχει ΜΙΑ αναπαράσταση της απουσίας αντί για δύο. Οι αλλαγές
/// γραμμής και τα διπλά κενά ισοπεδώνονται: μια ετικέτα μιας γραμμής δεν έχει
/// λόγο να κουβαλά μορφοποίηση.
String? normalizeDatabaseLabel(String? raw) {
  if (raw == null) return null;
  final collapsed = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (collapsed.isEmpty) return null;
  if (collapsed.length <= kDatabaseLabelMaxLength) return collapsed;
  return collapsed.substring(0, kDatabaseLabelMaxLength).trimRight();
}
