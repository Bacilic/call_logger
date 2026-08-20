import 'package:flutter/material.dart';

import '../../../core/models/operator.dart';

/// Το κοινό σώμα επιλογής χρήστη: λίστα ενεργών προφίλ ή φόρμα δημιουργίας.
///
/// Μία πηγή για δύο πλαίσια — την οθόνη «Ποιος είστε;» της εκκίνησης και τον
/// διάλογο «Αλλαγή χρήστη» της μπάρας. Δύο αντίγραφα του ίδιου περιεχομένου
/// θα απέκλιναν σιωπηλά στην πρώτη αλλαγή κειμένου ή κανόνα.
class OperatorPickerBody extends StatefulWidget {
  const OperatorPickerBody({
    super.key,
    required this.profiles,
    required this.onPick,
    required this.onCreate,
    this.suggestedName = '',
    this.hasWindowsAccount = true,
  });

  /// Τα ενεργά προφίλ, προς επιλογή. Κενή λίστα στην πρώτη εκκίνηση.
  final List<Operator> profiles;

  final void Function(Operator operator) onPick;

  /// Δημιουργία νέου προφίλ· `bindCurrentAccount` το δένει στον λογαριασμό
  /// Windows ώστε να μην ξαναρωτηθεί.
  final Future<void> Function(String displayName, bool bindCurrentAccount)
  onCreate;

  /// Πρόταση ονόματος — ο λογαριασμός Windows, για να μην πληκτρολογείται.
  final String suggestedName;

  /// Όταν δεν υπάρχει καθόλου λογαριασμός Windows, το δέσιμο δεν προσφέρεται.
  final bool hasWindowsAccount;

  @override
  State<OperatorPickerBody> createState() => _OperatorPickerBodyState();
}

class _OperatorPickerBodyState extends State<OperatorPickerBody> {
  late final TextEditingController _name = TextEditingController(
    text: widget.suggestedName,
  );
  bool _creating = false;
  bool _bindAccount = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Χωρίς προφίλ να διαλέξει κανείς, η μόνη χρήσιμη οθόνη είναι η φόρμα.
    _creating = widget.profiles.isEmpty;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(
        () => _error =
            'Δώστε όνομα — με αυτό θα υπογράφονται οι '
            'ενέργειές σας στο Ιστορικό.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    await widget.onCreate(name, _bindAccount && widget.hasWindowsAccount);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _creating
          ? _buildCreateForm(theme)
          : _buildProfileList(theme),
    );
  }

  List<Widget> _buildProfileList(ThemeData theme) {
    return [
      for (final profile in widget.profiles)
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(profile.displayName),
            trailing: const Icon(Icons.chevron_right),
            onTap: _busy ? null : () => widget.onPick(profile),
          ),
        ),
      const SizedBox(height: 8),
      TextButton.icon(
        onPressed: _busy ? null : () => setState(() => _creating = true),
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: const Text('Δεν είμαι στη λίστα'),
      ),
    ];
  }

  List<Widget> _buildCreateForm(ThemeData theme) {
    return [
      TextField(
        controller: _name,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Το όνομά σας',
          helperText: 'Όπως θέλετε να εμφανίζεται στο Ιστορικό.',
        ),
        onSubmitted: (_) => _busy ? null : _create(),
      ),
      if (widget.hasWindowsAccount) ...[
        const SizedBox(height: 8),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _bindAccount,
          onChanged: _busy
              ? null
              : (value) => setState(() => _bindAccount = value ?? false),
          title: const Text('Αυτός ο υπολογιστής είναι δικός μου'),
          subtitle: const Text(
            'Θα σας αναγνωρίζει αυτόματα και δεν θα ξαναρωτήσει. Αφήστε το '
            'κενό αν τον μοιράζεστε με συναδέλφους.',
          ),
        ),
      ],
      if (_error != null) ...[
        const SizedBox(height: 8),
        Text(
          _error!,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
      ],
      const SizedBox(height: 16),
      FilledButton(
        onPressed: _busy ? null : _create,
        child: const Text('Συνέχεια'),
      ),
      if (widget.profiles.isNotEmpty)
        TextButton(
          onPressed: _busy ? null : () => setState(() => _creating = false),
          child: const Text('Επιστροφή στη λίστα'),
        ),
    ];
  }
}
