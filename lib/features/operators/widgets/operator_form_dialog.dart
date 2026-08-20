import 'package:flutter/material.dart';

import '../../../core/models/operator.dart';
import '../../../core/services/operator_identity.dart';

/// Τι επέστρεψε η φόρμα — ό,τι πάτησε ο χρήστης, χωρίς κρίση αν επιτρέπεται.
class OperatorFormValues {
  const OperatorFormValues({
    required this.displayName,
    required this.windowsAccount,
    required this.isAdmin,
    required this.isActive,
  });

  final String displayName;
  final String windowsAccount;
  final bool isAdmin;
  final bool isActive;
}

/// Φόρμα προφίλ χρήστη. Δείχνει και μαζεύει — δεν αποφασίζει.
///
/// Οι κανόνες (μοναδικά ονόματα, τελευταίος διαχειριστής, κατειλημμένος
/// λογαριασμός) ζουν στην υπηρεσία διαχείρισης· εδώ μόνο εμφανίζεται το μήνυμα
/// που εκείνη επιστρέφει.
class OperatorFormDialog extends StatefulWidget {
  const OperatorFormDialog({
    super.key,
    this.existing,
    required this.onSubmit,
  });

  /// `null` για νέο προφίλ.
  final Operator? existing;

  /// Επιστρέφει μήνυμα σφάλματος όταν η αποθήκευση δεν επιτρέπεται, `null`
  /// όταν πέρασε — οπότε ο διάλογος κλείνει.
  final Future<String?> Function(OperatorFormValues values) onSubmit;

  @override
  State<OperatorFormDialog> createState() => _OperatorFormDialogState();
}

class _OperatorFormDialogState extends State<OperatorFormDialog> {
  late final TextEditingController _name;
  late final TextEditingController _account;
  late bool _isAdmin;
  late bool _isActive;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _name = TextEditingController(text: existing?.displayName ?? '');
    _account = TextEditingController(text: existing?.windowsAccount ?? '');
    _isAdmin = existing?.isAdmin ?? false;
    _isActive = existing?.isActive ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _account.dispose();
    super.dispose();
  }

  void _useCurrentWindowsAccount() {
    final current = normalizeWindowsAccount(
      OperatorIdentity.currentWindowsAccount,
    );
    if (current == null) {
      setState(() => _error = 'Δεν βρέθηκε λογαριασμός Windows σε χρήση.');
      return;
    }
    setState(() {
      _account.text = current;
      _error = null;
    });
  }

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final problem = await widget.onSubmit(
      OperatorFormValues(
        displayName: _name.text,
        windowsAccount: _account.text,
        isAdmin: _isAdmin,
        isActive: _isActive,
      ),
    );
    if (!mounted) return;
    if (problem != null) {
      setState(() {
        _saving = false;
        _error = problem;
      });
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isNew = widget.existing == null;

    return AlertDialog(
      title: Text(isNew ? 'Νέος χρήστης' : 'Επεξεργασία χρήστη'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _name,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Όνομα εμφάνισης',
                  helperText:
                      'Με αυτό σφραγίζεται κάθε νέα εγγραφή στο Ιστορικό.',
                  helperMaxLines: 2,
                ),
                onSubmitted: (_) => _saving ? null : _submit(),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _account,
                      decoration: const InputDecoration(
                        labelText: 'Λογαριασμός Windows',
                        helperText:
                            'Κενό = αυτόνομο προφίλ, χωρίς αυτόματη αναγνώριση.',
                        helperMaxLines: 2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: OutlinedButton(
                      onPressed: _useCurrentWindowsAccount,
                      child: const Text('Ο τρέχων'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Divider(),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _isAdmin,
                onChanged: (value) => setState(() => _isAdmin = value),
                secondary: const Icon(Icons.shield_outlined),
                title: const Text('Διαχειριστής'),
                subtitle: const Text('Δεν περνά από τη λίστα δικαιωμάτων'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _isActive,
                onChanged: (value) => setState(() => _isActive = value),
                secondary: const Icon(Icons.how_to_reg_outlined),
                title: const Text('Ενεργός'),
                subtitle: const Text(
                  'Οι αρχειοθετημένοι κρύβονται από τις λίστες επιλογής',
                ),
              ),
              if (!isNew) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.history,
                        size: 20,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Οι παλιές εγγραφές του Ιστορικού κρατούν το όνομα '
                          'που ίσχυε τότε. Η μετονομασία αφορά μόνο τις '
                          'επόμενες.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Ακύρωση'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: const Text('Αποθήκευση'),
        ),
      ],
    );
  }
}
