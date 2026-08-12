import 'package:flutter/material.dart';

import '../../../../core/utils/text_similarity.dart';
import '../../../../core/utils/user_similarity_finder.dart';
import '../../../../core/widgets/draggable_dialog_shell.dart';
import '../../../calls/models/user_model.dart';
import 'suggestion_comparison_card.dart';

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

  /// Μετονομάζεται ΥΠΑΡΧΟΥΣΑ εγγραφή και το νέο όνομα πέφτει πάνω σε άλλη.
  /// Καμία εγγραφή δεν δημιουργείται, οπότε η διατύπωση δεν επιτρέπεται να
  /// μιλά για «νέα εγγραφή» — ο χρήστης θα έψαχνε μια εγγραφή που δεν έγινε.
  directoryRename,
}

/// Διάλογος όταν το ονοματεπώνυμο ταυτίζεται ή μοιάζει με ΥΠΑΡΧΟΥΣΕΣ εγγραφές του καταλόγου.
///
/// Δείχνει δίπλα-δίπλα τι πληκτρολόγησε ο χρήστης και τι υπάρχει ήδη, με
/// μαρκαρισμένο το κοινό μέρος των ονομάτων ώστε η σχέση να φαίνεται με μια
/// ματιά. Μετακινήσιμος, για να φαίνεται η φόρμα από πίσω.
class SimilarUsersDialog extends StatelessWidget {
  const SimilarUsersDialog({
    super.key,
    required this.matches,
    required this.allowPickExisting,
    required this.typedDisplayName,
    this.typedDepartmentName,
    this.purpose = SimilarUsersDialogPurpose.directoryEntry,
  });

  /// Υπάρχουσες εγγραφές καταλόγου με παρόμοιο όνομα.
  final List<UserSimilarityMatch> matches;

  /// Αν true, κάθε γραμμή είναι πατήσιμη για επιλογή υπάρχοντος χρήστη.
  final bool allowPickExisting;

  /// Το ονοματεπώνυμο όπως το πληκτρολόγησε ο χρήστης.
  final String typedDisplayName;

  /// Τμήμα της νέας εγγραφής: null = δεν αφορά τη ροή (δεν εμφανίζεται),
  /// κενό = ρητά «(χωρίς τμήμα)», αλλιώς το όνομα του τμήματος.
  final String? typedDepartmentName;

  final SimilarUsersDialogPurpose purpose;

  bool get _isCallRecord => purpose == SimilarUsersDialogPurpose.callRecord;

  bool get _isRename => purpose == SimilarUsersDialogPurpose.directoryRename;

  bool get _allIdentical =>
      matches.isNotEmpty &&
      matches.every((m) => m.score == UserSimilarityFinder.kIdenticalScore);

  String _matchName(UserSimilarityMatch m) =>
      UserSimilarityFinder.displayNameFor(m.user.firstName, m.user.lastName);

  /// Το κοινό τμήμα του πληκτρολογημένου με το ΚΑΛΥΤΕΡΟ ταίριασμα.
  ({int start, int length}) get _typedHighlight {
    var best = (start: 0, length: 0);
    for (final m in matches) {
      final span = TextSimilarity.matchedSpan(
        typedDisplayName.trim(),
        _matchName(m),
      );
      if (span.length > best.length) best = span;
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final identical = _allIdentical;

    return DraggableDialogShell(
      title: Text(
        identical && !_isCallRecord ? 'Ίδιο ονοματεπώνυμο' : 'Μήπως εννοείτε;',
      ),
      builder: (titleHandle) => AlertDialog(
        title: titleHandle,
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
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
                _buildComparisonCard(context),
                const SizedBox(height: 12),
                Text(
                  _closingQuestion(identical),
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
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
      ),
    );
  }

  /// Ούτε η καταγραφή κλήσης ούτε η μετονομασία δημιουργούν εγγραφή καταλόγου
  /// — η διατύπωση δεν επιτρέπεται να υπονοεί ότι δημιουργούν.
  String _closingQuestion(bool identical) {
    if (_isCallRecord) {
      return 'Θέλετε να καταχωρηθεί η κλήση σε αυτόν τον υπάλληλο ή να καταγραφεί το όνομα όπως το γράψατε;';
    }
    if (_isRename) {
      return identical
          ? 'Μετά τη μετονομασία θα υπάρχουν δύο εγγραφές με ταυτόσημο ονοματεπώνυμο. Θέλετε να συνεχίσετε ή να ακυρώσετε και να διορθώσετε;'
          : 'Θέλετε να συνεχίσετε τη μετονομασία ή να ακυρώσετε και να διορθώσετε;';
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
    if (_isRename) return 'Ναι, συνέχισε τη μετονομασία';
    return identical ? 'Συνέχεια ως Συνωνυμία' : 'Όχι, είναι νέα εγγραφή';
  }

  /// «(τμήμα)» / «(χωρίς τμήμα)» — null όταν η ροή δεν έχει τμήμα να δείξει.
  String? _departmentSuffix(String? departmentName) {
    final dept = departmentName?.trim();
    if (dept == null) return null;
    return dept.isEmpty ? '(χωρίς τμήμα)' : '($dept)';
  }

  /// Η κάρτα σύγκρισης: «Πληκτρολογήσατε» πάνω, «Υπάρχει ήδη» από κάτω.
  Widget _buildComparisonCard(BuildContext context) {
    final typed = typedDisplayName.trim();
    return SuggestionComparisonCard(
      rows: [
        SuggestionComparisonRow(
          label: 'Πληκτρολογήσατε',
          icon: Icons.edit_outlined,
          name: typed,
          highlight: _typedHighlight,
          suffix: _departmentSuffix(typedDepartmentName),
        ),
        for (final (index, m) in matches.indexed)
          SuggestionComparisonRow(
            label: index != 0
                ? ''
                : (matches.length == 1 ? 'Υπάρχει ήδη' : 'Υπάρχουν ήδη'),
            icon: Icons.person_outline,
            name: _matchName(m),
            highlight: TextSimilarity.matchedSpan(_matchName(m), typed),
            suffix: _departmentSuffix(m.user.departmentName ?? ''),
            emphasized: true,
            onTap: !allowPickExisting
                ? null
                : () => Navigator.of(
                    context,
                  ).pop(SimilarUsersDialogResult.pickExisting(m.user)),
          ),
      ],
    );
  }
}
