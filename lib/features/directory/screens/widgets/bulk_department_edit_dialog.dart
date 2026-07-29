import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/draggable_dialog_shell.dart';
import '../../models/department_model.dart';
import '../../providers/department_directory_provider.dart';
import '../../services/bulk_department_actions.dart';
import 'bulk_user_action_pickers.dart';
import 'department_color_palette.dart';

/// Μαζικές ενέργειες τμημάτων: κτίριο, χρώμα, ομάδα, σημειώσεις, απόκρυψη
/// χάρτη και καθαρισμός πεδίου.
///
/// **Καμία ενέργεια πάνω σε μέλη.** Υπάλληλοι, εξοπλισμός και τηλέφωνα δεν
/// είναι χαρακτηριστικά του τμήματος αλλά ανεξάρτητες οντότητες που το
/// αναφέρουν — μια μαζική ενέργεια πάνω τους θα άγγιζε δεκάδες εγγραφές εκτός
/// επιλογής, χωρίς έγκυρο προορισμό. Η τύχη τους αποφασίζεται στον οδηγό
/// διαγραφής τμήματος, ένα τμήμα τη φορά και με ορατό περιεχόμενο.
class BulkDepartmentEditDialog extends ConsumerStatefulWidget {
  const BulkDepartmentEditDialog({
    super.key,
    required this.selectedDepartments,
    required this.notifier,
  });

  final List<DepartmentModel> selectedDepartments;
  final DepartmentDirectoryNotifier notifier;

  @override
  ConsumerState<BulkDepartmentEditDialog> createState() =>
      _BulkDepartmentEditDialogState();
}

