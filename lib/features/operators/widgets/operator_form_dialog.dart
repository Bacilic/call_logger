import 'package:flutter/material.dart';

import '../../../core/models/operator.dart';
import '../../../core/services/operator_identity.dart';
import 'operator_permissions_card.dart';

/// Τι επέστρεψε η φόρμα — ό,τι πάτησε ο χρήστης, χωρίς κρίση αν επιτρέπεται.
class OperatorFormValues {
  const OperatorFormValues({
    required this.displayName,
    required this.windowsAccount,
    required this.isAdmin,
    required this.isActive,
    required this.permissionOverrides,
  });

  final String displayName;
  final String windowsAccount;
  final bool isAdmin;
  final bool isActive;

  /// Μόνο όσα δικαιώματα αποκλίνουν από την προεπιλογή τους.
  final Map<String, bool> permissionOverrides;
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
    this.readOnly = false,
  });

  /// `null` για νέο προφίλ.
  final Operator? existing;

  /// Ο θεατής δεν είναι διαχειριστής: βλέπει τα πάντα, δεν αλλάζει τίποτα.
  ///
  /// Δεν αρκεί να κρυφτεί το κουμπί από τη λίστα — η καρτέλα ανοίγει κιόλας με
  /// διπλό πάτημα στη γραμμή, και ο χρήστης δικαιούται να δει τι ισχύει για
  /// αυτόν χωρίς να ρωτήσει κανέναν.
  final bool readOnly;

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
  late Map<String, bool> _permissionOverrides;
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
    _permissionOverrides = Map<String, bool>.from(
      existing?.permissionOverrides ?? const <String, bool>{},
    );
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
        permissionOverrides: _permissionOverrides,
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

    final readOnly = widget.readOnly;

    return AlertDialog(
      title: Text(
        readOnly
            ? 'Προβολή χρήστη'
            : (isNew ? 'Νέος χρήστης' : 'Επεξεργασία χρήστη'),
      ),
      content: SizedBox(
        width: 460,
        height: 470,
        child: DefaultTabController(
          length: 2,
          child: Column(
            children: [
              const TabBar(
                tabs: [
                  Tab(text: 'Στοιχεία'),
                  Tab(text: 'Δικαιώματα'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    SingleChildScrollView(
                      padding: const EdgeInsets.only(top: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextField(
                            controller: _name,
                            autofocus: !readOnly,
                            readOnly: readOnly,
                            decoration: const InputDecoration(
                              labelText: 'Όνομα εμφάνισης',
                              helperText:
                                  'Με αυτό σφραγίζεται κάθε νέα εγγραφή στο Ιστορικό.',
                              helperMaxLines: 2,
                            ),
                            onSubmitted: (_) =>
                                _saving || readOnly ? null : _submit(),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _account,
                                  readOnly: readOnly,
                                  decoration: const InputDecoration(
                                    labelText: 'Λογαριασμός Windows',
                                    helperText:
                                        'Κενό = αυτόνομο προφίλ, χωρίς αυτόματη αναγνώριση.',
                                    helperMaxLines: 2,
                                  ),
                                ),
                              ),
                              if (!readOnly) ...[
                                const SizedBox(width: 8),
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: OutlinedButton(
                                    onPressed: _useCurrentWindowsAccount,
                                    child: const Text('Ο τρέχων'),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Divider(),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _isAdmin,
                            onChanged: readOnly
                                ? null
                                : (value) => setState(() => _isAdmin = value),
                            secondary: const Icon(Icons.shield_outlined),
                            title: const Text('Διαχειριστής'),
                            subtitle: const Text(
                              'Δεν περνά από τη λίστα δικαιωμάτων',
                            ),
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _isActive,
                            onChanged: readOnly
                                ? null
                                : (value) => setState(() => _isActive = value),
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
                                color:
                                    theme.colorScheme.surfaceContainerHighest,
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
                        ],
                      ),
                    ),
                    SingleChildScrollView(
                      padding: const EdgeInsets.only(top: 12),
                      child: OperatorPermissionsCard(
                        overrides: _permissionOverrides,
                        isAdmin: _isAdmin,
                        readOnly: readOnly,
                        onChanged: (next) =>
                            setState(() => _permissionOverrides = next),
                      ),
                    ),
                  ],
                ),
              ),
              // Έξω από τις καρτέλες: το σφάλμα μπορεί να αφορά οποιαδήποτε από
              // τις δύο, και πρέπει να φαίνεται όποια κι αν είναι ανοιχτή.
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
      actions: readOnly
          // Χωρίς «Αποθήκευση»: κουμπί που δεν θα δεχόταν τίποτα είναι
          // υπόσχεση που δεν τηρείται.
          ? [
              FilledButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Κλείσιμο'),
              ),
            ]
          : [
              TextButton(
                onPressed: _saving
                    ? null
                    : () => Navigator.of(context).pop(false),
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
