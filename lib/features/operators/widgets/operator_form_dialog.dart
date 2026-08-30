import 'package:flutter/material.dart';

import '../../../core/models/operator.dart';
import '../../../core/services/operator_identity.dart';
import '../avatars/operator_avatar_picker.dart';
import '../services/operator_management.dart'
    show kLastAdminDeactivateBlockedMessage, kLastAdminDemoteBlockedMessage;
import 'operator_permissions_card.dart';

/// Τι επέστρεψε η φόρμα — ό,τι πάτησε ο χρήστης, χωρίς κρίση αν επιτρέπεται.
class OperatorFormValues {
  const OperatorFormValues({
    required this.displayName,
    required this.windowsAccount,
    required this.isAdmin,
    required this.isActive,
    required this.permissionOverrides,
    required this.avatarKey,
  });

  final String displayName;
  final String windowsAccount;
  final bool isAdmin;
  final bool isActive;

  /// Το εικονίδιο που διάλεξε ο χρήστης· `null` = κλασικό ανθρωπάκι.
  final String? avatarKey;

  /// Μόνο όσα δικαιώματα αποκλίνουν από την προεπιλογή τους.
  final Map<String, bool> permissionOverrides;
}

/// Φόρμα προφίλ χρήστη. Δείχνει και μαζεύει — δεν αποφασίζει.
///
/// Οι κανόνες (μοναδικά ονόματα, τελευταίος διαχειριστής, κατειλημμένος
/// λογαριασμός) ζουν στην υπηρεσία διαχείρισης· εδώ μόνο εμφανίζεται το μήνυμα
/// που εκείνη επιστρέφει. Ο μόνος άμεσος φραγμός — οι διακόπτες του τελευταίου
/// διαχειριστή — κρίνεται κι αυτός απ' έξω ([lockedAsLastAdmin])· η φόρμα
/// απλώς αρνείται το πάτημα και δείχνει το γιατί.
class OperatorFormDialog extends StatefulWidget {
  const OperatorFormDialog({
    super.key,
    this.existing,
    required this.onSubmit,
    this.readOnly = false,
    this.lockedAsLastAdmin = false,
    this.takenAvatars = const <String, String>{},
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

  /// Το προφίλ είναι ο τελευταίος διαχειριστής που μπορεί να συνδεθεί.
  ///
  /// Οι διακόπτες «Διαχειριστής» και «Ενεργός» δεν κατεβαίνουν: αναβοσβήνουν
  /// και εξηγούν, αντί να αφήσουν τον χρήστη να το μάθει στην Αποθήκευση.
  /// Κρίνεται από τη λίστα που έχει ήδη η οθόνη — ο έλεγχος της αποθήκευσης
  /// παραμένει, ως δίχτυ για τη λίστα που πάλιωσε όσο η καρτέλα ήταν ανοιχτή.
  final bool lockedAsLastAdmin;

  /// Ποια εικονίδια κρατούν **άλλα** ενεργά προφίλ, και ποιος το καθένα.
  ///
  /// Έρχεται έτοιμος από την οθόνη: η φόρμα δείχνει και μαζεύει, δεν ρωτά τη
  /// βάση. Το εικονίδιο αυτού του προφίλ έχει ήδη αφαιρεθεί από τον χάρτη.
  final Map<String, String> takenAvatars;

  @override
  State<OperatorFormDialog> createState() => _OperatorFormDialogState();
}

/// Ποιος διακόπτης αρνήθηκε το πάτημα — για να αναβοσβήσει μόνο αυτός.
enum _DeniedSwitch { admin, active }

class _OperatorFormDialogState extends State<OperatorFormDialog>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _name;
  late final TextEditingController _account;
  late bool _isAdmin;
  late bool _isActive;
  late Map<String, bool> _permissionOverrides;
  late String? _avatarKey;
  String? _error;
  bool _saving = false;

  /// Δύο αναβοσβήματα — η καθιερωμένη γλώσσα του «δεν επιτρέπεται» χωρίς λόγια.
  late final AnimationController _denialBlink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 640),
  );
  late final Animation<double> _denialOpacity = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1, end: 0.25), weight: 1),
    TweenSequenceItem(tween: Tween(begin: 0.25, end: 1), weight: 1),
    TweenSequenceItem(tween: Tween(begin: 1, end: 0.25), weight: 1),
    TweenSequenceItem(tween: Tween(begin: 0.25, end: 1), weight: 1),
  ]).animate(_denialBlink);
  _DeniedSwitch? _denied;

  /// Αρνείται το πάτημα: ο διακόπτης μένει όπου ήταν, αναβοσβήνει δύο φορές
  /// και το μήνυμα λέει το γιατί — το ίδιο που θα έλεγε και η Αποθήκευση.
  void _denySwitch(_DeniedSwitch which, String message) {
    setState(() {
      _denied = which;
      _error = message;
    });
    _denialBlink.forward(from: 0);
  }

  /// Τυλίγει διακόπτη ώστε να μπορεί να αναβοσβήσει όταν αρνηθεί.
  Widget _blinkable(_DeniedSwitch which, Widget tile) {
    return AnimatedBuilder(
      animation: _denialBlink,
      builder: (context, child) => Opacity(
        opacity: _denied == which ? _denialOpacity.value : 1,
        child: child,
      ),
      child: tile,
    );
  }

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
    _avatarKey = existing?.avatarKey;
  }

  @override
  void dispose() {
    _denialBlink.dispose();
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
        avatarKey: _avatarKey,
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

    // Με το όνομα στον τίτλο, φαίνεται αμέσως για ΠΟΙΟΝ γίνονται οι αλλαγές —
    // το αποθηκευμένο όνομα, όχι ό,τι πληκτρολογείται τώρα στο πεδίο.
    final existingName = widget.existing?.displayName.trim() ?? '';
    final personLabel = existingName.isEmpty ? 'χρήστη' : existingName;

    return AlertDialog(
      title: Text(
        isNew
            ? 'Νέος χρήστης'
            : (readOnly ? 'Προβολή $personLabel' : 'Επεξεργασία $personLabel'),
      ),
      content: SizedBox(
        width: 460,
        height: 470,
        child: DefaultTabController(
          length: 3,
          child: Column(
            children: [
              const TabBar(
                tabs: [
                  Tab(text: 'Στοιχεία'),
                  Tab(text: 'Εικονίδιο'),
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
                          _blinkable(
                            _DeniedSwitch.admin,
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              value: _isAdmin,
                              onChanged: readOnly
                                  ? null
                                  : (value) {
                                      if (!value && widget.lockedAsLastAdmin) {
                                        _denySwitch(
                                          _DeniedSwitch.admin,
                                          kLastAdminDemoteBlockedMessage,
                                        );
                                        return;
                                      }
                                      setState(() => _isAdmin = value);
                                    },
                              secondary: const Icon(Icons.shield_outlined),
                              title: const Text('Διαχειριστής'),
                              subtitle: const Text(
                                'Δεν περνά από τη λίστα δικαιωμάτων',
                              ),
                            ),
                          ),
                          _blinkable(
                            _DeniedSwitch.active,
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              value: _isActive,
                              onChanged: readOnly
                                  ? null
                                  : (value) {
                                      if (!value && widget.lockedAsLastAdmin) {
                                        _denySwitch(
                                          _DeniedSwitch.active,
                                          kLastAdminDeactivateBlockedMessage,
                                        );
                                        return;
                                      }
                                      setState(() => _isActive = value);
                                    },
                              secondary: const Icon(Icons.how_to_reg_outlined),
                              title: const Text('Ενεργός'),
                              subtitle: const Text(
                                'Οι απενεργοποιημένοι κρύβονται από τις λίστες επιλογής',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SingleChildScrollView(
                      padding: const EdgeInsets.only(top: 12),
                      child: OperatorAvatarPicker(
                        selected: _avatarKey,
                        takenBy: widget.takenAvatars,
                        readOnly: readOnly,
                        onChanged: (key) => setState(() => _avatarKey = key),
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
