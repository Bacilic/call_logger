import 'package:flutter/material.dart';

import '../../../../core/utils/similar_department_finder.dart';
import '../../../../core/utils/text_similarity.dart';
import '../../../../core/widgets/draggable_dialog_shell.dart';
import '../../../directory/models/department_model.dart';
import 'suggestion_comparison_card.dart';

/// Αποτέλεσμα διαλόγου πρότασης παρόμοιου τμήματος.
class SimilarDepartmentDialogResult {
  /// Ο χρήστης ακύρωσε (ή έκλεισε τον διάλογο).
  const SimilarDepartmentDialogResult.cancelled()
    : createNew = false,
      selectedDepartment = null;

  /// Συνέχεια με δημιουργία νέου τμήματος όπως πληκτρολογήθηκε.
  const SimilarDepartmentDialogResult.createNew()
    : createNew = true,
      selectedDepartment = null;

  /// Επιλογή υπάρχοντος τμήματος από τον κατάλογο.
  const SimilarDepartmentDialogResult.pickExisting(DepartmentModel department)
    : createNew = false,
      selectedDepartment = department;

  /// True όταν επιλέχθηκε «Όχι, δημιουργία νέου τμήματος».
  final bool createNew;

  /// Υπάρχον τμήμα που επιλέχθηκε· null αν ακύρωση ή δημιουργία νέου.
  final DepartmentModel? selectedDepartment;

  bool get isCancelled => !createNew && selectedDepartment == null;
}

/// Διάλογος πρότασης όταν το πληκτρολογημένο τμήμα μοιάζει με ΥΠΑΡΧΟΝτα του καταλόγου.
///
/// Δείχνει δίπλα-δίπλα τι πληκτρολόγησε ο χρήστης και τι υπάρχει ήδη, με
/// μαρκαρισμένο το κοινό μέρος των ονομάτων. Μετακινήσιμος, για να φαίνεται η
/// φόρμα από πίσω.
class SimilarDepartmentSuggestionDialog extends StatelessWidget {
  const SimilarDepartmentSuggestionDialog({
    super.key,
    required this.typedName,
    required this.matches,
  });

  /// Όνομα που πληκτρολόγησε ο χρήστης (θα δημιουργούνταν ως νέο).
  final String typedName;

  /// Υπάρχοντα τμήματα με παρόμοιο όνομα.
  final List<SimilarDepartmentMatch> matches;

  /// Η κάρτα σύγκρισης: «Πληκτρολογήσατε» πάνω, «Υπάρχει ήδη» από κάτω.
  Widget _buildComparisonCard(BuildContext context) {
    final typed = typedName.trim();
    var typedHighlight = (start: 0, length: 0);
    for (final m in matches) {
      final span = TextSimilarity.matchedSpan(typed, m.department.name.trim());
      if (span.length > typedHighlight.length) typedHighlight = span;
    }

    return SuggestionComparisonCard(
      rows: [
        SuggestionComparisonRow(
          label: 'Πληκτρολογήσατε',
          icon: Icons.edit_outlined,
          name: typed,
          highlight: typedHighlight,
        ),
        for (final (index, m) in matches.indexed)
          SuggestionComparisonRow(
            label: index != 0
                ? ''
                : (matches.length == 1 ? 'Υπάρχει ήδη' : 'Υπάρχουν ήδη'),
            icon: Icons.apartment_outlined,
            name: m.department.name.trim(),
            highlight: TextSimilarity.matchedSpan(
              m.department.name.trim(),
              typed,
            ),
            emphasized: true,
            onTap: () => Navigator.of(
              context,
            ).pop(SimilarDepartmentDialogResult.pickExisting(m.department)),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableDialogShell(
      title: const Text('Μήπως εννοείτε υπάρχον τμήμα;'),
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
                  matches.length == 1
                      ? 'Το τμήμα που πληκτρολογήσατε θα δημιουργηθεί ως νέο, '
                            'ενώ υπάρχει ήδη τμήμα με παρόμοιο όνομα:'
                      : 'Το τμήμα που πληκτρολογήσατε θα δημιουργηθεί ως νέο, '
                            'ενώ υπάρχουν ήδη τμήματα με παρόμοιο όνομα:',
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 12),
                _buildComparisonCard(context),
                const SizedBox(height: 12),
                Text(
                  'Επιλέξτε υπάρχον τμήμα ή συνεχίστε με δημιουργία νέου.',
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
            ).pop(const SimilarDepartmentDialogResult.cancelled()),
            child: const Text('Ακύρωση'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(
              context,
            ).pop(const SimilarDepartmentDialogResult.createNew()),
            child: const Text('Όχι, δημιουργία νέου τμήματος'),
          ),
        ],
      ),
    );
  }
}

/// Εμφανίζει τον διάλογο πρότασης μόνο αν υπάρχουν παρόμοια τμήματα.
///
/// Επιστρέφει `null` όταν δεν υπάρχουν προτάσεις (η ροή συνεχίζει ανενόχλητη).
/// Διαφορετικά επιστρέφει το αποτέλεσμα του διαλόγου (ή `cancelled` αν έκλεισε).
Future<SimilarDepartmentDialogResult?> showSimilarDepartmentSuggestionIfNeeded({
  required BuildContext context,
  required Iterable<DepartmentModel> departments,
  required String typedName,
}) async {
  final matches = SimilarDepartmentFinder.findSimilarDepartments(
    departments: departments,
    typedName: typedName,
  );
  if (matches.isEmpty) return null;

  final result = await showDialog<SimilarDepartmentDialogResult>(
    context: context,
    barrierDismissible: true,
    builder: (_) => SimilarDepartmentSuggestionDialog(
      typedName: typedName,
      matches: matches,
    ),
  );
  return result ?? const SimilarDepartmentDialogResult.cancelled();
}
