import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/managed_server.dart';
import '../../../../core/providers/servers_provider.dart';
import '../../../../core/widgets/draggable_dialog_shell.dart';

/// Φόρμα προσθήκης/επεξεργασίας διακομιστή.
///
/// Επιστρέφει `true` όταν αποθηκεύτηκε κάτι, ώστε ο καλών να ανανεώσει τη λίστα.
Future<bool> showServerFormDialog(
  BuildContext context, {
  ManagedServer? server,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _ServerFormDialog(server: server),
  );
  return saved ?? false;
}

class _ServerFormDialog extends ConsumerStatefulWidget {
  const _ServerFormDialog({this.server});

  final ManagedServer? server;

  @override
  ConsumerState<_ServerFormDialog> createState() => _ServerFormDialogState();
}

class _ServerFormDialogState extends ConsumerState<_ServerFormDialog> {
  late final TextEditingController _name;
  late final TextEditingController _host;
  late final TextEditingController _user;
  late final TextEditingController _password;
  late final TextEditingController _notes;

  bool _isDefault = false;
  bool _showPassword = false;
  bool _saving = false;
  bool _testing = false;

  /// Αποτέλεσμα του τελευταίου ελέγχου: μήνυμα + αν ήταν επιτυχία.
  ({String text, bool ok})? _testResult;

  String? _nameError;
  String? _hostError;

  bool get _isNew => widget.server == null;

  @override
  void initState() {
    super.initState();
    final s = widget.server;
    _name = TextEditingController(text: s?.name ?? '');
    _host = TextEditingController(text: s?.host ?? '');
    _user = TextEditingController(text: s?.adminUser ?? 'Administrator');
    _password = TextEditingController(text: s?.adminPassword ?? '');
    _notes = TextEditingController(text: s?.notes ?? '');
    _isDefault = s?.isDefault ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _host.dispose();
    _user.dispose();
    _password.dispose();
    _notes.dispose();
    super.dispose();
  }

  /// Επικυρώνει τα δύο πεδία χωρίς τα οποία η εγγραφή δεν έχει νόημα.
  bool _validate() {
    final nameEmpty = _name.text.trim().isEmpty;
    final hostEmpty = _host.text.trim().isEmpty;
    setState(() {
      _nameError = nameEmpty ? 'Δώσε μια ονομασία' : null;
      _hostError = hostEmpty ? 'Δώσε διεύθυνση IP ή όνομα υπολογιστή' : null;
    });
    return !nameEmpty && !hostEmpty;
  }

  Future<void> _test() async {
    if (_host.text.trim().isEmpty) {
      setState(() => _hostError = 'Δώσε διεύθυνση IP ή όνομα υπολογιστή');
      return;
    }
    setState(() {
      _testing = true;
      _testResult = null;
    });

    final service = ref.read(serverSessionServiceProvider);
    final result = await service.listSessions(
      host: _host.text.trim(),
      adminUser: _user.text.trim(),
      adminPassword: _password.text,
    );

    if (!mounted) return;
    setState(() {
      _testing = false;
      _testResult = result.ok
          ? (
              text:
                  'Ο διακομιστής απάντησε — '
                  '${result.sessions.length} συνεδρίες.',
              ok: true,
            )
          : (text: result.error ?? 'Άγνωστο σφάλμα.', ok: false);
    });
  }

  Future<void> _save() async {
    if (!_validate()) return;
    setState(() => _saving = true);

    final repo = ref.read(serversRepositoryProvider);
    final draft = ManagedServer(
      id: widget.server?.id ?? 0,
      name: _name.text.trim(),
      host: _host.text.trim(),
      adminUser: _user.text.trim(),
      adminPassword: _password.text,
      isDefault: _isDefault,
      sortOrder: widget.server?.sortOrder ?? 0,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
    );

    try {
      if (_isNew) {
        await repo.insert(draft);
      } else {
        await repo.update(draft);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _testResult = (text: 'Αποτυχία αποθήκευσης: $e', ok: false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = _testResult;

    return DraggableDialogShell(
      title: Text(_isNew ? 'Νέος διακομιστής' : 'Επεξεργασία διακομιστή'),
      builder: (titleHandle) => AlertDialog(
        title: titleHandle,
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _name,
                  autofocus: _isNew,
                  decoration: InputDecoration(
                    labelText: 'Ονομασία',
                    hintText: 'π.χ. Medico κύριος',
                    errorText: _nameError,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _host,
                  decoration: InputDecoration(
                    labelText: 'Διεύθυνση (IP ή όνομα υπολογιστή)',
                    hintText: 'π.χ. 192.168.13.82',
                    errorText: _hostError,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _user,
                  decoration: const InputDecoration(
                    labelText: 'Λογαριασμός διαχειριστή',
                    helperText: 'Διαχειριστής ΤΟΥ ΔΙΑΚΟΜΙΣΤΗ, όχι του τομέα',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: !_showPassword,
                  decoration: InputDecoration(
                    labelText: 'Κωδικός',
                    helperText:
                        'Αποθηκεύεται σε καθαρό κείμενο μέσα στη βάση, όπως και '
                        'τα εργαλεία απομακρυσμένης σύνδεσης',
                    helperMaxLines: 2,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _showPassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      tooltip: _showPassword
                          ? 'Απόκρυψη κωδικού'
                          : 'Εμφάνιση κωδικού',
                      onPressed: () =>
                          setState(() => _showPassword = !_showPassword),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _notes,
                  decoration: const InputDecoration(
                    labelText: 'Σημειώσεις (προαιρετικό)',
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  value: _isDefault,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Προεπιλεγμένος διακομιστής'),
                  subtitle: const Text(
                    'Προτείνεται όταν ο εξοπλισμός δεν δείχνει δικό του',
                  ),
                  onChanged: (v) => setState(() => _isDefault = v),
                ),
                const Divider(height: 20),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _testing ? null : _test,
                      icon: _testing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.electrical_services_outlined),
                      label: Text(
                        _testing ? 'Γίνεται έλεγχος…' : 'Έλεγχος σύνδεσης',
                      ),
                    ),
                  ],
                ),
                if (result != null) ...[
                  const SizedBox(height: 10),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: result.ok
                          ? theme.colorScheme.primaryContainer.withValues(
                              alpha: 0.5,
                            )
                          : theme.colorScheme.errorContainer.withValues(
                              alpha: 0.5,
                            ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            result.ok
                                ? Icons.check_circle_outline
                                : Icons.error_outline,
                            size: 18,
                            color: result.ok
                                ? theme.colorScheme.primary
                                : theme.colorScheme.error,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SelectableText(
                              result.text,
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving
                ? null
                : () => Navigator.of(context).pop(false),
            child: const Text('Ακύρωση'),
          ),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Αποθήκευση…' : 'Αποθήκευση'),
          ),
        ],
      ),
    );
  }
}
