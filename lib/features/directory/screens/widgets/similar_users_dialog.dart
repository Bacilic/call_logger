import 'package:flutter/material.dart';

import '../../../../core/utils/user_similarity_finder.dart';
import '../../../calls/models/user_model.dart';

/// Αποτέλεσμα διαλόγου παρόμοιων / ίδιων υπαλλήλων καταλόγου.
class SimilarUsersDialogResult {
  /// Ο χρήστης ακύρωσε (ή έκλεισε τον διάλογο).
  const SimilarUsersDialogResult.cancelled()
    : continuedAsNew = false,
      selectedUser = null;

  /// Συνέχεια ως νέα εγγραφή / συνωνυμία.
  const SimilarUsersDialogResult.continueAsNew()
    : continuedAsNew = true,
      selectedUser = null;

  /// Επιλογή υπάρχουσας εγγραφής καταλόγου (μόνο όταν επιτρέπεται).
  const SimilarUsersDialogResult.pickExisting(UserModel user)
    : continuedAsNew = false,
      selectedUser = user;

  /// True όταν ο χρήστης επέλεξε «Συνέχεια ως Συνωνυμία» ή «Όχι, είναι νέα εγγραφή».
  final bool continuedAsNew;

  /// Υπάρχουσα εγγραφή που επιλέχθηκε· null αν ακύρωση ή συνέχεια ως νέα.
  final UserModel? selectedUser;

  bool get isCancelled => !continuedAsNew && selectedUser == null;
}

/// Γιατί εμφανίζεται ο διάλογος — αλλάζει μόνο τη διατύπωση, όχι τη λογική.
enum SimilarUsersDialogPurpose {
  /// Πρόκειται να δημιουργηθεί εγγραφή στον κατάλογο (κουμπί «Προσθήκη»).
  directoryEntry,

  /// Πρόκειται να αποθηκευτεί κλήση (κουμπί «Καταγραφή») — καμία εγγραφή καταλόγου.
  callRecord,
}

/// Διάλογος όταν το ονοματεπώνυμο ταυτίζεται ή μοιάζει με ΥΠΑΡΧΟΥΣΕΣ εγγραφές του καταλόγου.
class SimilarUsersDialog extends StatelessWidget {
  const SimilarUsersDialog({
    super.key,
    required this.matches,
    required this.allowPickExisting,
    this.purpose = SimilarUsersDialogPurpose.directoryEntry,
  });

  /// Υπάρχουσες εγγραφές καταλόγου (ποτέ το κείμενο που πληκτρολόγησε ο χρήστης).
  final List<UserSimilarityMatch> matches;

  /// Αν true, κάθε γραμμή είναι πατήσιμη για επιλογή υπάρχοντος χρήστη.
  final bool allowPickExisting;

  final SimilarUsersDialogPurpose purpose;

  bool get _isCallRecord => purpose == SimilarUsersDialogPurpose.callRecord;

  bool get _allIdentical =>
      matches.isNotEmpty &&
      matches.every((m) => m.score == UserSimilarityFinder.kIdenticalScore);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final identical = _allIdentical;

    return AlertDialog(
      title: Text(
        identical && !_isCallRecord ? 'Ίδιο ονοματεπώνυμο' : 'Μήπως εννοείτε;',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              identical
                  ? (matches.length == 1
                        ? 'Υπάρχει ήδη ο παρακάτω χρήστης στον κατάλογο:'
                        : 'Υπάρχουν ήδη οι παρακάτω χρήστες στον κατάλογο:')
                  : (matches.length == 1
                        ? 'Βρέθηκε παρόμοιος υπάλληλος στον κατάλογο:'
                        : 'Βρέθηκαν παρόμοιοι υπάλληλοι στον κατάλογο:'),
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 12),
            ...matches.map((m) => _buildMatchRow(context, m)),
            const SizedBox(height: 12),
            Text(
              _closingQuestion(identical),
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(
            context,
          ).pop(const SimilarUsersDialogResult.cancelled()),
          child: const Text('Ακύρωση'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(
            context,
          ).pop(const SimilarUsersDialogResult.continueAsNew()),
          child: Text(_continueLabel(identical)),
        ),
      ],
    );
  }

  /// Η καταγραφή κλήσης ΔΕΝ δημιουργεί εγγραφή καταλόγου — η διατύπωση δεν
  /// επιτρέπεται να υπονοεί ότι δημιουργεί.
  String _closingQuestion(bool identical) {
    if (_isCallRecord) {
      return 'Θέλετε να καταχωρηθεί η κλήση σε αυτόν τον υπάλληλο ή να καταγραφεί το όνομα όπως το γράψατε;';
    }
    if (identical) {
      return 'Πρόκειται για συνωνυμία (νέος υπάλληλος με το ίδιο όνομα) ή θέλετε να ακυρώσετε και να διορθώσετε την υπάρχουσα εγγραφή;';
    }
    return allowPickExisting
        ? 'Επιλέξτε υπάρχοντα υπάλληλο ή συνεχίστε με νέα εγγραφή.'
        : 'Θέλετε να συνεχίσετε με νέα εγγραφή ή να ακυρώσετε και να διορθώσετε;';
  }

  String _continueLabel(bool identical) {
    if (_isCallRecord) return 'Όχι, κατέγραψε όπως το έγραψα';
    return identical ? 'Συνέχεια ως Συνωνυμία' : 'Όχι, είναι νέα εγγραφή';
  }

  Widget _buildMatchRow(BuildContext context, UserSimilarityMatch match) {
    final u = match.user;
    final name = UserSimilarityFinder.displayNameFor(u.firstName, u.lastName);
    final deptRaw = u.departmentName?.trim() ?? '';
    final dept = deptRaw.isEmpty ? '—' : deptRaw;
    final line = Text(
      '«$name» στο τμήμα «$dept»',
      style: Theme.of(context).textTheme.bodyLarge,
    );

    if (!allowPickExisting) {
      return Padding(padding: const EdgeInsets.only(bottom: 6), child: line);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: () =>
            Navigator.of(context).pop(SimilarUsersDialogResult.pickExisting(u)),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          child: Row(
            children: [
              Expanded(child: line),
              Icon(
                Icons.chevron_right,
                color: Theme.of(context).colorScheme.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
