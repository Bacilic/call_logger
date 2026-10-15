import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/database/department_repository.dart';
import '../../../core/database/equipment_repository.dart';
import '../../../core/database/phone_repository.dart';
import '../../../core/database/user_repository.dart';
import '../../../core/services/lookup_service.dart';
import '../../../core/utils/user_facing_error_messages.dart';
import '../../directory/providers/directory_cache_refresh.dart';
import '../../tasks/providers/task_service_provider.dart';
import '../models/equipment_model.dart';
import 'association_caller_flows.dart';
import 'association_questions.dart';
import 'association_quick_task.dart';
import 'call_mutation_refresh.dart';
import 'lookup_provider.dart';
import 'orphan_quick_add_plan.dart';
import 'quick_add_undo_record.dart';
import 'smart_entity_selector_provider.dart';

/// Το «+» της φόρμας κλήσης, τα κοινόχρηστα του τμήματος και η αναίρεση.
///
/// Συνεργάτης του [SmartEntitySelectorNotifier] (Σύνθεση): δουλεύει πάνω στην
/// κατάσταση του host μέσω των δημόσιων γεφυρών του — δεν κρατά δική του.
/// Είναι η μόνη πόρτα προς τον host· η δουλειά μοιράζεται σε τρεις
/// συνεργάτες:
/// - [AssociationQuestions] — οι ερωτήσεις του «+», χωρίς καμία εγγραφή·
/// - [AssociationCallerFlows] — οι ροές νέου και υπάρχοντος καλούντα·
/// - [AssociationQuickTask] — η γρήγορη εκκρεμότητα του κύκλου.
class SmartEntitySelectorAssociation {
  SmartEntitySelectorAssociation(this.host);

  final SmartEntitySelectorNotifier host;

  late final AssociationQuestions questions = AssociationQuestions(ref);
  late final AssociationQuickTask quickTask = AssociationQuickTask(host);
  late final AssociationCallerFlows _callerFlows = AssociationCallerFlows(this);

  SmartEntitySelectorState get state => host.selectorState;
  set state(SmartEntitySelectorState value) => host.selectorState = value;

  Ref get ref => host.selectorRef;

  /// Μηδενίζει τον κύκλο γρήγορης εκκρεμότητας (νέα φόρμα/καθαρισμός/submit).
  void resetQuickTaskCycle() {
    host.associationQuickTaskId = null;
    host.lastQuickAddUndo = QuickAddUndoRecord.empty;
    host.callerAwaitingPhoneAssociation = false;
    host.clearPendingAuditOrigins();
  }

  /// Αναιρεί ό,τι γέννησε η τελευταία γρήγορη καταχώρηση.
  ///
  /// Επιστρέφει το μήνυμα προς τον χρήστη· `null` όταν δεν υπάρχει τίποτα να
  /// αναιρεθεί (η προσφορά έχει ήδη σβήσει ή δεν δημιουργήθηκε ποτέ τίποτα).
  ///
  /// **Φεύγει και η εκκρεμότητα του κύκλου:** θα έμενε να δείχνει σε καρτέλες
  /// που μόλις σβήστηκαν, δηλαδή υπενθύμιση για δουλειά που δεν υπάρχει.
  ///
  /// Η φόρμα γυρίζει στο «πριν»: τα κείμενα που πληκτρολογήσατε μένουν, αλλά η
  /// ταυτοποίηση φεύγει — ακριβώς η κατάσταση πριν πατήσετε «Προσθήκη».
  Future<String?> undoLastQuickAdd() async {
    final record = host.lastQuickAddUndo;
    if (record.isEmpty) return null;
    host.lastQuickAddUndo = QuickAddUndoRecord.empty;

    final db = await DatabaseHelper.instance.database;
    try {
      await applyQuickAddUndo(
        record,
        executor: db,
        users: UserRepository(db),
        phones: PhoneRepository(db),
        equipment: EquipmentRepository(db),
        departments: DepartmentRepository(db),
      );
    } catch (e, st) {
      // Καμία δεύτερη προσπάθεια (απόφαση Διευθυντή 02/10): ο κατάλογος
      // ξαναδιαβάζεται, ώστε ό,τι έμεινε να φαίνεται και να σβήνεται από
      // τον Κατάλογο. Η εκκρεμότητα μένει — περιγράφει ό,τι υπάρχει ακόμη.
      await _refreshAfterFailure('quick add undo failed', e, st);
      final cause = humanizeUserFacingError(e).trim();
      final causeSentence = cause.endsWith('.') ? cause : '$cause.';
      return 'Η αναίρεση δεν ολοκληρώθηκε: $causeSentence '
          'Ό,τι πρόλαβε να σβηστεί έμεινε σβησμένο — ελέγξτε τον Κατάλογο.';
    }

    final taskId = host.associationQuickTaskId;
    if (taskId != null) {
      try {
        await ref.read(taskServiceProvider).deleteTask(taskId);
      } catch (e, st) {
        developer.log(
          'quick add undo: task delete failed',
          name: 'SmartEntitySelectorNotifier',
          error: e,
          stackTrace: st,
        );
      }
      host.associationQuickTaskId = null;
      invalidateTaskListProviders(ref);
    }

    await refreshDirectoryCaches(
      ref,
      users: true,
      equipment: true,
      departments: true,
    );
    if (!ref.mounted) return quickAddUndoSummary(record);

    state = state.copyWith(
      clearSelectedCaller: true,
      clearSelectedEquipment: true,
      callerNoMatch: true,
    );
    host.callerAwaitingPhoneAssociation = false;
    return quickAddUndoSummary(record);
  }

