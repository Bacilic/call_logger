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
    List<UserSimilarityMatch> matches,
  ) async {
    if (!context.mounted) return const SimilarUsersDialogResult.cancelled();
    final result = await showDialog<SimilarUsersDialogResult>(
      context: context,
      barrierDismissible: true,
      builder: (_) => SimilarUsersDialog(
        matches: matches,
        allowPickExisting: true,
        purpose: SimilarUsersDialogPurpose.callRecord,
      ),
    );
    return result ?? const SimilarUsersDialogResult.cancelled();
  }
}

/// Σύνδεση των ενεργειών υποβολής με τους providers της οθόνης κλήσεων.
class CallEntrySubmitActions implements CallSubmitActions {
  const CallEntrySubmitActions({required this.ref});

  final WidgetRef ref;

  @override
  CallHeaderState get header => ref.read(callHeaderProvider);

  @override
  void attachExistingCaller(UserModel user) =>
      ref.read(callHeaderProvider.notifier).attachExistingCallerForSubmit(user);

  @override
  Future<bool> submitCall() =>
      ref.read(callEntryProvider.notifier).submitCall();
}

/// Έτοιμος controller για το κουμπί «Καταγραφή».
CallSubmitController buildCallSubmitController({
  required WidgetRef ref,
  required BuildContext context,
}) {
  return CallSubmitController(
    actions: CallEntrySubmitActions(ref: ref),
    prompts: CallSubmitDialogPrompts(context: context),
  );
}
