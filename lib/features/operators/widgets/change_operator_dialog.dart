import 'package:flutter/material.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/models/operator.dart';
import '../../../core/services/current_operator.dart';
import '../../../core/services/operator_identity.dart';
import '../../../core/services/workstation_operators.dart';
import '../services/selectable_profiles.dart';
import 'operator_picker_body.dart';

/// Φόρτωση των προφίλ που προσφέρονται προς επιλογή — αντικαθίσταται στα τεστ.
typedef SelectableProfilesLoader = Future<SelectableProfiles> Function();

/// Δημιουργία και ενεργοποίηση νέου προφίλ — αντικαθίσταται στα τεστ.
typedef OperatorProfileCreator =
    Future<Operator> Function(String displayName, bool bindCurrentAccount);

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
/// μπορεί να έχουν αλλάξει από την οθόνη «Χρήστες» εν τω μεταξύ.
///
/// Η επιλογή **επιβιώνει της επανεκκίνησης**: ο υπολογιστής θυμάται ποιοι
/// έχουν δουλέψει εδώ. Όταν είναι ένας, η επόμενη εκκίνηση τον βάζει κατευθείαν
/// μέσα· όταν είναι περισσότεροι, ρωτά. Το μόνιμο δέσιμο λογαριασμού Windows
/// είναι άλλο πράγμα και γίνεται ρητά, από την οθόνη «Χρήστες».
Future<void> showChangeOperatorDialog(
  BuildContext context, {
  SelectableProfilesLoader loadProfiles = _loadSelectableProfiles,
  OperatorProfileCreator createProfile = _createAndActivateProfile,
  Future<void> Function(Operator operator) activateExisting =
      OperatorIdentity.chooseForSession,
  Future<void> Function(String displayName) keepOnlyCurrent =
      WorkstationOperators.keepOnly,
}) async {
  final selectable = await loadProfiles();
  if (!context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  final active = CurrentOperator.active;
  // Η ένδειξη έχει νόημα μόνο όταν ο σταθμός όντως ρωτά, και μόνο όταν ξέρουμε
  // ποιον να κρατήσει.
  final showWorkstationNotice =
      active != null && selectable.workstationProfiles.length > 1;

  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Αλλαγή χρήστη'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OperatorPickerBody(
                profiles: selectable.profiles,
                presence: selectable.presence,
                suggestedName: OperatorIdentity.suggestedDisplayName(),
                hasWindowsAccount:
                    OperatorIdentity.suggestedDisplayName().isNotEmpty,
                onPick: (operator) async {
                  await activateExisting(operator);
                  if (!ctx.mounted) return;
                  Navigator.of(ctx).pop();
                },
                onCreate: (displayName, bindCurrentAccount) async {
                  await createProfile(displayName, bindCurrentAccount);
                  if (!ctx.mounted) return;
                  Navigator.of(ctx).pop();
                },
              ),
              if (showWorkstationNotice)
                _WorkstationMemoryNotice(
                  rememberedCount: selectable.workstationProfiles.length,
                  onKeepOnlyMe: () async {
                    await keepOnlyCurrent(active.displayName);
                    if (ctx.mounted) Navigator.of(ctx).pop();
                    messenger.showSnackBar(
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
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Άκυρο'),
        ),
      ],
    ),
  );
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
