import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/models/operator.dart';
import '../../../core/services/current_operator.dart';
import '../../../core/services/operator_identity.dart';
import '../../../core/services/workstation_operators.dart';
import '../../../core/services/profile_availability.dart';
import '../services/selectable_profiles.dart';
import 'admin_override_dialog.dart';
import 'operator_picker_body.dart';

/// Φόρτωση των προφίλ που προσφέρονται προς επιλογή — αντικαθίσταται στα τεστ.
typedef SelectableProfilesLoader = Future<SelectableProfiles> Function();

/// Δημιουργία και ενεργοποίηση νέου προφίλ — αντικαθίσταται στα τεστ.
typedef OperatorProfileCreator =
    Future<Operator> Function(String displayName, bool bindCurrentAccount);

/// Κάθε πότε ξαναδιαβάζονται τα ίχνη όσο ο διάλογος είναι ανοιχτός.
///
/// Πυκνότερο από τον χτύπο παρουσίας (ένα λεπτό) επίτηδες: ο άνθρωπος που
/// περιμένει να αδειάσει ένα προφίλ κοιτάζει την οθόνη, και μια αναμονή
/// ολόκληρου λεπτού θα τον έκανε να κλείσει και να ξανανοίξει τον διάλογο.
const Duration kProfileLockRefreshInterval = Duration(seconds: 15);

Future<SelectableProfiles> _loadSelectableProfiles() async {
  final db = await DatabaseHelper.instance.database;
  return loadSelectableProfiles(db);
}

Future<Operator> _createAndActivateProfile(
  String displayName,
  bool bindCurrentAccount,
) async {
  final db = await DatabaseHelper.instance.database;
  return OperatorIdentity.createAndActivate(
    db,
    displayName: displayName,
    bindCurrentAccount: bindCurrentAccount,
  );
}

/// «Αλλαγή χρήστη» εν λειτουργία — χωρίς επανεκκίνηση.
///
/// Ίδιο περιεχόμενο με την οθόνη «Ποιος είστε;» της εκκίνησης
/// ([OperatorPickerBody]): επιλογή από τα ενεργά προφίλ ή δημιουργία νέου.
/// Η λίστα φορτώνεται **φρέσκια** από τη βάση σε κάθε άνοιγμα — τα προφίλ
/// μπορεί να έχουν αλλάξει από την οθόνη «Χρήστες» εν τω μεταξύ — και
/// **ξαναδιαβάζεται** όσο ο διάλογος μένει ανοιχτός, ώστε ένα προφίλ που
/// ελευθερώνεται να γίνεται επιλέξιμο χωρίς να κλείσει και να ξανανοίξει.
///
/// Η επιλογή **επιβιώνει της επανεκκίνησης**: ο υπολογιστής θυμάται ποιοι
/// έχουν δουλέψει εδώ. Όταν είναι ένας, η επόμενη εκκίνηση τον βάζει κατευθείαν
/// μέσα· όταν είναι περισσότεροι, ρωτά. Το μόνιμο δέσιμο λογαριασμού Windows
/// είναι άλλο πράγμα και γίνεται ρητά, από την οθόνη «Χρήστες».
///
/// Το [refreshEvery] γίνεται `null` στα τεστ που αφήνουν τον διάλογο ανοιχτό:
/// ένας περιοδικός χρονιστής που επιζεί του ελέγχου τον κάνει να αποτύχει.
Future<void> showChangeOperatorDialog(
  BuildContext context, {
  SelectableProfilesLoader loadProfiles = _loadSelectableProfiles,
  OperatorProfileCreator createProfile = _createAndActivateProfile,
  Future<void> Function(Operator operator) activateExisting =
      OperatorIdentity.chooseForSession,
  Future<void> Function(String displayName) keepOnlyCurrent =
      WorkstationOperators.keepOnly,
  Duration? refreshEvery = kProfileLockRefreshInterval,
}) async {
  final selectable = await loadProfiles();
  if (!context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);

  await showDialog<void>(
    context: context,
    builder: (ctx) => _ChangeOperatorDialog(
      initial: selectable,
      loadProfiles: loadProfiles,
      createProfile: createProfile,
      activateExisting: activateExisting,
      keepOnlyCurrent: keepOnlyCurrent,
      messenger: messenger,
      refreshEvery: refreshEvery,
    ),
  );
}

/// Το σώμα του διαλόγου — **με κατάσταση**, γιατί έχει δουλειά που διαρκεί.
///
/// Η επανάληψη της ανάγνωσης χρειάζεται κάποιον που θα ακυρώσει τον χρονιστή
/// όταν ο διάλογος κλείσει· μια απλή συνάρτηση δεν έχει πού να τον φυλάξει.
class _ChangeOperatorDialog extends StatefulWidget {
  const _ChangeOperatorDialog({
    required this.initial,
    required this.loadProfiles,
    required this.createProfile,
    required this.activateExisting,
    required this.keepOnlyCurrent,
    required this.messenger,
    required this.refreshEvery,
  });

  final SelectableProfiles initial;
  final SelectableProfilesLoader loadProfiles;
  final OperatorProfileCreator createProfile;
  final Future<void> Function(Operator operator) activateExisting;
  final Future<void> Function(String displayName) keepOnlyCurrent;
  final ScaffoldMessengerState messenger;
  final Duration? refreshEvery;

