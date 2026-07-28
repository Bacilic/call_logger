import 'package:flutter/material.dart';

import '../../../../core/utils/similar_department_finder.dart';
import '../../../directory/models/department_model.dart';

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final typed = typedName.trim();

    return AlertDialog(
      title: const Text('Μήπως εννοείτε υπάρχον τμήμα;'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Το τμήμα «$typed» θα δημιουργηθεί ως νέο, ενώ υπάρχουν ήδη τμήματα με παρόμοιο όνομα:',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 12),
            ...matches.map((m) => _buildMatchRow(context, m)),
            const SizedBox(height: 8),
            Text(
              'Επιλέξτε υπάρχον τμήμα ή συνεχίστε με δημιουργία νέου.',
              style: theme.textTheme.bodyMedium,
            ),
          ],
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
    );
  }

  Widget _buildMatchRow(BuildContext context, SimilarDepartmentMatch match) {
    final name = match.department.name.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: () => Navigator.of(
          context,
        ).pop(SimilarDepartmentDialogResult.pickExisting(match.department)),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '«$name»',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
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
