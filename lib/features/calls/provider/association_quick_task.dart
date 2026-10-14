import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../directory/providers/catalog_validation_provider.dart';
import '../../tasks/models/task.dart';
import '../../tasks/providers/task_service_provider.dart';
import 'call_mutation_refresh.dart';
import 'smart_entity_selector_provider.dart';

/// Η γρήγορη εκκρεμότητα του κύκλου του «+»: μία ανά κύκλο, που γεννιέται με
/// την πρώτη νέα εγγραφή και συμπληρώνεται από τις επόμενες.
///
/// Ο αριθμός της εκκρεμότητας ζει στον [SmartEntitySelectorNotifier]
/// (`associationQuickTaskId`), ώστε να τον μηδενίζει το κλείσιμο του κύκλου.
class AssociationQuickTask {
  AssociationQuickTask(this.host);

  final SmartEntitySelectorNotifier host;

  Ref get ref => host.selectorRef;

  /// Μία γρήγορη εκκρεμότητα ανά κύκλο: δημιουργία ή append/merge στην υπάρχουσα.
  Future<void> sync({
    required bool newEntityEligible,
    required bool associationWorkDone,
    required String? summaryText,
    required String? callerName,
    required int? callerId,
    required int? departmentId,
    required int? equipmentId,
    String? phoneText,
    String? userText,
    String? equipmentText,
    String? departmentText,
  }) async {
    final taskService = ref.read(taskServiceProvider);
    final summary = summaryText?.trim();
    final hasSummary = summary != null && summary.isNotEmpty;
    final existingId = host.associationQuickTaskId;
    if (existingId != null) {
      var touched = false;
      if (hasSummary && (newEntityEligible || associationWorkDone)) {
        final appended = await taskService.appendToQuickAddDescription(
          existingId,
          summary,
        );
        if (appended) touched = true;
      }
      final merged = await taskService.mergeQuickAddEntitySnapshot(
        taskId: existingId,
        callerId: callerId,
        departmentId: departmentId,
        equipmentId: equipmentId,
        phoneText: phoneText,
        userText: userText,
        equipmentText: equipmentText,
        departmentText: departmentText,
      );
      if (merged) touched = true;
      if (touched) invalidateTaskListProviders(ref);
      return;
    }

    if (!newEntityEligible) return;

    final id = await _insert(
      callerName: callerName,
      summaryText: summaryText,
      callerId: callerId,
      departmentId: departmentId,
      equipmentId: equipmentId,
      phoneText: phoneText,
      userText: userText,
      equipmentText: equipmentText,
      departmentText: departmentText,
    );
    host.associationQuickTaskId = id;
    invalidateTaskListProviders(ref);
  }

  /// Οι υποδείξεις κανόνων για τα πεδία της γρήγορης καταχώρησης.
  ///
  /// Αν οι κανόνες δεν φορτώνονται (π.χ. βάση σε μετάβαση), η καταχώρηση
  /// προχωρά κανονικά χωρίς υποδείξεις — ποτέ δεν εμποδίζεται.
  Future<List<String>> _validationHints({
    String? callerName,
    String? phones,
    String? departmentName,
    String? equipmentCode,
  }) async {
    try {
      final service = await ref.read(catalogValidationServiceProvider.future);
      return service.quickAddHints(
        callerName: callerName,
        phones: phones,
        departmentName: departmentName,
        equipmentCode: equipmentCode,
      );
    } catch (_) {
      return const [];
    }
  }

  Future<int> _insert({
    required String? callerName,
    required String? summaryText,
    required int? callerId,
    required int? departmentId,
    required int? equipmentId,
    String? phoneText,
    String? userText,
    String? equipmentText,
    String? departmentText,
  }) async {
    final cleanSummary = summaryText?.trim();
    final caller = callerName?.trim();
    final descriptionCore = cleanSummary?.isNotEmpty == true
        ? cleanSummary!
        : (caller?.isNotEmpty == true
              ? 'Ενημερώθηκε οντότητα καλούντα'
              : 'Quick add');
    // Οι κανόνες επικύρωσης δεν διακόπτουν τη γρήγορη καταχώρηση — οι
    // υποδείξεις τους ταξιδεύουν στην εκκρεμότητα, για έλεγχο με την ησυχία
    // του χρήστη. Καθαρή καταχώρηση δεν προσθέτει καμία γραμμή.
    final hints = await _validationHints(
      callerName: userText ?? caller,
      phones: phoneText,
      departmentName: departmentText,
      equipmentCode: equipmentText,
    );
    final hintBlock = hints.isEmpty
        ? ''
        : '\n${Task.validationHintHeader}\n'
              '${hints.map((h) => '${Task.validationHintPrefix}$h').join('\n')}';
    final quickDescription = '${Task.quickAddTag} $descriptionCore$hintBlock';
    return ref
        .read(taskServiceProvider)
        .createFromCall(
          callId: null,
          callerName: caller,
          description: quickDescription,
          callDate: DateTime.now(),
          callerId: callerId,
          equipmentId: equipmentId,
          departmentId: departmentId,
          phoneId: null,
          phoneText: phoneText?.isEmpty == true ? null : phoneText,
          userText: userText?.isEmpty == true ? null : userText,
          equipmentText: equipmentText?.isEmpty == true ? null : equipmentText,
          departmentText: departmentText?.isEmpty == true
              ? null
              : departmentText,
          priority: SmartEntitySelectorNotifier.criticalTaskPriority,
          categoryName: Task.quickAddCategoryEl,
        );
  }
}
