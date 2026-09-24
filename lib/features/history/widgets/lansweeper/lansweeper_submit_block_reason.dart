import '../../models/lansweeper_connection_status.dart';

/// Γιατί δεν μπορεί να γίνει τώρα Άμεση Καταχώρηση· `null` σημαίνει «μπορεί».
///
/// **Μία απόφαση, δύο χρήσεις.** Το ίδιο αποτέλεσμα κρίνει αν το κουμπί είναι
/// πατημένο και τι λέει η υπόδειξη πάνω του. Όσο ήταν δύο χωριστές αποφάσεις,
/// το κουμπί μπορούσε να κλειδώνει για λόγο που η υπόδειξη δεν κάλυπτε — και
/// ακριβώς αυτό συνέβη: όσο ο έλεγχος σύνδεσης ήταν σε εξέλιξη, το κουμπί
/// ήταν γκρίζο και η υπόδειξη σιωπούσε, γιατί κάλυπτε μόνο την αποτυχία.
///
/// Η σειρά των ελέγχων είναι η σειρά που βοηθά τον χειριστή: πρώτα ό,τι
/// διορθώνει ο ίδιος με ένα κλικ, στο τέλος ό,τι πρέπει απλώς να περιμένει.
String? lansweeperImmediateSubmitBlockReason({
  required bool hasSelection,
  required bool isRegistered,
  required bool apiUrlValid,
  required LansweeperConnectionStatus connection,
  required bool busy,
}) {
  if (!hasSelection) {
    return 'Επιλέξτε πρώτα την κλήση που θα καταχωρηθεί.';
  }
  if (isRegistered) {
    return 'Η κλήση είναι ήδη καταχωρημένη στο Lansweeper.';
  }
  if (!apiUrlValid) {
    return 'Δεν έχει οριστεί έγκυρο URL API (api.aspx). Συμπληρώστε το στις '
        'Ρυθμίσεις Lansweeper.';
  }
  final connectionReason = lansweeperConnectionBlockReason(connection);
  if (connectionReason != null) return connectionReason;
  if (busy) {
    return 'Μια άλλη ενέργεια βρίσκεται σε εξέλιξη — περιμένετε να τελειώσει.';
  }
  return null;
}

/// Γιατί η κατάσταση σύνδεσης εμποδίζει την αποστολή· `null` όταν δεν εμποδίζει.
///
/// Το «ελέγχω» **είναι** λόγος εμποδίου και οφείλει να το λέει: είναι η μόνη
/// κατάσταση που περνά μόνη της, οπότε η σωστή οδηγία είναι «περιμένετε»,
/// όχι σιωπή.
String? lansweeperConnectionBlockReason(LansweeperConnectionStatus status) {
  return switch (status) {
    LansweeperConnectionAvailable() => null,
    LansweeperConnectionChecking() =>
      'Γίνεται έλεγχος σύνδεσης με το Lansweeper — περιμένετε λίγα '
          'δευτερόλεπτα.',
    LansweeperConnectionUnavailable(:final reason) =>
      'Ο διακομιστής Lansweeper δεν απαντά: $reason',
  };
}