class _BulkDepartmentEditDialogState
    extends ConsumerState<BulkDepartmentEditDialog> {
  bool _busy = false;

  List<DepartmentModel> get _departments => widget.selectedDepartments;

  Future<void> _run(Future<void> Function() flow) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await flow();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ─────────────────────────── Κτίριο ───────────────────────────

  Future<void> _runBuildingFlow() async {
    final text = await showBulkTextInputDialog(
      context,
      title: 'Κτίριο σε ${_departments.length} τμήματα',
      label: 'Κτίριο',
      helper:
          'Το κενό κείμενο δεν αποθηκεύεται — για διαγραφή χρησιμοποιήστε '
          'τον «Καθαρισμό πεδίου».',
    );
    if (text == null || !mounted) return;

    final confirmed = await showBulkConfirmDialog(
      context,
      title: 'Επιβεβαίωση κτιρίου',
      message:
          'Το κτίριο «$text» θα γραφτεί σε ${_departments.length} τμήματα: '
          '${bulkDepartmentNamesPreview(_departments)}.',
    );
    if (!confirmed || !mounted) return;

    await widget.notifier.applyBulkField(
      departments: _departments,
      column: 'building',
      value: text,
      message: 'Ενημερώθηκε το κτίριο ${_departments.length} τμημάτων.',
    );
    if (mounted) Navigator.of(context).pop();
  }

  // ─────────────────────────── Χρώμα ───────────────────────────

  Future<void> _runColorFlow() async {
    final color = await showDialog<Color>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _ColorPickerDialog(),
    );
    if (color == null || !mounted) return;
    final hex = colorToDepartmentHex(color);

    final confirmed = await showBulkConfirmDialog(
      context,
      title: 'Επιβεβαίωση χρώματος',
      message:
          'Το χρώμα $hex θα εφαρμοστεί σε ${_departments.length} τμήματα: '
          '${bulkDepartmentNamesPreview(_departments)}.'
          '\nΤο χρώμα χρησιμοποιείται στον κατάλογο και ως γέμισμα της '
          'περιοχής στον χάρτη κτιρίου.',
    );
    if (!confirmed || !mounted) return;

    await widget.notifier.applyBulkField(
      departments: _departments,
      column: 'color',
      value: hex,
      message: 'Ενημερώθηκε το χρώμα ${_departments.length} τμημάτων.',
    );
    if (mounted) Navigator.of(context).pop();
  }

  // ─────────────────────────── Ομάδα ───────────────────────────

  Future<void> _runGroupFlow() async {
    final all = ref.read(departmentDirectoryProvider).allDepartments;
    final suggestions = existingDepartmentGroups(all);

    final text = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _GroupPickerDialog(
        departmentCount: _departments.length,
        suggestions: suggestions,
      ),
    );
    if (text == null || !mounted) return;

    final confirmed = await showBulkConfirmDialog(
      context,
      title: 'Επιβεβαίωση ομάδας',
      message:
          'Η ομάδα «$text» θα δοθεί σε ${_departments.length} τμήματα: '
          '${bulkDepartmentNamesPreview(_departments)}.'
          '\nΗ ομάδα χρησιμοποιείται για ομαδοποίηση στον επιλογέα τμημάτων '
          'του χάρτη.',
    );
    if (!confirmed || !mounted) return;

    await widget.notifier.applyBulkField(
      departments: _departments,
      column: 'group_name',
      value: text,
      message: 'Ορίστηκε η ομάδα «$text» σε ${_departments.length} τμήματα.',
    );
    if (mounted) Navigator.of(context).pop();
  }

  // ─────────────────────────── Σημειώσεις ───────────────────────────

  Future<void> _runNotesFlow() async {
    final result = await showBulkNotesDialog(
      context,
      title: 'Σημειώσεις σε ${_departments.length} τμήματα',
    );
    if (result == null || !mounted) return;
    final (append, text) = result;

    final confirmed = await showBulkConfirmDialog(
      context,
      title: 'Επιβεβαίωση σημειώσεων',
      message: append
          ? 'Θα προστεθεί η σημείωση «$text» στο τέλος των σημειώσεων '
                '${_departments.length} τμημάτων: '
                '${bulkDepartmentNamesPreview(_departments)}.'
          : 'Θα ΑΝΤΙΚΑΤΑΣΤΑΘΟΥΝ οι σημειώσεις ${_departments.length} τμημάτων '
                'με το κείμενο «$text»: '
                '${bulkDepartmentNamesPreview(_departments)}.',
    );
    if (!confirmed || !mounted) return;

    await widget.notifier.applyBulkField(
      departments: _departments,
      column: 'notes',
      value: text,
      notesMode: append
          ? BulkDepartmentNotesMode.append
          : BulkDepartmentNotesMode.replace,
      message:
          'Ενημερώθηκαν οι σημειώσεις ${_departments.length} τμημάτων '
          '(${append ? 'προσθήκη' : 'αντικατάσταση'}).',
    );
    if (mounted) Navigator.of(context).pop();
  }

  // ─────────────────────── Ορατότητα στον χάρτη ───────────────────────

  Future<void> _runMapVisibilityFlow() async {
    final hide = await showBulkOptionDialog<bool>(
      context,
      title: 'Ορατότητα στον χάρτη',
      message:
          'Η γεωμετρία (θέση και μέγεθος) διατηρείται — αλλάζει μόνο αν το '
          'τμήμα σχεδιάζεται.',
      options: const [
        (
          'Απόκρυψη από τον χάρτη',
          'Τα τμήματα παύουν να εμφανίζονται στην κάτοψη.',
          true,
        ),
        ('Εμφάνιση στον χάρτη', 'Τα κρυμμένα τμήματα ξαναεμφανίζονται.', false),
      ],
    );
    if (hide == null || !mounted) return;

    final affected = [
      for (final d in _departments)
        if (d.isHiddenOnMap != hide) d,
    ];
    if (affected.isEmpty) {
      await showBulkInfoDialog(
        context,
        title: 'Καμία αλλαγή',
        message: hide
            ? 'Όλα τα επιλεγμένα τμήματα είναι ήδη κρυμμένα από τον χάρτη.'
            : 'Όλα τα επιλεγμένα τμήματα εμφανίζονται ήδη στον χάρτη.',
      );
      return;
    }

    final confirmed = await showBulkConfirmDialog(
      context,
      title: 'Επιβεβαίωση ορατότητας',
      message: hide
          ? 'Θα κρυφτούν από τον χάρτη ${affected.length} τμήματα: '
                '${bulkDepartmentNamesPreview(affected)}.'
          : 'Θα εμφανιστούν στον χάρτη ${affected.length} τμήματα: '
                '${bulkDepartmentNamesPreview(affected)}.',
    );
    if (!confirmed || !mounted) return;

    await widget.notifier.applyBulkField(
      departments: affected,
      column: 'map_hidden',
      value: hide ? 1 : 0,
      message: hide
          ? 'Κρύφτηκαν ${affected.length} τμήματα από τον χάρτη.'
          : 'Εμφανίστηκαν ${affected.length} τμήματα στον χάρτη.',
    );
    if (mounted) Navigator.of(context).pop();
  }

  // ─────────────────────────── Καθαρισμός ───────────────────────────

  Future<void> _runClearFlow() async {
    final field = await showBulkOptionDialog<BulkDepartmentClearField>(
      context,
      title: 'Καθαρισμός πεδίου',
      message:
          'Καθαρίζονται μόνο πεδία του ίδιου του τμήματος. Υπάλληλοι, '
          'εξοπλισμός και τηλέφωνα δεν θίγονται ποτέ από εδώ — η τύχη τους '
          'αποφασίζεται στον οδηγό διαγραφής τμήματος.',
      options: const [
        ('Κτίριο', null, BulkDepartmentClearField.building),
        ('Ομάδα', null, BulkDepartmentClearField.group),
        ('Σημειώσεις', null, BulkDepartmentClearField.notes),
      ],
    );
    if (field == null || !mounted) return;

    final plan = buildBulkDepartmentClearPlan(
      selectedDepartments: _departments,
      field: field,
    );
    if (!plan.hasWork) {
      await showBulkInfoDialog(
        context,
        title: 'Κανένας καθαρισμός',
        message:
            'Κανένα από τα επιλεγμένα τμήματα δεν έχει τιμή στο πεδίο '
            '«${bulkDepartmentClearLabel(field)}».',
      );
      return;
    }

    final confirmed = await showBulkConfirmDialog(
      context,
      title: 'Επιβεβαίωση καθαρισμού',
      message: bulkDepartmentClearConfirmationText(plan),
      confirmLabel: 'Καθαρισμός',
    );
    if (!confirmed || !mounted) return;

    await widget.notifier.applyBulkClear(plan);
    if (mounted) Navigator.of(context).pop();
  }

  // ─────────────────────────── Δόμηση ───────────────────────────

  Widget _actionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Future<void> Function() flow,
    Color? iconColor,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        leading: Icon(icon, color: iconColor),
        title: Text(title),
        subtitle: Text(subtitle),
        enabled: !_busy,
        onTap: () => _run(flow),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = _departments.length == 1
        ? 'Μαζικές ενέργειες — 1 τμήμα'
        : 'Μαζικές ενέργειες — ${_departments.length} τμήματα';
    return DraggableDialogShell(
      title: Text(title),
      builder: (titleHandle) => AlertDialog(
        title: titleHandle,
        content: SizedBox(
          width: 540,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  bulkDepartmentNamesPreview(_departments),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                _actionCard(
                  icon: Icons.apartment_outlined,
                  title: 'Κτίριο…',
                  subtitle: 'Κοινό κτίριο για όλα τα επιλεγμένα τμήματα.',
                  flow: _runBuildingFlow,
                ),
                _actionCard(
                  icon: Icons.palette_outlined,
                  title: 'Χρώμα…',
                  subtitle:
                      'Χρώμα καταλόγου και γεμίσματος περιοχής στον χάρτη.',
                  flow: _runColorFlow,
                ),
                _actionCard(
                  icon: Icons.workspaces_outline,
                  title: 'Ομάδα τμημάτων…',
                  subtitle:
                      'Π.χ. «Εργαστήρια», «Κλινικές» — ομαδοποιεί τον '
                      'επιλογέα τμημάτων του χάρτη.',
                  flow: _runGroupFlow,
                ),
                _actionCard(
                  icon: Icons.note_add_outlined,
                  title: 'Σημειώσεις…',
                  subtitle:
                      'Προσθήκη στις υπάρχουσες (προεπιλογή) ή αντικατάσταση.',
                  flow: _runNotesFlow,
                ),
                _actionCard(
                  icon: Icons.visibility_off_outlined,
                  title: 'Ορατότητα στον χάρτη…',
                  subtitle: 'Απόκρυψη ή εμφάνιση — η γεωμετρία διατηρείται.',
                  flow: _runMapVisibilityFlow,
                ),
                _actionCard(
                  icon: Icons.cleaning_services_outlined,
                  iconColor: theme.colorScheme.error,
                  title: 'Καθαρισμός πεδίου…',
                  subtitle:
                      'Κτίριο, ομάδα ή σημειώσεις — ποτέ υπάλληλοι, '
                      'εξοπλισμός ή τηλέφωνα.',
                  flow: _runClearFlow,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('Κλείσιμο'),
          ),
        ],
      ),
    );
  }
}

