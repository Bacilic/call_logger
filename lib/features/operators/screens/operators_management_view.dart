import 'package:flutter/material.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/database/operator_presence_repository.dart';
import '../../../core/database/operator_repository.dart';
import '../../../core/models/operator.dart';
import '../../../core/models/operator_presence.dart';
import '../../../core/services/current_operator.dart';
import '../../../core/services/permission_service.dart';
import '../services/operator_management.dart';
import '../services/operator_presence_summary.dart';
import '../widgets/operator_form_dialog.dart';

/// «Χρήστες»: ποιοι χειρίζονται την εφαρμογή και με ποιο όνομα υπογράφουν.
///
/// Δεν έχει σχέση με τους Υπαλλήλους του Καταλόγου — εκείνοι είναι το προσωπικό
/// του νοσοκομείου.
class OperatorsManagementView extends StatefulWidget {
  const OperatorsManagementView({super.key});

  @override
  State<OperatorsManagementView> createState() =>
      _OperatorsManagementViewState();
}

/// Ό,τι χρειάζεται η οθόνη, διαβασμένο μαζί σε μία στιγμή.
///
/// Η [readAt] κρατιέται ρητά ώστε το «συνδεδεμένος τώρα» να κρίνεται με τη
/// στιγμή της ανάγνωσης και όχι με ένα δεύτερο ρολόι μέσα στο `build`.
class _ProfilesSnapshot {
  const _ProfilesSnapshot({
    required this.operators,
    required this.presence,
    required this.readAt,
  });

  final List<Operator> operators;
  final Map<int, List<OperatorPresence>> presence;
  final DateTime readAt;
}

class _OperatorsManagementViewState extends State<OperatorsManagementView> {
  late Future<_ProfilesSnapshot> _operators;

  @override
  void initState() {
    super.initState();
    _operators = _load();
  }

  Future<OperatorManagement> _management() async {
    final db = await DatabaseHelper.instance.database;
    return OperatorManagement(OperatorRepository(db));
  }

  Future<_ProfilesSnapshot> _load() async {
    final db = await DatabaseHelper.instance.database;
    final operators = await OperatorManagement(OperatorRepository(db)).load();

    // Τα ίχνη σύνδεσης είναι πληροφορία άνεσης: αν λείπει ο πίνακας (βάση από
    // παλαιότερη έκδοση που δεν αναβαθμίστηκε ακόμη) η οθόνη δείχνει κανονικά
    // τους χρήστες, απλώς χωρίς γραμμή σύνδεσης.
    var marks = const <OperatorPresence>[];
    try {
      marks = await OperatorPresenceRepository(db).getAll();
    } catch (_) {
      marks = const <OperatorPresence>[];
    }

    final byOperator = <int, List<OperatorPresence>>{};
    for (final mark in marks) {
      byOperator.putIfAbsent(mark.operatorId, () => []).add(mark);
    }

    return _ProfilesSnapshot(
      operators: operators,
      presence: byOperator,
      readAt: DateTime.now(),
    );
  }

  void _reload() {
    // Σώμα με άγκιστρα, όχι βέλος: η ανάθεση αποτιμάται στην τιμή της, οπότε
    // ένα `setState(() => _operators = _load())` θα επέστρεφε Future — και το
    // Flutter το απορρίπτει ως ασύγχρονη δουλειά μέσα σε setState.
    setState(() {
      _operators = _load();
    });
  }

  Future<void> _openForm({Operator? existing, bool readOnly = false}) async {
    final management = await _management();
    if (!mounted) return;

    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => OperatorFormDialog(
        existing: existing,
        readOnly: readOnly,
        onSubmit: (values) async {
          final result = existing == null
              ? await management.create(
                  displayName: values.displayName,
                  windowsAccount: values.windowsAccount,
                  isAdmin: values.isAdmin,
                  permissionOverrides: values.permissionOverrides,
                )
              : await management.save(
                  existing,
                  displayName: values.displayName,
                  windowsAccount: values.windowsAccount,
                  isAdmin: values.isAdmin,
                  isActive: values.isActive,
                  permissionOverrides: values.permissionOverrides,
                );
          return result.allowed ? null : result.message;
        },
      ),
    );

    if (saved == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Η ταυτότητα παρακολουθείται ζωντανά: μια «Αλλαγή χρήστη» με την οθόνη
    // ανοιχτή αλλάζει αμέσως και το σήμα «Εσείς» και το τι επιτρέπεται εδώ.
    return ValueListenableBuilder<Operator?>(
      valueListenable: CurrentOperator.listenable,
      builder: (context, activeOperator, _) {
        final canManage = PermissionService.instance.canManageOperators();
        return _buildBody(context, theme, activeOperator, canManage);
      },
    );
  }

