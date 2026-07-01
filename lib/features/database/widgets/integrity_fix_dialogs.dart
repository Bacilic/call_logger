import 'package:flutter/material.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/database/department_repository.dart';
import '../../../core/database/user_repository.dart';
import '../../../core/database/lock_diagnostic_service.dart';
import '../../../core/utils/search_text_normalizer.dart';
import '../models/database_integrity_finding.dart';
import '../models/integrity_fix_models.dart';
import 'database_maintenance_panel.dart';

/// Επιβεβαίωση μονής ή μαζικής επιδιόρθωσης (confirm-only).
Future<bool> showIntegrityConfirmDialog(
  BuildContext context, {
  required String message,
  int affectedCount = 1,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(
        affectedCount > 1
            ? 'Μαζική επιδιόρθωση ($affectedCount)'
            : 'Επιδιόρθωση ενός ευρήματος',
      ),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Άκυρο'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Επιδιόρθωση'),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Διάλογος επιλογής (αποσύνδεση ή νέα τιμή).
Future<IntegrityFixDecision?> showIntegrityChoiceDialog(
  BuildContext context,
  DatabaseIntegrityFinding finding,
) async {
  return showDialog<IntegrityFixDecision>(
    context: context,
    builder: (ctx) => _IntegrityChoiceDialog(finding: finding),
  );
}

/// Μη απορριπτικός διάλογος για PRAGMA corruption.
Future<void> showIntegrityCorruptionBlockoutDialog(
  BuildContext context, {
  Future<void> Function()? onDatabaseReopened,
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('Κρίσιμο πρόβλημα ακεραιότητας βάσης'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Ο έλεγχος PRAGMA quick_check απέτυχε. '
                'Δεν επιτρέπεται αυτόματη επιδιόρθωση από την εφαρμογή.',
              ),
              SizedBox(height: 12),
              Text(
                'Προτεινόμενες ενέργειες:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 8),
              Text('• Άνοιγμα πίνακα συντήρησης βάσης (VACUUM / REINDEX)'),
              Text('• Επαναφορά από αντίγραφο ασφαλείας (.zip)'),
              Text('• Επικοινωνία με διαχειριστή IT αν το πρόβλημα επαναλαμβάνεται'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Κλείσιμο'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              if (onDatabaseReopened != null) {
                await DatabaseMaintenancePanel.show(
                  context,
                  onDatabaseReopened: onDatabaseReopened,
                );
              }
            },
            child: const Text('Συντήρηση βάσης'),
          ),
        ],
      ),
    ),
  );
}

/// Retry διάλογος για SQLITE_BUSY / database locked.
Future<bool> showIntegrityLockRetryDialog(
  BuildContext context, {
  required String dbPath,
  String? message,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Η βάση είναι κλειδωμένη'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message ??
                  'Η επιδιόρθωση δεν ολοκληρώθηκε επειδή το αρχείο βάσης '
                  'χρησιμοποιείται από άλλη διεργασία.',
            ),
            const SizedBox(height: 16),
            _LockDiagnosticSection(dbPath: dbPath),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Κλείσιμο'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Επανάληψη'),
        ),
      ],
    ),
  );
  return result ?? false;
}

class _IntegrityChoiceDialog extends StatefulWidget {
  const _IntegrityChoiceDialog({required this.finding});

  final DatabaseIntegrityFinding finding;

  @override
  State<_IntegrityChoiceDialog> createState() => _IntegrityChoiceDialogState();
}

