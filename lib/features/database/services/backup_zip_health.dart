/// Είναι αυτό το αρχείο αντίγραφο, και διαβάζεται ως το τέλος;
///
/// **Το πρόβλημα που λύνει (14/09/2026):** ο αποκωδικοποιητής zip δεν πετάει
/// τίποτα σε κομμένο αρχείο ούτε σε αρχείο που δεν είναι καν zip — επιστρέφει
/// **άδειο** αρχειοθέτη. Έτσι το `catch` της απογραφής δεν ενεργοποιούνταν
/// ποτέ, και ο χειριστής διάβαζε «Δεν βρέθηκε αρχείο βάσης (.db) μέσα στο
/// zip»: μήνυμα που κατηγορεί την **επιλογή** του, ενώ το αντίγραφό του ήταν
/// χαλασμένο — και κανείς δεν του έλεγε να δοκιμάσει το προηγούμενο.
///
/// Η κρίση γίνεται στα **bytes**, πριν από κάθε αποκωδικοποίηση: ένα zip έχει
/// υπογραφή στην αρχή και μια εγγραφή τερματισμού στο τέλος. Ό,τι λείπει,
/// λέει τι λείπει.
library;

/// Τι απάντησε ο έλεγχος του αρχείου.
enum BackupArchiveHealth {
  /// Διαβάζεται ως το τέλος. Ό,τι λέει μετά η απογραφή είναι αλήθεια.
  ok,

  /// Μηδέν bytes.
  empty,

  /// Δεν φέρει καμία υπογραφή zip — άλλο αρχείο, ή λάθος επιλογή.
  notAnArchive,

  /// Ξεκινά ως zip αλλά δεν τελειώνει: η αντιγραφή δεν ολοκληρώθηκε.
  truncated,
}

/// Υπογραφή τοπικής κεφαλίδας αρχείου («PK\x03\x04»).
const List<int> _localHeaderSignature = <int>[0x50, 0x4B, 0x03, 0x04];

/// Υπογραφή εγγραφής τερματισμού καταλόγου («PK\x05\x06»).
const List<int> _endOfCentralDirectorySignature = <int>[0x50, 0x4B, 0x05, 0x06];

/// Το ελάχιστο μέγεθος της εγγραφής τερματισμού, χωρίς σχόλιο.
const int _endOfCentralDirectoryLength = 22;

/// Κρίνει το αρχείο από τα ίδια του τα bytes.
///
/// Η εγγραφή τερματισμού δεν αρκεί να **υπάρχει**: σε αρχείο κομμένο λίγο
/// πριν το τέλος η υπογραφή της βρίσκεται μέσα, αλλά τα 22 bytes της δεν
/// χωρούν ως το τέλος του αρχείου. Μετρημένο σε πραγματικό zip κομμένο στο
/// 90%: η υπογραφή στη θέση 125, το αρχείο τελειώνει στα 132.
BackupArchiveHealth inspectBackupArchiveBytes(List<int> bytes) {
  if (bytes.isEmpty) return BackupArchiveHealth.empty;

  if (_hasCompleteEndRecord(bytes)) return BackupArchiveHealth.ok;

  final startsAsArchive =
      _startsWith(bytes, _localHeaderSignature) ||
      _startsWith(bytes, _endOfCentralDirectorySignature);
  return startsAsArchive
      ? BackupArchiveHealth.truncated
      : BackupArchiveHealth.notAnArchive;
}

/// Τι λέμε στον χειριστή. `null` όταν το αρχείο είναι εντάξει — τότε μιλά η
/// απογραφή, που ξέρει τι βρήκε μέσα.
String? backupArchiveHealthMessage(BackupArchiveHealth health) {
  switch (health) {
    case BackupArchiveHealth.ok:
      return null;
    case BackupArchiveHealth.empty:
      return 'Το αρχείο του αντιγράφου είναι κενό — δεν περιέχει τίποτα. '
          'Δοκιμάστε παλαιότερο αντίγραφο.';
    case BackupArchiveHealth.notAnArchive:
      return 'Αυτό το αρχείο δεν είναι αντίγραφο ασφαλείας της εφαρμογής: '
          'δεν έχει τη μορφή συμπιεσμένου αρχείου (.zip). Ελέγξτε ότι '
          'επιλέξατε το σωστό αρχείο.';
    case BackupArchiveHealth.truncated:
      return 'Το αντίγραφο είναι χαλασμένο: το αρχείο ξεκινά κανονικά αλλά '
          'δεν διαβάζεται ως το τέλος, που σημαίνει ότι η αντιγραφή του δεν '
          'ολοκληρώθηκε. Δοκιμάστε παλαιότερο αντίγραφο.';
  }
}

/// Η ίδια κρίση σε μία σύντομη φράση, για υποδείξεις όπου δεν χωρά παράγραφος.
///
/// Ζει δίπλα στο [backupArchiveHealthMessage] επίτηδες: δύο διατυπώσεις για
/// τις ίδιες τρεις καταστάσεις αποκλίνουν σιωπηλά όταν ζουν σε άλλα αρχεία.
String? backupArchiveHealthShortMessage(BackupArchiveHealth health) {
  switch (health) {
    case BackupArchiveHealth.ok:
      return null;
    case BackupArchiveHealth.empty:
      return 'Το αρχείο είναι κενό.';
    case BackupArchiveHealth.notAnArchive:
      return 'Το αρχείο δεν έχει τη μορφή συμπιεσμένου αρχείου (.zip).';
    case BackupArchiveHealth.truncated:
      return 'Το αρχείο είναι χαλασμένο — δεν διαβάζεται ως το τέλος.';
  }
}

bool _startsWith(List<int> bytes, List<int> signature) {
  if (bytes.length < signature.length) return false;
  for (var i = 0; i < signature.length; i++) {
    if (bytes[i] != signature[i]) return false;
  }
  return true;
}

/// Υπάρχει εγγραφή τερματισμού που **χωράει** ολόκληρη μέσα στο αρχείο;
bool _hasCompleteEndRecord(List<int> bytes) {
  if (bytes.length < _endOfCentralDirectoryLength) return false;
  // Το σχόλιο του zip μπορεί να σπρώξει την εγγραφή πιο μέσα, γι' αυτό η
  // αναζήτηση ξεκινά από το τέλος και προχωρά προς τα πίσω.
  for (var i = bytes.length - _endOfCentralDirectoryLength; i >= 0; i--) {
    var matches = true;
    for (var j = 0; j < _endOfCentralDirectorySignature.length; j++) {
      if (bytes[i + j] != _endOfCentralDirectorySignature[j]) {
        matches = false;
        break;
      }
    }
    if (matches) return true;
  }
  return false;
}
