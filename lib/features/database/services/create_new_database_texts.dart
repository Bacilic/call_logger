// Τα κείμενα της ροής «Δημιουργία νέου αρχείου βάσης».
//
// Καθαρές συναρτήσεις χωρίς widgets και χωρίς βάση — ελέγχονται με unit tests.
// Το όνομα που θα πάρει η παλιά βάση **δεν** υπολογίζεται εδώ: έρχεται από την
// `resolveRenamedOldDatabaseFileName`, την ίδια που εκτελεί τη μετονομασία.

/// Υπόδειξη του κουμπιού «Δημιουργία νέου αρχείου βάσης».
///
/// Λέει και τα δύο βήματα που ακολουθούν, ώστε το παράθυρο των Windows να μην
/// έρχεται ως έκπληξη και να είναι γνωστό ότι υπάρχει και δεύτερη επιβεβαίωση.
String createNewDatabaseButtonTooltip({required String suggestedFileName}) {
  final name = suggestedFileName.trim();
  final defaultPart = name.isEmpty ? '' : ' (προεπιλογή: $name)';
  return 'Από την εξερεύνηση των Windows θα σας ζητηθεί να επιλέξετε '
      'τοποθεσία και όνομα για τη νέα βάση$defaultPart. '
      'Έπειτα ο οδηγός θα σας ζητήσει επιβεβαίωση.';
}

/// Η οδηγία κάτω από τον τίτλο, σπασμένη γύρω από το όνομα ώστε το UI να το
/// τονίσει: `πριν` + **όνομα** + `μετά`.
typedef RenameNoticeParts = ({String before, String fileName, String after});

/// Τι θα συμβεί στην τρέχουσα βάση, με το **πραγματικό** όνομα μετονομασίας.
///
/// Όταν δεν υπάρχει ενεργή βάση, το [renamedFileName] είναι κενό και το κείμενο
/// πέφτει σε γενική διατύπωση αντί να δείχνει κενά εισαγωγικά.
RenameNoticeParts currentDatabaseRenameNotice({
  required String renamedFileName,
}) {
  final name = renamedFileName.trim();
  if (name.isEmpty) {
    return (
      before:
          'Η τρέχουσα βάση μετονομάζεται πάντα με κατάληξη ημερομηνίας στον '
          'φάκελό της (χωρίς διαγραφή). Δημιουργείται νέο κενό αρχείο και '
          'ορίζεται ενεργό· επανασύνδεση χωρίς επανεκκίνηση.',
      fileName: '',
      after: '',
    );
  }
  return (
    before: 'Η τρέχουσα βάση μετονομάζεται στον φάκελό της ως ',
    fileName: name,
    after:
        ' (χωρίς διαγραφή). Δημιουργείται νέο κενό αρχείο και ορίζεται '
        'ενεργό· επανασύνδεση χωρίς επανεκκίνηση.',
  );
}

/// Το σώμα του διαλόγου επιβεβαίωσης, όταν ο στόχος είναι **νέα** διαδρομή.
RenameNoticeParts createNewDatabaseConfirmation({
  required String targetPath,
  required String renamedFileName,
}) {
  final name = renamedFileName.trim();
  final before =
      'Θα δημιουργηθεί νέο κενό αρχείο στη διαδρομή:\n\n$targetPath\n\n';
  if (name.isEmpty) {
    return (
      before:
          '$before'
          'Η τρέχουσα βάση θα μετονομαστεί στον φάκελό της με κατάληξη '
          'ημερομηνίας (χωρίς διαγραφή) και θα οριστεί ως ενεργή η νέα '
          'διαδρομή. Η εφαρμογή θα επανασυνδεθεί με τη νέα βάση.',
      fileName: '',
      after: '',
    );
  }
  return (
    before:
        '$before'
        'Η τρέχουσα βάση θα μετονομαστεί στον φάκελό της ως ',
    fileName: name,
    after:
        ' (χωρίς διαγραφή) και θα οριστεί ως ενεργή η νέα διαδρομή. '
        'Η εφαρμογή θα επανασυνδεθεί με τη νέα βάση.',
  );
}

/// Το σώμα του διαλόγου όταν ο στόχος είναι **η ίδια** η ενεργή διαδρομή.
RenameNoticeParts replaceCurrentDatabaseConfirmation({
  required String targetPath,
  required String renamedFileName,
}) {
  final name = renamedFileName.trim();
  final after =
      ' στον ίδιο φάκελο και θα δημιουργηθεί νέο κενό στη θέση:'
      '\n\n$targetPath';
  if (name.isEmpty) {
    return (
      before: 'Το τρέχον αρχείο θα μετονομαστεί με κατάληξη ημερομηνίας$after',
      fileName: '',
      after: '',
    );
  }
  return (
    before: 'Το τρέχον αρχείο θα μετονομαστεί ως ',
    fileName: name,
    after: after,
  );
}