  @override
  State<_ChangeOperatorDialog> createState() => _ChangeOperatorDialogState();
}

class _ChangeOperatorDialogState extends State<_ChangeOperatorDialog> {
  late SelectableProfiles _selectable = widget.initial;
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    _syncRefreshTimer();
  }

  /// Ο χρονιστής ζει **μόνο όσο υπάρχει κάτι κλειδωμένο**.
  ///
  /// Η ανανέωση υπάρχει για να ξεκλειδώνει· χωρίς κλείδωμα δεν έχει τι να
  /// ανακοινώσει, και σε βάση πάνω από κοινόχρηστο φάκελο κάθε ανάγνωση κάθε
  /// δεκαπέντε δευτερόλεπτα είναι κίνηση που πληρώνουν όλοι οι σταθμοί.
  void _syncRefreshTimer() {
    final locked = _selectable.availability.values.any(
      (state) => state.kind != ProfileLockKind.free,
    );
    if (!locked) {
      _refresh?.cancel();
      _refresh = null;
      return;
    }
    if (_refresh != null) return;
    final every = widget.refreshEvery;
    if (every == null) return;
    _refresh = Timer.periodic(every, (_) => unawaited(_reload()));
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  /// Ξαναδιαβάζει σιωπηλά. **Ποτέ μοιραίο:** μια αποτυχία της ανανέωσης δεν
  /// επιτρέπεται να ρίξει τον διάλογο — η προηγούμενη εικόνα μένει στη θέση της.
  Future<void> _reload() async {
    try {
      final fresh = await widget.loadProfiles();
      if (!mounted) return;
      setState(() => _selectable = fresh);
      _syncRefreshTimer();
    } catch (_) {
      // Η επόμενη ανανέωση ξαναδοκιμάζει.
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = CurrentOperator.active;
    // Η ένδειξη έχει νόημα μόνο όταν ο σταθμός όντως ρωτά, και μόνο όταν ξέρουμε
    // ποιον να κρατήσει.
    final showWorkstationNotice =
        active != null && _selectable.workstationProfiles.length > 1;

    return AlertDialog(
      title: const Text('Αλλαγή χρήστη'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OperatorPickerBody(
                profiles: _selectable.profiles,
                presence: _selectable.presence,
                availability: _selectable.availability,
                presenceUnavailable: _selectable.presenceUnavailable,
                confirmAdminOverride: (operator, station) =>
                    confirmAdminProfileOpenElsewhere(
                      context,
                      operator: operator,
                      station: station,
                    ),
                suggestedName: OperatorIdentity.suggestedDisplayName(),
                hasWindowsAccount:
                    OperatorIdentity.suggestedDisplayName().isNotEmpty,
                onPick: (operator) async {
                  await widget.activateExisting(operator);
                  if (!mounted) return;
                  Navigator.of(this.context).pop();
                },
                onCreate: (displayName, bindCurrentAccount) async {
                  await widget.createProfile(displayName, bindCurrentAccount);
                  if (!mounted) return;
                  Navigator.of(this.context).pop();
                },
              ),
              if (showWorkstationNotice)
                _WorkstationMemoryNotice(
                  rememberedCount: _selectable.workstationProfiles.length,
                  onKeepOnlyMe: () async {
                    await widget.keepOnlyCurrent(active.displayName);
                    if (mounted) Navigator.of(this.context).pop();
                    widget.messenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          'Αυτός ο υπολογιστής θυμάται πλέον μόνο '
                          '«${active.displayName}» και δεν θα ξαναρωτήσει '
                          'στην εκκίνηση.',
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Άκυρο'),
        ),
      ],
    );
  }
}

/// «Γιατί με ρωτά κάθε φορά;» — και η μία κίνηση που το σταματά.
///
/// Ο συνάδελφος που κάθισε μια φορά για δέκα λεπτά δεν πρέπει να κάνει τον
/// σταθμό να ρωτά για έναν μήνα.
class _WorkstationMemoryNotice extends StatefulWidget {
  const _WorkstationMemoryNotice({
    required this.rememberedCount,
    required this.onKeepOnlyMe,
  });

  final int rememberedCount;
  final Future<void> Function() onKeepOnlyMe;

  @override
  State<_WorkstationMemoryNotice> createState() =>
      _WorkstationMemoryNoticeState();
}

class _WorkstationMemoryNoticeState extends State<_WorkstationMemoryNotice> {
  bool _busy = false;

  Future<void> _keepOnlyMe() async {
    setState(() => _busy = true);
    await widget.onKeepOnlyMe();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1),
          const SizedBox(height: 12),
          Text(
            'Σε αυτόν τον υπολογιστή έχουν δουλέψει ${widget.rememberedCount} '
            'χρήστες, γι\' αυτό η εφαρμογή ρωτά «Ποιος είστε;» σε κάθε '
            'εκκίνηση.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _busy ? null : _keepOnlyMe,
              icon: const Icon(Icons.person_pin_circle_outlined, size: 18),
              label: const Text('Εδώ κάθομαι μόνο εγώ'),
            ),
          ),
        ],
      ),
    );
  }
}
