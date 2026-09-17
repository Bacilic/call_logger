import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/user_similarity_finder.dart';
import '../../../directory/screens/widgets/similar_users_dialog.dart';
import '../../controllers/call_submit_controller.dart';
import '../../models/user_model.dart';
import '../../provider/call_entry_provider.dart';
import '../../provider/call_header_provider.dart';

/// Η «υλική» πλευρά της καταγραφής κλήσης: ο διάλογος ταυτοποίησης καλούντα.
class CallSubmitDialogPrompts implements CallSubmitPrompts {
  const CallSubmitDialogPrompts({required this.context});

  final BuildContext context;

  @override
  Future<SimilarUsersDialogResult?> resolveSimilarCallers(
    List<UserSimilarityMatch> matches, {
    required String typedDisplayName,
  }) async {
    if (!context.mounted) return const SimilarUsersDialogResult.cancelled();
    final result = await showDialog<SimilarUsersDialogResult>(
      context: context,
      barrierDismissible: true,
      builder: (_) => SimilarUsersDialog(
        matches: matches,
        allowPickExisting: true,
        typedDisplayName: typedDisplayName,
        purpose: SimilarUsersDialogPurpose.callRecord,
      ),
    );
    return result ?? const SimilarUsersDialogResult.cancelled();
  }
}

/// Σύνδεση των ενεργειών υποβολής με τους providers της οθόνης κλήσεων.
///
/// Κρατά **τους ίδιους τους notifiers**, όχι το `ref` που τους δίνει: η υποβολή
/// περνά από τον διάλογο ταυτοποίησης, και όσο αυτός είναι ανοιχτός η φόρμα
/// μπορεί να ξηλωθεί — και τότε κάθε `ref.read` πετάει. Οι notifiers ζουν όσο η
/// εφαρμογή και διαβάζονται μια φορά στην κατασκευή.
class CallEntrySubmitActions implements CallSubmitActions {
  const CallEntrySubmitActions({
    required this.headerNotifier,
    required this.entryNotifier,
  });

  final CallHeaderNotifier headerNotifier;
  final CallEntryNotifier entryNotifier;

  @override
  CallHeaderState get header => headerNotifier.selectorState;

  @override
  void attachExistingCaller(UserModel user) =>
      headerNotifier.attachExistingCallerForSubmit(user);

  @override
  Future<bool> submitCall() => entryNotifier.submitCall();
}

/// Έτοιμος controller για το κουμπί «Καταγραφή».
CallSubmitController buildCallSubmitController({
  required WidgetRef ref,
  required BuildContext context,
}) {
  return CallSubmitController(
    actions: CallEntrySubmitActions(
      headerNotifier: ref.read(callHeaderProvider.notifier),
      entryNotifier: ref.read(callEntryProvider.notifier),
    ),
    prompts: CallSubmitDialogPrompts(context: context),
  );
}