/// Επιλογή χρώματος από την καθιερωμένη παλέτα τμημάτων.
class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog();

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  Color _selected = const Color(0xFF1976D2);

  @override
  Widget build(BuildContext context) {
    return DraggableDialogShell(
      title: const Text('Χρώμα τμημάτων'),
      builder: (titleHandle) => AlertDialog(
        title: titleHandle,
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: DepartmentColorPalette(
              showHeading: false,
              compact: true,
              selected: _selected,
              onColorSelected: (c) => setState(() => _selected = c),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Ακύρωση'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_selected),
            child: const Text('Συνέχεια'),
          ),
        ],
      ),
    );
  }
}

/// Ελεύθερο πεδίο ομάδας με προτάσεις από τις ομάδες που ήδη υπάρχουν.
class _GroupPickerDialog extends StatefulWidget {
  const _GroupPickerDialog({
    required this.departmentCount,
    required this.suggestions,
  });

  final int departmentCount;
  final List<String> suggestions;

  @override
  State<_GroupPickerDialog> createState() => _GroupPickerDialogState();
}

class _GroupPickerDialogState extends State<_GroupPickerDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _canApply => _controller.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableDialogShell(
      title: Text('Ομάδα σε ${widget.departmentCount} τμήματα'),
      builder: (titleHandle) => AlertDialog(
        title: titleHandle,
        content: SizedBox(
          width: 470,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _controller,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Ομάδα',
                  hintText: 'π.χ. Εργαστήρια, Κλινικές, Διοίκηση',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              if (widget.suggestions.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Υπάρχουσες ομάδες',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final g in widget.suggestions)
                      ActionChip(
                        label: Text(g),
                        onPressed: () => setState(() {
                          _controller.text = g;
                          _controller.selection = TextSelection.collapsed(
                            offset: g.length,
                          );
                        }),
                      ),
                  ],
                ),
              ] else
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    'Δεν υπάρχει ακόμη καμία ομάδα — αυτή θα είναι η πρώτη.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Ακύρωση'),
          ),
          FilledButton(
            onPressed: _canApply
                ? () => Navigator.of(context).pop(_controller.text.trim())
                : null,
            child: const Text('Συνέχεια'),
          ),
        ],
      ),
    );
  }
}
