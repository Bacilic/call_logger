import 'package:flutter/material.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/models/operator.dart';
import '../../../core/services/operator_identity.dart';
import 'operator_picker_body.dart';

/// Φόρτωση των προφίλ που προσφέρονται προς επιλογή — αντικαθίσταται στα τεστ.
typedef SelectableProfilesLoader = Future<List<Operator>> Function();

/// Δημιουργία και ενεργοποίηση νέου προφίλ — αντικαθίσταται στα τεστ.
typedef OperatorProfileCreator =
    Future<Operator> Function(String displayName, bool bindCurrentAccount);

Future<List<Operator>> _loadSelectableProfiles() async {
  final db = await DatabaseHelper.instance.database;
  return OperatorIdentity.selectableProfiles(db);
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
/// Η ενεργοποίηση ισχύει **για αυτή τη συνεδρία μόνο**, όπως και στην οθόνη
/// εκκίνησης: το μόνιμο δέσιμο λογαριασμού γίνεται ρητά, ποτέ σιωπηλά.
Future<void> showChangeOperatorDialog(
  BuildContext context, {
  SelectableProfilesLoader loadProfiles = _loadSelectableProfiles,
  OperatorProfileCreator createProfile = _createAndActivateProfile,
  void Function(Operator operator) activateExisting =
      OperatorIdentity.activateForSession,
}) async {
  final profiles = await loadProfiles();
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Αλλαγή χρήστη'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: OperatorPickerBody(
            profiles: profiles,
            suggestedName: OperatorIdentity.suggestedDisplayName(),
            hasWindowsAccount:
                OperatorIdentity.suggestedDisplayName().isNotEmpty,
            onPick: (operator) {
              activateExisting(operator);
              Navigator.of(ctx).pop();
            },
            onCreate: (displayName, bindCurrentAccount) async {
              await createProfile(displayName, bindCurrentAccount);
              if (!ctx.mounted) return;
              Navigator.of(ctx).pop();
            },
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
