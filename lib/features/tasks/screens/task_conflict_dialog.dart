import 'package:flutter/material.dart';

import '../../../core/errors/task_stale_exception.dart';
import '../../../core/widgets/stale_write_conflict_dialog.dart';
import '../services/task_conflict_summary.dart';

/// Η απόφαση του χρήστη μπροστά σε διένεξη.
enum TaskConflictChoice {
  /// Ακύρωση της αποθήκευσης — η οθόνη δείχνει τη φρέσκια εικόνα.
  takeFresh,

  /// Η δική μου εικόνα γράφεται από πάνω, εν γνώσει μου.
  overwrite,
}

/// Ρωτά τον χρήστη τι να γίνει όταν κάποιος άλλος πρόλαβε.
///
/// Δεν αποφασίζει τίποτα μόνος του: το «γράψε από πάνω» είναι θεμιτή επιλογή
/// (η βάρδια που λύνει το πρόβλημα πρέπει να μπορεί να κλείσει), αρκεί ο
/// άνθρωπος να βλέπει **τι** σβήνει πριν το επιλέξει.
///
/// Επιστρέφει `null` όταν ο διάλογος κλείσει χωρίς επιλογή — ισοδύναμο με
/// ακύρωση, ώστε το κατά λάθος Escape να μη σβήνει ξένη δουλειά.
Future<TaskConflictChoice?> showTaskConflictDialog(
  BuildContext context,
  TaskStaleException conflict, {
  DateTime? now,
}) async {
  final summary = TaskConflictSummary.of(
    attempted: conflict.attempted,
    fresh: conflict.fresh,
    changedBy: conflict.changedBy,
    changedAt: conflict.changedAt,
    now: now,
  );
  final theme = Theme.of(context);
  final solution = summary.freshSolution;

  final overwrite = await showStaleWriteConflictDialog(
    context,
    headline: summary.headline,
    warning: summary.overwriteWarning,
    changedFields: <String>[summary.currentStateLine],
    changedFieldsCaption: 'Πώς είναι τώρα:',
    extra: solution == null
        ? null
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Η λύση που είναι καταγεγραμμένη τώρα:',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  solution,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
    takeTheirsLabel: 'Ακύρωσε την αλλαγή μου',
  );
  if (overwrite == null) return null;
  return overwrite ? TaskConflictChoice.overwrite : TaskConflictChoice.takeFresh;
}
