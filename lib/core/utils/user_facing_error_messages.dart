import 'dart:io';

import 'package:sqflite_common/sqlite_api.dart';

import '../database/database_file_identity.dart';
import '../directory/phone_department_policy.dart';

/// Μετατρέπει τεχνικές εξαιρέσεις σε κατανοητά ελληνικά μηνύματα για τον χρήστη.
String humanizeUserFacingError(Object error) {
  if (error is PhoneDepartmentPolicyException) {
    final phones = error.conflicts
        .map((c) => c.phone.trim())
        .where((p) => p.isNotEmpty)
        .toSet()
        .join(', ');
    final phonePart = phones.isEmpty ? 'τηλέφωνο' : 'τηλέφωνο $phones';
    return 'Το $phonePart ανήκει σε άλλο τμήμα και δεν συνδέθηκε αυτόματα. '
        'Επεξεργαστείτε τον υπάλληλο από τον Κατάλογο για να επιλύσετε τη σύγκρουση.';
  }

  if (error is DatabaseException) {
    final text = error.toString();
    if (text.contains('database is locked') || text.contains('SQLITE_BUSY')) {
      return 'Η βάση δεδομένων είναι προσωρινά απασχολημένη. '
          'Δοκιμάστε ξανά σε λίγα δευτερόλεπτα.';
    }
    if (text.contains('database_closed') || error.isDatabaseClosedError()) {
      return 'Η σύνδεση με τη βάση ανανεώθηκε. Δοκιμάστε ξανά την ενέργεια.';
    }
  }

  // Το «malformed» του SQLite: η σύνδεση πετυχαίνει, οι σελίδες από κάτω όχι.
  //
  // Μπαίνει ΕΞΩ από τον έλεγχο τύπου επίτηδες — το ίδιο μήνυμα φτάνει άλλοτε
  // ως DatabaseException και άλλοτε ως ωμό SqfliteFfiException, και ο
  // χειριστής δεν έχει λόγο να δει δύο διαφορετικά κείμενα για το ίδιο.
  //
  // **Η αιτία ΔΕΝ δηλώνεται.** Την ίδια φωνή βγάζει και μια πραγματικά
  // φθαρμένη βάση και μια ανοιχτή σύνδεση σε αρχείο που αντικαταστάθηκε από
  // κάτω της — η δεύτερη θεραπεύεται με επανεκκίνηση. Το μήνυμα λέει το
  // σύμπτωμα, δίνει την ασφαλή ενέργεια, και αφήνει την οριστική στη
  // δεύτερη γραμμή.
  //
  // Απαντά έτσι και στην αντίφαση της οθόνης «Βάση Δεδομένων» (13/09/2026):
  // από πάνω «η σύνδεση πέτυχε», από κάτω αγγλικό «malformed». Και τα δύο
  // ήταν αληθινά, και κανένα δεν εξηγούσε το άλλο.
  if (looksLikeCorruptImageError(error) ||
      looksLikeCopiedWhileInUseError(error)) {
    return 'Η βάση απαντά, αλλά μέρος του περιεχομένου της δεν διαβάζεται. '
        'Πάρτε αντίγραφο ασφαλείας τώρα, όσο ό,τι απομένει διαβάζεται. Αν το '
        'πρόβλημα συνεχιστεί μετά από επανεκκίνηση της εφαρμογής, '
        'επαναφέρετε από παλαιότερο αντίγραφο.';
  }

  if (error is FileSystemException) {
    return 'Δεν υπάρχει πρόσβαση σε απαραίτητο αρχείο. '
        'Ελέγξτε δικαιώματα ή αν το αρχείο είναι ανοιχτό αλλού.';
  }

  final details = error.toString();
  final clipped = details.length <= 120 ? details : details.substring(0, 120);
  return 'Απρόβλεπτο σφάλμα. Τεχνικές λεπτομέρειες: $clipped';
}
