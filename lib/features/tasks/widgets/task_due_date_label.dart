import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/greek_date_format.dart';
import '../utils/task_duration_format.dart';

/// Η ημερομηνία λήξης (ή ολοκλήρωσης) στην κεφαλίδα της κάρτας εκκρεμότητας.
///
/// Το τρίγραμμο της ημέρας μπαίνει μπροστά με διακριτό χρώμα — ένα χρώμα για
/// όλες τις ημέρες, ώστε να ξεχωρίζει η ημέρα από τους αριθμούς χωρίς να
/// χρειάζεται ο χρήστης να απομνημονεύσει επτά αντιστοιχίσεις.
///
/// Όταν δοθεί [onSnooze], το διπλό κλικ ανοίγει την αναβολή και η υπόδειξη το
/// ανακοινώνει· διαφορετικά η ένδειξη είναι καθαρά πληροφοριακή (ολοκληρωμένες).
class TaskDueDateLabel extends StatefulWidget {
  const TaskDueDateLabel({
    super.key,
    required this.date,
    required this.pattern,
    required this.fallbackText,
    this.onSnooze,
    this.showRemaining = false,
  });

  /// Η στιγμή που εμφανίζεται· `null` όταν η εκκρεμότητα δεν έχει έγκυρη τιμή.
  final DateTime? date;

  /// Μοτίβο μορφοποίησης της [date].
  final String pattern;

  /// Ό,τι εμφανίζεται όταν η [date] δεν είναι έγκυρη ημερομηνία.
  final String fallbackText;

  /// Άνοιγμα του διαλόγου αναβολής με διπλό κλικ.
  final VoidCallback? onSnooze;

  /// Υπόδειξη με το πόσο απομένει ή πόσο εκκρεμεί — μόνο για ενεργές.
  final bool showRemaining;

  @override
  State<TaskDueDateLabel> createState() => _TaskDueDateLabelState();
}

class _TaskDueDateLabelState extends State<TaskDueDateLabel> {
  /// Ανανεώνεται σε κάθε πέρασμα του ποντικιού: η κάρτα δεν ξαναζωγραφίζεται
  /// μόνη της, οπότε κείμενο υπολογισμένο μία φορά θα έλεγε «Λήγει σε 3 ώρες»
  /// ακόμη και πέντε ώρες αργότερα.
  late String _hoverMessage = _buildMessage();

  String _buildMessage() {
    final date = widget.date;
    return [
      if (widget.showRemaining && date != null)
        dueRelativeLabel(DateTime.now(), date),
      if (widget.onSnooze != null) 'Διπλό κλικ για αναβολή',
    ].join('\n');
  }

  void _refreshMessage() {
    final message = _buildMessage();
    if (message == _hoverMessage) return;
    setState(() => _hoverMessage = message);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = widget.date;

    final Widget label = date == null
        ? Text(widget.fallbackText, style: theme.textTheme.bodySmall)
        : Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${weekdayShortEl(date)} ',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextSpan(text: DateFormat(widget.pattern).format(date)),
              ],
            ),
            style: theme.textTheme.bodySmall,
          );

    if (widget.onSnooze == null && !widget.showRemaining) return label;

    return MouseRegion(
      cursor: widget.onSnooze != null
          ? SystemMouseCursors.click
          : MouseCursor.defer,
      onEnter: (_) => _refreshMessage(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: widget.onSnooze,
        child: Tooltip(
          message: _hoverMessage,
          waitDuration: const Duration(milliseconds: 400),
          child: label,
        ),
      ),
    );
  }
}
