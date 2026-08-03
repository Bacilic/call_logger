import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/user_similarity_finder.dart';
import '../../../directory/models/department_model.dart';
import '../../../directory/screens/widgets/similar_department_suggestion_dialog.dart';
import '../../../directory/screens/widgets/similar_users_dialog.dart';
import '../../controllers/caller_quick_add_controller.dart';
import '../../models/user_model.dart';
import '../../provider/call_header_provider.dart';
import '../../provider/smart_entity_selector_state.dart'
    show OrphanQuickAddResult;

/// Η «υλική» πλευρά της γρήγορης καταχώρησης: διάλογοι και snackbars.
///
/// Κάθε ερώτηση επιστρέφει ασφαλή προεπιλογή όταν το UI έχει φύγει από τη σκηνή,
/// ώστε ο controller να μη χρειάζεται να γνωρίζει τίποτα για `mounted`.
class CallerQuickAddDialogPrompts implements CallerQuickAddPrompts {
  const CallerQuickAddDialogPrompts({
    required this.context,
    required this.messenger,
  });

  final BuildContext context;

  /// Κρατιέται ΠΡΙΝ από τους διαλόγους: μετά το κλείσιμό τους το context μπορεί
  /// να μην φτάνει πια σε ScaffoldMessenger.
  final ScaffoldMessengerState messenger;

  @override
  Future<bool> confirmSharedAssetOnConflict(String message) async {
    if (!context.mounted) return false;
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Σύγκρουση δεδομένων'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Ακύρωση'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Ναι, Προσθήκη'),
          ),
        ],
      ),
    );
    return approved ?? false;
  }

  @override
  Future<bool> confirmPrimaryDepartmentChange({
    required String currentDepartmentName,
    required String newDepartmentName,
  }) async {
    if (!context.mounted) return false;
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Αλλαγή κύριου τμήματος'),
        content: Text(
          'Ο χρήστης έχει κύριο τμήμα "$currentDepartmentName". '
          'Να γίνει νέο κύριο τμήμα του χρήστη το "$newDepartmentName";',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Όχι'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Ναι'),
          ),
        ],
      ),
    );
    return approved ?? false;
  }

  @override
  Future<SimilarUsersDialogResult?> resolveSimilarCallers(
    List<UserSimilarityMatch> matches, {
    required String typedDisplayName,
    required String typedDepartmentName,
  }) async {
    if (!context.mounted) return const SimilarUsersDialogResult.cancelled();
    final result = await showDialog<SimilarUsersDialogResult>(
      context: context,
      barrierDismissible: true,
      builder: (_) => SimilarUsersDialog(
        matches: matches,
        allowPickExisting: true,
        typedDisplayName: typedDisplayName,
        typedDepartmentName: typedDepartmentName,
      ),
    );
    return result ?? const SimilarUsersDialogResult.cancelled();
  }

  @override
  Future<SimilarDepartmentDialogResult?> resolveSimilarDepartments({
    required Iterable<DepartmentModel> departments,
    required String typedName,
  }) async {
    if (!context.mounted) {
      return const SimilarDepartmentDialogResult.cancelled();
    }
    return showSimilarDepartmentSuggestionIfNeeded(
      context: context,
      departments: departments,
      typedName: typedName,
    );
  }

  @override
  void announce(String message) {
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}

/// Σύνδεση των ενεργειών του controller με τον notifier της κεφαλίδας κλήσης.
class CallHeaderQuickAddActions implements CallerQuickAddActions {
  const CallHeaderQuickAddActions({required this.ref, required this.context});

  final WidgetRef ref;

  /// Το ίδιο context που δίνει και τους διαλόγους — ο notifier εμφανίζει δικούς
  /// του διαλόγους (συγκρούσεις τηλεφώνου) κατά τη συσχέτιση.
  final BuildContext context;

  CallHeaderNotifier get _notifier => ref.read(callHeaderProvider.notifier);

  @override
  CallHeaderState get header => ref.read(callHeaderProvider);

  @override
  Future<OrphanQuickAddResult?> quickAddOrphan({bool forceShared = false}) {
    return _notifier.quickAddOrphanToDepartment(
      forceSharedOnConflict: forceShared,
    );
  }

  @override
  void selectExistingCaller(UserModel user) => _notifier.setCaller(user);

  @override
  void useExistingDepartment(String departmentName) =>
      _notifier.updateDepartmentText(departmentName);

  @override
  Future<String?> associate({required bool updatePrimaryDepartment}) {
    return _notifier.associateCurrentIfNeeded(
      updatePrimaryDepartment: updatePrimaryDepartment,
      context: context.mounted ? context : null,
    );
  }
}

/// Έτοιμος controller για την κεφαλίδα κλήσης, με UI δεσμεύσεις.
CallerQuickAddController buildCallerQuickAddController({
  required WidgetRef ref,
  required BuildContext context,
  required ScaffoldMessengerState messenger,
}) {
  return CallerQuickAddController(
    actions: CallHeaderQuickAddActions(ref: ref, context: context),
    prompts: CallerQuickAddDialogPrompts(
      context: context,
      messenger: messenger,
    ),
  );
}
