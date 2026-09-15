import 'dart:io';

/// Το όνομα του υπολογιστή που τρέχει αυτό το αντίγραφο.
///
/// Ζει σε δικό του αρχείο γιατί το χρειάζονται **δύο ανεξάρτητοι κόσμοι**: η
/// παρουσία χρήστη, που γράφει στη βάση, και το ημερολόγιο σφαλμάτων, που
/// γράφει σε αρχεία **πριν καν υπάρξει βάση**. Αν το κρατούσε ο ένας, ο άλλος
/// θα έφτιαχνε δικό του αντίγραφο — και τα δύο θα απέκλιναν σιωπηλά.
class StationName {
  const StationName._();

  /// Πώς διαβάζεται ο σταθμός. Αντικαθίσταται στα τεστ.
  static String Function() reader = defaultReader;

  static String defaultReader() {
    final fromEnvironment = Platform.environment['COMPUTERNAME']?.trim();
    if (fromEnvironment != null && fromEnvironment.isNotEmpty) {
      return fromEnvironment;
    }
    return Platform.localHostname;
  }

  /// Ο σταθμός αυτού του αντιγράφου· κενό όταν το σύστημα δεν τον δίνει.
  static String get current {
    try {
      return reader().trim();
    } catch (_) {
      // Ο σταθμός είναι πληροφορία άνεσης — η απουσία του δεν σταματά τίποτα.
      return '';
    }
  }

  /// Ο σταθμός σε μορφή που αντέχει να μπει σε **όνομα αρχείου**.
  ///
  /// Το `localHostname` μπορεί να γυρίσει πλήρες όνομα δικτύου με τελείες, και
  /// τίποτα δεν εγγυάται ότι ένα όνομα υπολογιστή είναι νόμιμο όνομα αρχείου.
  /// Ό,τι δεν είναι γράμμα ή ψηφίο γίνεται παύλα· το κενό όνομα γίνεται
  /// [unknownStation], ώστε το αρχείο να έχει πάντα σταθερό, έγκυρο όνομα.
  static String get fileSafe {
    final raw = current;
    if (raw.isEmpty) return unknownStation;
    final cleaned = raw
        .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (cleaned.isEmpty) return unknownStation;
    return cleaned.length <= maxLength
        ? cleaned
        : cleaned.substring(0, maxLength);
  }

  static const String unknownStation = 'unknown';

  /// Φράγμα μήκους: η πλήρης διαδρομή ενός αρχείου στα Windows έχει όριο, και
  /// ο φάκελος ζει δίπλα στη βάση — συχνά βαθιά σε δικτυακή διαδρομή.
  static const int maxLength = 40;
}
