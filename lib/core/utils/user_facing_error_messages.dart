import 'dart:io';

import 'package:sqflite_common/sqlite_api.dart';

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
    if (text.contains('database_closed') ||
        error.isDatabaseClosedError()) {
      return 'Η σύνδεση με τη βάση ανανεώθηκε. Δοκιμάστε ξανά την ενέργεια.';
    }
  }

  if (error is FileSystemException) {
    return 'Δεν υπάρχει πρόσβαση σε απαραίτητο αρχείο. '
        'Ελέγξτε δικαιώματα ή αν το αρχείο είναι ανοιχτό αλλού.';
  }

  final details = error.toString();
  final clipped =
      details.length <= 120 ? details : details.substring(0, 120);
  return 'Απρόβλεπτο σφάλμα. Τεχνικές λεπτομέρειες: $clipped';
}
