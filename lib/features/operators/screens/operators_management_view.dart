import 'package:flutter/material.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/database/operator_repository.dart';
import '../../../core/models/operator.dart';
import '../../../core/services/current_operator.dart';
import '../services/operator_management.dart';
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

class _OperatorsManagementViewState extends State<OperatorsManagementView> {
  late Future<List<Operator>> _operators;

  @override
  void initState() {
    super.initState();
    _operators = _load();
  }

  Future<OperatorManagement> _management() async {
    final db = await DatabaseHelper.instance.database;
    return OperatorManagement(OperatorRepository(db));
  }

  Future<List<Operator>> _load() async {
    return (await _management()).load();
  }

  void _reload() {
    // Σώμα με άγκιστρα, όχι βέλος: η ανάθεση αποτιμάται στην τιμή της, οπότε
    // ένα `setState(() => _operators = _load())` θα επέστρεφε Future — και το
    // Flutter το απορρίπτει ως ασύγχρονη δουλειά μέσα σε setState.
    setState(() {
      _operators = _load();
    });
  }

  Future<void> _openForm({Operator? existing}) async {
    final management = await _management();
    if (!mounted) return;

    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => OperatorFormDialog(
        existing: existing,
        onSubmit: (values) async {
          final result = existing == null
              ? await management.create(
                  displayName: values.displayName,
                  windowsAccount: values.windowsAccount,
                  isAdmin: values.isAdmin,
                )
              : await management.save(
                  existing,
                  displayName: values.displayName,
                  windowsAccount: values.windowsAccount,
                  isAdmin: values.isAdmin,
                  isActive: values.isActive,
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
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: () => _openForm(),
                icon: const Icon(Icons.person_add_alt_1_outlined),
                label: const Text('Νέο προφίλ'),
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Operator>>(
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
              final operators = snapshot.data ?? const <Operator>[];
              if (operators.isEmpty) {
                return const Center(
                  child: Text('Δεν υπάρχει κανένα προφίλ ακόμη.'),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                itemCount: operators.length,
                itemBuilder: (context, index) => _OperatorCard(
                  operator: operators[index],
                  isCurrent:
                      operators[index].id != null &&
                      operators[index].id == CurrentOperator.active?.id,
                  onEdit: () => _openForm(existing: operators[index]),
                ),
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
    required this.onEdit,
  });

  final Operator operator;
  final bool isCurrent;
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
            if (operator.isAdmin) const _Tag(label: 'Διαχειριστής'),
            if (isCurrent) const _Tag(label: 'Εσείς'),
            if (operator.windowsAccount == null)
              const _Tag(label: 'Αυτόνομο'),
            if (muted) const _Tag(label: 'Αρχειοθετημένος'),
          ],
        ),
        subtitle: Row(
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
        trailing: IconButton(
          icon: const Icon(Icons.edit_outlined),
          tooltip: 'Επεξεργασία',
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