  /// Καταχωρεί τηλέφωνο και/ή εξοπλισμό ως κοινόχρηστα ενός τμήματος, όταν η
  /// φόρμα δεν έχει καλούντα.
  ///
  /// Τέσσερα βήματα, με αυστηρή σειρά και χωρισμένες ευθύνες: **τι θα γραφτεί**
  /// (κρίση), **χρειάζεται έγκριση;** (καθαρός υπολογισμός), **γράψε**, και
  /// **φινάλε** (ανανέωση, οθόνη, μήνυμα, εκκρεμότητα). Το βήμα της εγγραφής
  /// δεν κρίνει τίποτα — διαβάζει μόνο το [OrphanQuickAddPlan].
  Future<OrphanQuickAddResult?> quickAddOrphanToDepartment({
    bool forceSharedOnConflict = false,
  }) async {
    if (!state.needsOrphanDepartmentQuickAdd) return null;

    final lookup = (await ref.read(lookupServiceProvider.future)).service;
    final plan = await _planOrphanQuickAdd(lookup);

    if (!forceSharedOnConflict) {
      final confirmation = orphanQuickAddConflictMessage(plan);
      if (confirmation != null) {
        return OrphanQuickAddResult(
          requiresConfirmation: true,
          message: confirmation,
        );
      }
    }

    try {
      final departmentId = await _resolveOrphanDepartmentId(plan);
      if (departmentId == null) {
        return const OrphanQuickAddResult.failed(
          'Δεν βρέθηκε/δημιουργήθηκε τμήμα.',
        );
      }

      await _writeOrphanShared(plan, departmentId);
      // Ό,τι γεννήθηκε τώρα μπορεί να αναιρεθεί όσο κρατά η στιγμή. Η κρίση
      // «υπήρχε πριν;» έχει ήδη γίνει στο πλάνο — εδώ απλώς επιβιώνει.
      host.lastQuickAddUndo = QuickAddUndoRecord(
        createdDepartmentId: plan.departmentExistedBefore ? null : departmentId,
        createdDepartmentName: plan.departmentExistedBefore
            ? null
            : plan.departmentText,
        createdPhone: (plan.phoneNeedsShared && !plan.phoneExistedBefore)
            ? plan.phone
            : null,
        createdEquipmentCode:
            (plan.equipmentNeedsShared && !plan.equipmentExistedBefore)
            ? plan.equipmentCode
            : null,
      );
      return await _finishOrphanQuickAdd(plan, departmentId);
    } catch (e, st) {
      return OrphanQuickAddResult.failed(await saveFailed(e, st));
    }
  }

