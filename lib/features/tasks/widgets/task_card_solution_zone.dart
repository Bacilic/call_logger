import 'package:flutter/material.dart';

import '../../../core/widgets/linkable_selectable_text.dart';
import '../utils/task_completion_summary.dart';

/// Η λύση της εκκρεμότητας, ξεδιπλωμένη κάτω από την κάρτα.
///
/// Δείχνεται και σε ξανα-ανοιγμένη εκκρεμότητα: περιγράφει τι είχε δοκιμαστεί
/// και δεν παύει να ισχύει επειδή το θέμα ξανάνοιξε. Σε αυτή την περίπτωση
/// προηγείται η στιγμή της, ώστε να μη διαβαστεί ως τρέχουσα απάντηση.
class TaskCardSolutionZone extends StatelessWidget {
  const TaskCardSolutionZone({
    required this.completion,
    required this.isClosed,
    super.key,
  });

  final TaskCompletionSummary completion;
  final bool isClosed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final momentLine = completion.momentLine;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(height: 10, thickness: 0.5, color: Colors.black87),
          if (!isClosed && momentLine != null) ...[
            Text(
              'Προηγούμενη λύση — $momentLine',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
          ],
          LinkableSelectableText(
            text: completion.solution!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