  Widget _buildBody(
    BuildContext context,
    ThemeData theme,
    Operator? activeOperator,
    bool canManage,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Ποιοι χειρίζονται την εφαρμογή. Το όνομα εμφάνισης είναι '
                  'αυτό που υπογράφει κάθε ενέργεια στο Ιστορικό.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (canManage) ...[
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: () => _openForm(),
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: const Text('Νέο προφίλ'),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<_ProfilesSnapshot>(
            future: _operators,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Text('Αποτυχία φόρτωσης: ${snapshot.error}'),
                );
              }
              final data = snapshot.data;
              final operators = data?.operators ?? const <Operator>[];
              if (operators.isEmpty) {
                return const Center(
                  child: Text('Δεν υπάρχει κανένα προφίλ ακόμη.'),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                itemCount: operators.length,
                itemBuilder: (context, index) {
                  final operator = operators[index];
                  final marks =
                      data?.presence[operator.id] ?? const <OperatorPresence>[];
                  return _OperatorCard(
                    operator: operator,
                    isCurrent:
                        operator.id != null &&
                        operator.id == activeOperator?.id,
                    canManage: canManage,
                    presence: describeOperatorPresence(
                      marks,
                      data?.readAt ?? DateTime.fromMillisecondsSinceEpoch(0),
                    ),
                    onEdit: () =>
                        _openForm(existing: operator, readOnly: !canManage),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _OperatorCard extends StatelessWidget {
  const _OperatorCard({
    required this.operator,
    required this.isCurrent,
    required this.canManage,
    required this.presence,
    required this.onEdit,
  });

  final Operator operator;
  final bool isCurrent;

  /// Ο θεατής είναι διαχειριστής; Αλλιώς η καρτέλα ανοίγει μόνο για ανάγνωση.
  final bool canManage;

  /// Έτοιμες γραμμές σύνδεσης — η κάρτα δείχνει, δεν υπολογίζει.
  final List<OperatorPresenceLine> presence;

  final VoidCallback onEdit;

  String get _initials {
    final parts = operator.displayName
        .trim()
        .split(RegExp(r'[\s.]+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.characters.take(2).toString().toUpperCase();
    }
    return (parts[0].characters.first + parts[1].characters.first)
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = !operator.isActive;
    final titleColor = muted ? theme.colorScheme.onSurfaceVariant : null;

    final subtitle = operator.windowsAccount == null
        ? 'Χωρίς λογαριασμό Windows — επιλέγεται χειροκίνητα'
        : operator.windowsAccount!;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: onEdit,
        leading: CircleAvatar(
          backgroundColor: muted
              ? theme.colorScheme.surfaceContainerHighest
              : theme.colorScheme.primaryContainer,
          child: Text(
            _initials,
            style: theme.textTheme.labelLarge?.copyWith(
              color: muted
                  ? theme.colorScheme.onSurfaceVariant
                  : theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ),
        title: Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              operator.displayName,
              style: theme.textTheme.titleMedium?.copyWith(color: titleColor),
            ),
            // Ο ρόλος γράφεται πάντα, και για τους δύο. Η απουσία σήμανσης
            // διαβάζεται ως «δεν ξέρω», όχι ως «απλός χρήστης».
            _Tag(label: operator.isAdmin ? 'Διαχειριστής' : 'Χρήστης'),
            if (isCurrent) const _Tag(label: 'Εσείς'),
            if (operator.windowsAccount == null) const _Tag(label: 'Αυτόνομο'),
            if (muted) const _Tag(label: 'Αρχειοθετημένος'),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                if (operator.windowsAccount != null) ...[
                  Icon(
                    Icons.badge_outlined,
                    size: 15,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text(
                    subtitle,
                    style: theme.textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            for (final line in presence)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  children: [
                    Icon(
                      line.online
                          ? Icons.circle
                          : Icons.history_toggle_off_outlined,
                      size: line.online ? 9 : 15,
                      color: line.online
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    SizedBox(width: line.online ? 7 : 4),
                    Flexible(
                      child: Text(
                        line.text,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: line.online
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        trailing: IconButton(
          icon: Icon(
            canManage ? Icons.edit_outlined : Icons.visibility_outlined,
          ),
          tooltip: canManage ? 'Επεξεργασία' : 'Προβολή',
          onPressed: onEdit,
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}
