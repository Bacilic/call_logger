/// Πρότυπο αρίθμησης και προεπισκόπηση για τη σειρά σειριακών.
///
/// Ο χρήστης βλέπει **πριν** πατήσει τι ακριβώς θα γραφτεί σε ποιο μηχάνημα.
/// Είκοσι εγγραφές αλλάζουν με ένα κλικ· χωρίς προεπισκόπηση η ενέργεια θα
/// ήταν στοίχημα.
///
/// Δύο καταστάσεις: η **προεπιλογή** (`σειριακός-1`) και ένα **προσαρμοσμένο**
/// πρότυπο με τον τελεστή `<αύξον>`. Το δεύτερο υπάρχει γιατί η βάση δεν δίνει
/// πάντα χρήσιμη αφετηρία — όταν ο σειριακός είναι σκέτη παύλα, η σύμβαση του
/// νοσοκομείου βάζει το μοντέλο στη θέση του.
library;

import 'package:flutter/material.dart';

import '../../../core/database/old_database/lamp_serial_series.dart';

/// Πόσες γραμμές δείχνει η προεπισκόπηση πριν συνοψίσει.
const int kLampSeriesPreviewRows = 3;

class LampSerialSeriesFields extends StatefulWidget {
  const LampSerialSeriesFields({
    super.key,
    required this.buildPlan,
    required this.defaultTemplate,
    required this.controller,
    required this.descriptionByCode,
    required this.onUseDefault,
  });

  /// Χτίζει την αρίθμηση για το πρότυπο που ισχύει τη στιγμή της κλήσης.
  final LampSerialSeriesPlan Function(String template) buildPlan;

  /// Η προεπιλογή, όπως την πρότεινε ο αναλυτής.
  final String defaultTemplate;

  /// Το προσαρμοσμένο πεδίο· κενό σημαίνει «χρησιμοποίησε την προεπιλογή».
  final TextEditingController controller;

  /// Κωδικός εξοπλισμού → σύντομη περιγραφή, για να αναγνωρίζεται η γραμμή.
  final Map<int, String> descriptionByCode;

  final VoidCallback onUseDefault;

  @override
  State<LampSerialSeriesFields> createState() => _LampSerialSeriesFieldsState();
}

class _LampSerialSeriesFieldsState extends State<LampSerialSeriesFields> {
  // Το widget ακούει μόνο του τον controller: η προεπισκόπηση πρέπει να
  // ακολουθεί κάθε πληκτρολόγηση, ανεξάρτητα από το τι κάνει ο καλών.
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTemplateChanged);
  }

  @override
  void didUpdateWidget(LampSerialSeriesFields oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTemplateChanged);
      widget.controller.addListener(_onTemplateChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTemplateChanged);
    super.dispose();
  }

  void _onTemplateChanged() {
    if (mounted) setState(() {});
  }

  bool get _usingDefault => widget.controller.text.trim().isEmpty;

  String get _template {
    final custom = widget.controller.text.trim();
    return custom.isEmpty ? widget.defaultTemplate : custom;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final template = _template;
    final plan = widget.buildPlan(template);
    final defaultTemplate = widget.defaultTemplate;
    final controller = widget.controller;
    final onUseDefault = widget.onUseDefault;
    final valid = lampSeriesTemplateIsValid(template);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text('Μορφή:', style: theme.textTheme.bodySmall),
            const SizedBox(width: 8),
            // Η προεπιλογή δείχνει το **αποτέλεσμα**, όχι το πρότυπο: ο
            // χρήστης κρίνει από αυτό που θα γραφτεί.
            ChoiceChip(
              key: const Key('lamp_series_default_format'),
              label: Text(
                defaultTemplate.replaceAll(kLampSeriesCounterToken, '1'),
              ),
              selected: _usingDefault,
              onSelected: (_) => onUseDefault(),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                key: const Key('lamp_series_custom_template'),
                controller: controller,
                decoration: InputDecoration(
                  labelText: 'Προσαρμοσμένο',
                  hintText: 'π.χ. Πληκτρολόγιο Dell (61)-'
                      '$kLampSeriesCounterToken',
                  helperText: valid
                      ? null
                      : 'Χρειάζεται τον τελεστή $kLampSeriesCounterToken',
                  errorText: _usingDefault || valid
                      ? null
                      : 'Χωρίς $kLampSeriesCounterToken όλες οι εγγραφές θα '
                            'πάρουν την ίδια τιμή',
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
        if (plan.continuationNote case final note?) ...[
          const SizedBox(height: 8),
          Text(
            note,
            key: const Key('lamp_series_continuation'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ],
        const SizedBox(height: 8),
        _Preview(
          plan: plan,
          descriptionByCode: widget.descriptionByCode,
          theme: theme,
        ),
      ],
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({
    required this.plan,
    required this.descriptionByCode,
    required this.theme,
  });

  final LampSerialSeriesPlan plan;
  final Map<int, String> descriptionByCode;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final shown = plan.assignments.take(kLampSeriesPreviewRows).toList();
    final rest = plan.assignments.length - shown.length;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
            child: Text('Προεπισκόπηση', style: theme.textTheme.labelSmall),
          ),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 2, 10, 8),
              child: Text(
                'Συμπληρώστε πρότυπο με τον τελεστή '
                '$kLampSeriesCounterToken.',
                key: const Key('lamp_series_preview_empty'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          for (final assignment in shown)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 2, 10, 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${assignment.code}'
                      '${descriptionByCode[assignment.code] == null ? '' : ' · ${descriptionByCode[assignment.code]}'}',
                      style: theme.textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    assignment.serial,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          if (rest > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 2, 10, 6),
              child: Text(
                '… και $rest ακόμη, με τη σειρά του κωδικού',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            )
          else if (shown.isNotEmpty)
            const SizedBox(height: 6),
        ],
      ),
    );
  }
}