  /// Βήμα 1 — τι υπάρχει σήμερα και τι πρόκειται να γραφτεί.
  ///
  /// Η απάντηση στο «τι θα γραφτεί» **δεν υπολογίζεται εδώ**: ζητείται από την
  /// ίδια κρίση που αποφασίζει αν θα εμφανιστεί η γρήγορη καταχώρηση.
  Future<OrphanQuickAddPlan> _planOrphanQuickAdd(LookupService lookup) async {
    final s = state;
    final deptText = s.departmentText.trim();
    final phoneText = s.selectedPhone?.trim();
    final phone = (phoneText != null && phoneText.isNotEmpty)
        ? phoneText
        : null;
    final equipmentText = s.equipmentText.trim();
    final equipmentCode = equipmentText.isEmpty ? null : equipmentText;
    final needsShared = s.orphanNeedsSharedFlags(lookup);

    final db = await DatabaseHelper.instance.database;

    return OrphanQuickAddPlan(
      departmentText: deptText,
      departmentId:
          s.selectedDepartmentId ?? lookup.findDepartmentByName(deptText)?.id,
      phone: phone,
      equipmentCode: equipmentCode,
      phoneUsage: phone == null ? null : lookup.checkPhoneUsage(phone),
      equipmentUsage: equipmentCode == null
          ? null
          : lookup.checkEquipmentUsage(equipmentCode),
      phoneNeedsShared: needsShared.phoneNeedsShared,
      equipmentNeedsShared: needsShared.equipmentNeedsShared,
      departmentExistedBefore:
          deptText.isNotEmpty &&
          await DepartmentRepository(db).departmentNameExists(deptText),
      phoneExistedBefore: phone == null
          ? true
          : await PhoneRepository(db).phoneNumberExists(phone),
      equipmentExistedBefore: equipmentCode == null
          ? true
          : await EquipmentRepository(db).equipmentCodeExists(equipmentCode),
    );
  }

  /// Βήμα 2 — το τμήμα της φόρμας, δημιουργημένο αν δεν υπήρχε.
  Future<int?> _resolveOrphanDepartmentId(OrphanQuickAddPlan plan) async {
    final known = plan.departmentId;
    if (known != null) return known;
    final db = await DatabaseHelper.instance.database;
    return DepartmentRepository(
      db,
    ).getOrCreateDepartmentIdByName(plan.departmentText);
  }

  /// Βήμα 3 — μόνο οι εγγραφές. Καμία κρίση, κανένα μήνυμα.
  Future<void> _writeOrphanShared(
    OrphanQuickAddPlan plan,
    int departmentId,
  ) async {
    if (!plan.writesAnything) return;

    final phone = plan.phone;
    final equipmentCode = plan.equipmentCode;
    final db = await DatabaseHelper.instance.database;
    if (plan.phoneNeedsShared && phone != null) {
      await PhoneRepository(db).updatePhoneDepartment(phone, departmentId);
    }
    if (plan.equipmentNeedsShared && equipmentCode != null) {
      await EquipmentRepository(
        db,
      ).updateEquipmentDepartment(equipmentCode, departmentId);
    }
  }

  /// Βήμα 4 — ανανέωση καταλόγων, ενημέρωση της φόρμας, μήνυμα, εκκρεμότητα.
  Future<OrphanQuickAddResult> _finishOrphanQuickAdd(
    OrphanQuickAddPlan plan,
    int departmentId,
  ) async {
    await refreshDirectoryCaches(
      ref,
      users: plan.phoneNeedsShared,
      equipment: plan.equipmentNeedsShared,
      departments: true,
    );
    if (!ref.mounted) {
      return const OrphanQuickAddResult(
        requiresConfirmation: false,
        message: 'Η συσχέτιση ολοκληρώθηκε αλλά το container δεν είναι ενεργό.',
      );
    }

    final refreshed = (await ref.read(lookupServiceProvider.future)).service;
    final finalDepartment = refreshed.findDepartmentByName(plan.departmentText);
    state = state.copyWith(
      selectedDepartmentId: finalDepartment?.id ?? departmentId,
      departmentText: finalDepartment?.name ?? plan.departmentText,
      callerNoMatch: false,
      equipmentNoMatch: false,
    );

    // Το τμήμα λέγεται πλέον όπως το γράφει ο κατάλογος, όχι όπως πληκτρολογήθηκε.
    final departmentName = state.departmentText.trim();
    final success = orphanQuickAddSuccessMessage(
      phoneWritten: plan.phoneNeedsShared,
      equipmentWritten: plan.equipmentNeedsShared,
      departmentName: departmentName,
    );

    await _syncOrphanQuickTask(
      plan: plan,
      departmentId: finalDepartment?.id ?? departmentId,
      departmentName: departmentName,
      refreshed: refreshed,
      summary: success,
    );

    return OrphanQuickAddResult(
      requiresConfirmation: false,
      message: success,
      successMessage: success,
    );
  }