class _IntegrityChoiceDialogState extends State<_IntegrityChoiceDialog> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _departments = const [];
  List<Map<String, dynamic>> _users = const [];
  List<String> _departmentNames = const [];
  Map<String, int> _departmentNameToId = const {};
  List<String> _userLabels = const [];
  Map<String, int> _userLabelToId = const {};

  final _departmentController = TextEditingController();
  final _departmentFocusNode = FocusNode();
  final _userController = TextEditingController();
  final _userFocusNode = FocusNode();

  int? _selectedId;
  _ChoiceMode _mode = _ChoiceMode.disconnect;

  @override
  void initState() {
    super.initState();
    if (widget.finding.checkType == IntegrityCheckType.usersWithoutDepartment ||
        widget.finding.checkType == IntegrityCheckType.usersInvalidDepartment) {
      _mode = _ChoiceMode.reassign;
    }
    _loadChoices();
  }

  @override
  void dispose() {
    _departmentController.dispose();
    _departmentFocusNode.dispose();
    _userController.dispose();
    _userFocusNode.dispose();
    super.dispose();
  }

  void _clearSelectionFields() {
    _selectedId = null;
    _departmentController.clear();
    _userController.clear();
  }

  static String _userLabel(Map<String, dynamic> row) {
    final id = row['id'] as int?;
    final name = '${row['last_name'] ?? ''} ${row['first_name'] ?? ''}'.trim();
    if (name.isNotEmpty) return name;
    if (id == null) return '';
    return 'Υπάλληλος #$id';
  }

  void _rebuildDepartmentIndex() {
    final names = <String>[];
    final nameToId = <String, int>{};
    for (final row in _departments) {
      final id = row['id'] as int?;
      final name = (row['name'] as String?)?.trim() ?? '';
      if (id == null || name.isEmpty) continue;
      names.add(name);
      nameToId[name] = id;
    }
    _departmentNames = names;
    _departmentNameToId = nameToId;
  }

  void _rebuildUserIndex() {
    final labels = <String>[];
    final labelToId = <String, int>{};
    for (final row in _users) {
      final id = row['id'] as int?;
      final label = _userLabel(row);
      if (id == null || label.isEmpty) continue;
      labels.add(label);
      labelToId[label] = id;
    }
    labels.sort(
      (a, b) => SearchTextNormalizer.normalizeForSearch(a).compareTo(
        SearchTextNormalizer.normalizeForSearch(b),
      ),
    );
    _userLabels = labels;
    _userLabelToId = labelToId;
  }

  Future<void> _loadChoices() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final departments = DepartmentRepository(db);
      final users = UserRepository(db);
      switch (widget.finding.checkType) {
        case IntegrityCheckType.orphanPhone:
          _departments = await departments.getActiveDepartments();
          _users = await users.getAllUsers();
          _rebuildDepartmentIndex();
          _rebuildUserIndex();
        case IntegrityCheckType.usersWithoutDepartment:
        case IntegrityCheckType.usersInvalidDepartment:
          _departments = await departments.getActiveDepartments();
          _rebuildDepartmentIndex();
        default:
          break;
      }
      if (mounted) {
        setState(() => _loading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
    }
  }

  Iterable<String> _filterOptions(Iterable<String> source, String query) {
    final q = SearchTextNormalizer.normalizeForSearch(query);
    if (q.isEmpty) return source;
    return source.where(
      (option) => SearchTextNormalizer.matchesNormalizedQuery(option, q),
    );
  }

  Widget _autocompleteOptionsView(
    BuildContext context,
    void Function(String) onSelected,
    Iterable<String> options,
  ) {
    return Align(
      alignment: Alignment.topLeft,
      child: Material(
        elevation: 4,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 220),
          child: ListView.builder(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            itemCount: options.length,
            itemBuilder: (context, index) {
              final option = options.elementAt(index);
              return ListTile(
                dense: true,
                title: Text(option),
                onTap: () => onSelected(option),
              );
            },
          ),
        ),
      ),
    );
  }

  void _syncDepartmentSelection(String text) {
    final id = _departmentNameToId[text.trim()];
    setState(() => _selectedId = id);
  }

  void _syncUserSelection(String text) {
    final id = _userLabelToId[text.trim()];
    setState(() => _selectedId = id);
  }

  IntegrityFixDecision? _buildDecision() {
    final finding = widget.finding;
    switch (finding.checkType) {
      case IntegrityCheckType.orphanPhone:
        return switch (_mode) {
          _ChoiceMode.delete => const IntegrityFixSoftDeletePhone(),
          _ChoiceMode.reassign when _selectedId != null =>
            IntegrityFixLinkPhoneToDepartment(_selectedId!),
          _ChoiceMode.linkUser when _selectedId != null =>
            IntegrityFixLinkPhoneToUser(_selectedId!),
          _ => null,
        };
      case IntegrityCheckType.usersWithoutDepartment:
        return switch (_mode) {
          _ChoiceMode.delete => const IntegrityFixSoftDeleteUser(),
          _ChoiceMode.reassign when _selectedId != null =>
            IntegrityFixAssignDepartment(_selectedId!),
          _ => null,
        };
      case IntegrityCheckType.usersInvalidDepartment:
        if (_selectedId == null) return null;
        return IntegrityFixAssignDepartment(_selectedId!);
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final finding = widget.finding;
    return AlertDialog(
      title: const Text('Επιδιόρθωση'),
      content: SizedBox(
        width: 420,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(finding.description),
                    const SizedBox(height: 12),
                    ..._buildModeSelectors(),
                    if (_mode != _ChoiceMode.delete &&
                        _mode != _ChoiceMode.disconnect &&
                        _mode != _ChoiceMode.linkUser) ...[
                      const SizedBox(height: 8),
                      _buildDepartmentAutocomplete(),
                    ],
                    if (_mode == _ChoiceMode.linkUser) ...[
                      const SizedBox(height: 8),
                      _buildUserAutocomplete(),
                    ],
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Άκυρο'),
        ),
        FilledButton(
          onPressed: _loading
              ? null
              : () {
                  final decision = _buildDecision();
                  if (decision == null) return;
                  Navigator.of(context).pop(decision);
                },
          child: const Text('Εφαρμογή'),
        ),
      ],
    );
  }

  List<Widget> _buildModeSelectors() {
    final tiles = switch (widget.finding.checkType) {
      IntegrityCheckType.orphanPhone => [
        RadioListTile<_ChoiceMode>(
          title: const Text('Διαγραφή τηλεφώνου'),
          value: _ChoiceMode.delete,
        ),
        RadioListTile<_ChoiceMode>(
          title: const Text('Σύνδεση με τμήμα'),
          value: _ChoiceMode.reassign,
        ),
        RadioListTile<_ChoiceMode>(
          title: const Text('Σύνδεση με υπάλληλο'),
          value: _ChoiceMode.linkUser,
        ),
      ],
      IntegrityCheckType.usersWithoutDepartment => [
        RadioListTile<_ChoiceMode>(
          title: const Text('Μεταφορά σε τμήμα'),
          value: _ChoiceMode.reassign,
        ),
        RadioListTile<_ChoiceMode>(
          title: const Text('Διαγραφή υπαλλήλου'),
          value: _ChoiceMode.delete,
        ),
      ],
      IntegrityCheckType.usersInvalidDepartment => const <Widget>[],
      _ => const <Widget>[],
    };
    if (tiles.isEmpty) return tiles;

    return [
      RadioGroup<_ChoiceMode>(
        groupValue: _mode,
        onChanged: (v) {
          if (v == null) return;
          setState(() {
            _mode = v;
            _clearSelectionFields();
          });
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: tiles,
        ),
      ),
    ];
  }

  Widget _buildDepartmentAutocomplete() {
    return RawAutocomplete<String>(
      textEditingController: _departmentController,
      focusNode: _departmentFocusNode,
      optionsBuilder: (textEditingValue) {
        return _filterOptions(_departmentNames, textEditingValue.text);
      },
      displayStringForOption: (option) => option,
      onSelected: (selection) {
        _departmentController.text = selection;
        _syncDepartmentSelection(selection);
      },
      fieldViewBuilder: (context, controller, focusNode, _) {
        return TextFormField(
          controller: controller,
          focusNode: focusNode,
          decoration: const InputDecoration(
            labelText: 'Τμήμα',
            border: OutlineInputBorder(),
            hintText: 'Πληκτρολογήστε για αναζήτηση…',
          ),
          textCapitalization: TextCapitalization.none,
          onChanged: _syncDepartmentSelection,
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return _autocompleteOptionsView(context, onSelected, options);
      },
    );
  }

  Widget _buildUserAutocomplete() {
    return RawAutocomplete<String>(
      textEditingController: _userController,
      focusNode: _userFocusNode,
      optionsBuilder: (textEditingValue) {
        return _filterOptions(_userLabels, textEditingValue.text);
      },
      displayStringForOption: (option) => option,
      onSelected: (selection) {
        _userController.text = selection;
        _syncUserSelection(selection);
      },
      fieldViewBuilder: (context, controller, focusNode, _) {
        return TextFormField(
          controller: controller,
          focusNode: focusNode,
          decoration: const InputDecoration(
            labelText: 'Υπάλληλος',
            border: OutlineInputBorder(),
            hintText: 'Πληκτρολογήστε για αναζήτηση…',
          ),
          textCapitalization: TextCapitalization.none,
          onChanged: _syncUserSelection,
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return _autocompleteOptionsView(context, onSelected, options);
      },
    );
  }

}

enum _ChoiceMode { disconnect, reassign, delete, linkUser }

class _LockDiagnosticSection extends StatefulWidget {
  const _LockDiagnosticSection({required this.dbPath});

  final String dbPath;

  @override
  State<_LockDiagnosticSection> createState() => _LockDiagnosticSectionState();
}

class _LockDiagnosticSectionState extends State<_LockDiagnosticSection> {
  late final Future<String> _future;

  @override
  void initState() {
    super.initState();
    _future = const LockDiagnosticService().detectLockingProcess(widget.dbPath);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text(
        'Διαγνωστικό κλειδώματος',
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
      subtitle: Text(
        'Όπως στην επανεκκίνηση ελέγχου βάσης (Sysinternals handle / PowerShell).',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      children: [
        FutureBuilder<String>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snap.hasError) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Σφάλμα: ${snap.error}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              );
            }
            return SelectableText(
              snap.data ?? '—',
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                fontFamilyFallback: const ['Consolas', 'monospace'],
              ),
            );
          },
        ),
      ],
    );
  }
}