  /// Η γρήγορη εκκρεμότητα του κύκλου — υπενθύμιση, ποτέ εμπόδιο: την
  /// αποτυχία της την απορροφά το [AssociationQuickTask.sync].
  Future<void> _syncOrphanQuickTask({
    required OrphanQuickAddPlan plan,
    required int departmentId,
    required String departmentName,
    required LookupService refreshed,
    required String summary,
  }) async {
    if (!plan.hasNewEntity && host.associationQuickTaskId == null) return;

    final equipmentCode = plan.equipmentCode;
    final resolved = (equipmentCode != null && equipmentCode.isNotEmpty)
        ? refreshed.findEquipmentsByCode(equipmentCode)
        : const <EquipmentModel>[];

    await quickTask.sync(
      newEntityEligible: plan.hasNewEntity,
      associationWorkDone: plan.writesAnything,
      summaryText: summary,
      callerName: null,
      callerId: null,
      departmentId: departmentId,
      equipmentId: resolved.isNotEmpty ? resolved.first.id : null,
      phoneText: plan.phone,
      userText: null,
      equipmentText: equipmentCode,
      departmentText: departmentName.isEmpty ? null : departmentName,
    );
  }

  /// Το «+» της φόρμας κλήσης: καταχωρεί στον κατάλογο ό,τι η φόρμα ξέρει
  /// αλλά ο κατάλογος όχι. Επιστρέφει το μήνυμα για τον χρήστη· `null` όταν
  /// δεν υπήρχε δουλειά ή ο χρήστης ακύρωσε κάποια ερώτηση.
  ///
  /// Δύο ροές, ίδια σειρά ([AssociationCallerFlows]): **πρώτα όλες οι
  /// ερωτήσεις** χωρίς καμία εγγραφή — η «Ακύρωση» αφήνει τη βάση ανέγγιχτη —
  /// **μετά οι εγγραφές**, και στο τέλος η φόρμα, το μήνυμα και η γρήγορη
  /// εκκρεμότητα.
  Future<String?> associateCurrentIfNeeded({
    bool updatePrimaryDepartment = false,
    BuildContext? context,
  }) async {
    final lookup = ref.read(lookupServiceProvider).value?.service;
    if (!state.needsAssociation(lookup)) return null;

    final db = await DatabaseHelper.instance.database;
    final auditSince = await host.maxAuditLogId(db);
    // Οθόνη που έκλεισε στο μεταξύ: καμία ερώτηση, καμία εγγραφή. Χωρίς
    // οθόνη καθόλου (`null`) κάθε ροή αποφασίζει μόνη της.
    if (context != null && !context.mounted) return null;
    if (state.needsNewCallerCreation) {
      return _callerFlows.associateNewCaller(
        db: db,
        lookup: lookup,
        auditSince: auditSince,
        context: context,
      );
    }
    if (state.selectedCaller?.id == null) return null;
    return _callerFlows.associateExistingCaller(
      db: db,
      lookup: lookup,
      auditSince: auditSince,
      updatePrimaryDepartment: updatePrimaryDepartment,
      context: context,
    );
  }

  /// Αποτυχία στη μέση του «+»: η αιτία γράφεται για διάγνωση, ο χρήστης
  /// παίρνει το ανθρώπινο μήνυμα.
  ///
  /// Ό,τι πρόλαβε να γραφτεί πριν από το σφάλμα μένει στη βάση· οι κατάλογοι
  /// ξαναδιαβάζονται, ώστε η φόρμα να δείχνει ό,τι πράγματι υπάρχει — αλλιώς
  /// το επόμενο «+» ρωτά ξανά για ό,τι έχει ήδη γίνει.
  Future<String> saveFailed(Object error, StackTrace stackTrace) async {
    await _refreshAfterFailure('quick add failed', error, stackTrace);
    return 'Σφάλμα αποθήκευσης: ${humanizeUserFacingError(error)}';
  }

  /// Κοινό σε κάθε εγγραφή του «+» (καλούντας, κοινόχρηστα, αναίρεση) που
  /// σταμάτησε στη μέση: η αιτία γράφεται για διάγνωση και οι κατάλογοι
  /// ξαναδιαβάζονται.
  Future<void> _refreshAfterFailure(
    String what,
    Object error,
    StackTrace stackTrace,
  ) async {
    developer.log(
      what,
      name: 'SmartEntitySelectorNotifier',
      error: error,
      stackTrace: stackTrace,
    );
    try {
      await refreshDirectoryCaches(
        ref,
        users: true,
        equipment: true,
        departments: true,
      );
    } catch (e, st) {
      developer.log(
        '$what: catalog refresh failed too',
        name: 'SmartEntitySelectorNotifier',
        error: e,
        stackTrace: st,
      );
    }
  }
}
