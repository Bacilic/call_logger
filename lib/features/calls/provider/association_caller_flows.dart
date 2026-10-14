import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/department_repository.dart';
import '../../../core/database/equipment_repository.dart';
import '../../../core/database/phone_repository.dart';
import '../../../core/database/sqlite_types.dart';
import '../../../core/database/user_repository.dart';
import '../../../core/directory/department_change_assets.dart';
import '../../../core/directory/phone_department_policy.dart';
import '../../../core/services/lookup_service.dart';
import '../../../core/utils/name_parser.dart';
import '../../../core/utils/phone_list_parser.dart';
import '../../directory/providers/directory_cache_refresh.dart';
import '../models/equipment_model.dart';
import '../models/user_model.dart';
import 'association_questions.dart';
import 'association_quick_task.dart';
import 'lookup_provider.dart';
import 'quick_add_undo_record.dart';
import 'smart_entity_selector_association.dart';
import 'smart_entity_selector_provider.dart';

/// Οι δύο ροές του «+» — νέος και υπάρχων καλών.
///
/// Ίδια σειρά και στις δύο: **πρώτα όλες οι ερωτήσεις** χωρίς καμία εγγραφή
/// ([AssociationQuestions]) — η «Ακύρωση» αφήνει τη βάση ανέγγιχτη — **μετά
/// οι εγγραφές**, και στο τέλος η φόρμα, το μήνυμα και η γρήγορη εκκρεμότητα
/// ([AssociationQuickTask]).
class AssociationCallerFlows {
  AssociationCallerFlows(this.association);

  final SmartEntitySelectorAssociation association;

  SmartEntitySelectorNotifier get host => association.host;

  SmartEntitySelectorState get state => host.selectorState;
  set state(SmartEntitySelectorState value) => host.selectorState = value;

  Ref get ref => host.selectorRef;

  AssociationQuestions get _questions => association.questions;

  AssociationQuickTask get _quickTask => association.quickTask;

  static const _containerGone =
      'Σφάλμα αποθήκευσης: το container δεν είναι ενεργό.';

  /// Το τμήμα που εννοεί η φόρμα: το επιλεγμένο, αλλιώς [created] (μόλις
  /// δημιουργημένο), αλλιώς αυτό που ταιριάζει στο κείμενο του πεδίου.
  int? _formDepartmentId(LookupService? lookup, {int? created}) =>
      state.selectedDepartmentId ??
      created ??
      lookup?.findDepartmentByName(state.departmentText)?.id;

  /// Μεταφορά, όχι μοιρασιά: ο εξοπλισμός φεύγει από τους κατόχους του άλλου
  /// τμήματος, αφού ο χρήστης απάντησε ρητά «Ναι». Καλείται **μετά** τη
  /// σύνδεση με τον νέο κάτοχο, ώστε ο εξοπλισμός να μη μείνει ποτέ ορφανός.
  Future<void> _releaseMovedEquipment(
    EquipmentRepository equipmentRepo,
    EquipmentMoveAnswer move,
  ) async {
    final equipmentId = move.equipmentId;
    if (equipmentId == null) return;
    for (final owner in move.ownersToRelease) {
      final ownerId = owner.id;
      if (ownerId == null) continue;
      await equipmentRepo.unlinkUserFromEquipment(ownerId, equipmentId);
    }
  }

  /// Εφαρμόζει την απάντηση της ερώτησης σύγκρουσης τηλεφώνου — μόνο αφού
  /// έχουν απαντηθεί όλες οι ερωτήσεις και υπάρχει πια το τμήμα-στόχος.
  Future<void> _applyPhoneResolutions({
    required PhoneRepository phonesRepo,
    required UserPhoneConflictBatchResult? resolutions,
    required int? targetDepartmentId,
  }) async {
    if (resolutions == null) return;
    await PhoneDepartmentPolicy.applyUserPhoneConflictResolutions(
      phones: phonesRepo,
      resolutions: resolutions,
      targetDepartmentId: targetDepartmentId,
    );
    ref.invalidate(lookupServiceProvider);
    await ref.read(lookupServiceProvider.future);
  }

  static String? _nullIfEmpty(String text) {
    final trimmed = text.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  // ── Νέος καλών ─────────────────────────────────────────────────────────

  Future<String?> associateNewCaller({
    required Database db,
    required LookupService? lookup,
    required int auditSince,
    required BuildContext? context,
  }) async {
    final input = await _readNewCallerInput(db, lookup);
    if (context != null && !context.mounted) return null;
    try {
      final answers = await _askNewCallerQuestions(input, context);
      if (answers == null) return null;
      final created = await _writeNewCaller(db, input, answers);
      // Το μήνυμα λέει ό,τι ΕΓΙΝΕ — και το ίδιο κείμενο γίνεται περίληψη της
      // γρήγορης εκκρεμότητας, όπως και για τον υπάρχοντα καλούντα. Η
      // περιγραφή του κουμπιού είναι πρόβλεψη πριν από τις ερωτήσεις.
      final message = _newCallerMessage(input, answers);
      final error = await _showNewCallerInForm(
        input,
        answers,
        created,
        message,
      );
      if (error != null) return error;
      await host.trackDerivativeAuditsSince(auditSince);
      return message;
    } catch (e, st) {
      return await association.saveFailed(e, st);
    }
  }

  /// Ό,τι γράφει η φόρμα, και τι **υπήρχε ήδη** — πριν αλλάξει οτιδήποτε,
  /// ώστε μήνυμα και αναίρεση να ξεχωρίζουν το νέο από το υπάρχον.
  Future<_NewCallerInput> _readNewCallerInput(
    Database db,
    LookupService? lookupBefore,
  ) async {
    final name = NameParserUtility.stripDisplayDecorations(
      state.normalizedCallerDisplayText,
    );
    final phone = state.selectedPhone?.trim();
    // Εταιρεία δεν γίνεται κάτοχος εξοπλισμού: ο νέος καλών δημιουργείται
    // κανονικά με το τηλέφωνό του, αλλά ο κωδικός του μηχανήματος μένει
    // αναφορά της κλήσης και δεν δένεται πάνω του.
    final equipmentCode = state.departmentAcceptsEquipment(lookupBefore)
        ? state.equipmentText.trim()
        : '';
    final departmentText = state.departmentText.trim();
    final departmentExisted =
        departmentText.isNotEmpty &&
        await DepartmentRepository(db).departmentNameExists(departmentText);
    final phoneExisted = (phone != null && phone.isNotEmpty)
        ? await PhoneRepository(db).phoneNumberExists(phone)
        : false;
    final equipmentExisted = equipmentCode.isNotEmpty
        ? await EquipmentRepository(db).equipmentCodeExists(equipmentCode)
        : false;

    final lookup = ref.read(lookupServiceProvider).value?.service;
    final departmentId = _formDepartmentId(lookup);
    return (
      name: name,
      parsed: NameParserUtility.parse(name),
      phone: phone,
      equipmentCode: equipmentCode,
      departmentText: departmentText,
      departmentExisted: departmentExisted,
      phoneExisted: phoneExisted,
      equipmentExisted: equipmentExisted,
      lookup: lookup,
      departmentId: departmentId,
      createsDepartment: departmentId == null && departmentText.isNotEmpty,
    );
  }

  /// Οι ερωτήσεις γίνονται ΠΡΙΝ δημιουργηθεί οτιδήποτε — και το νέο τμήμα:
  /// `null` = «Ακύρωση», και η βάση μένει ανέγγιχτη.
  Future<_NewCallerAnswers?> _askNewCallerQuestions(
    _NewCallerInput input,
    BuildContext? context,
  ) async {
    final equipmentMove = await _questions.askEquipmentMove(
      context: context,
      lookup: input.lookup,
      equipmentCode: input.equipmentCode,
      newOwnerId: null,
      targetDepartmentId: input.departmentId,
      newOwnerName: input.name,
    );
    if (equipmentMove.cancelled) return null;

    final phones = PhoneListParser.splitPhones(input.phone);
    if (phones.isEmpty) {
      return (
        equipmentMove: equipmentMove,
        phones: phones,
        phoneForAssociation: input.phone,
        phoneResolutions: null,
      );
    }
    if (context != null && !context.mounted) return null;
    final departmentId = input.departmentId;
    final prepared = await _questions.askPhoneAssociation(
      context: context,
      phone: phones.first,
      targetDepartmentId: departmentId,
      targetIsNewDepartment: input.createsDepartment,
      editingUserId: null,
      userDisplayName: input.name,
      targetDepartmentName: departmentId != null
          ? (input.lookup?.departmentIdToName[departmentId] ??
                input.departmentText)
          : input.departmentText,
    );
    if (prepared.cancelled) return null;
    final preparedPhone = prepared.phone;
    return (
      equipmentMove: equipmentMove,
      phones: preparedPhone == null
          ? <String>[]
          : PhoneListParser.splitPhones(preparedPhone),
      phoneForAssociation: preparedPhone,
      phoneResolutions: prepared.resolutions,
    );
  }

  /// Οι εγγραφές του νέου καλούντα, και η προσφορά αναίρεσης της στιγμής.
  Future<({int userId, int? departmentId})> _writeNewCaller(
    Database db,
    _NewCallerInput input,
    _NewCallerAnswers answers,
  ) async {
    var departmentId = input.departmentId;
    if (input.createsDepartment) {
      departmentId = await DepartmentRepository(
        db,
      ).getOrCreateDepartmentIdByName(state.departmentText.trim());
    }
    await _applyPhoneResolutions(
      phonesRepo: PhoneRepository(db),
      resolutions: answers.phoneResolutions,
      targetDepartmentId: departmentId,
    );
    final users = UserRepository(db);
    final userId = await users.insertUser(
      firstName: input.parsed.firstName,
      lastName: input.parsed.lastName,
      phones: answers.phones.isEmpty ? null : answers.phones,
      departmentId: departmentId,
    );
    await users.updateAssociationsIfNeeded(
      userId,
      answers.phoneForAssociation,
      input.equipmentCode.isNotEmpty ? input.equipmentCode : null,
    );
    await _releaseMovedEquipment(
      EquipmentRepository(db),
      answers.equipmentMove,
    );

    // Η προσφορά αναίρεσης της στιγμής: μόνο ό,τι δεν υπήρχε πριν.
    host.lastQuickAddUndo = QuickAddUndoRecord(
      createdUserId: userId,
      createdUserName: input.name,
      createdDepartmentId: input.departmentExisted ? null : departmentId,
      createdDepartmentName: input.departmentExisted
          ? null
          : input.departmentText,
      createdPhone: (!input.phoneExisted && answers.phones.isNotEmpty)
          ? answers.phones.first
          : null,
      createdEquipmentCode:
          (!input.equipmentExisted && input.equipmentCode.isNotEmpty)
          ? input.equipmentCode
          : null,
    );
    return (userId: userId, departmentId: departmentId);
  }

  /// Ο νέος καλών μπαίνει στη φόρμα, οι κατάλογοι ανανεώνονται, και γράφεται
  /// η γρήγορη εκκρεμότητα. Επιστρέφει μήνυμα σφάλματος μόνο αν η οθόνη
  /// έκλεισε στο μεταξύ.
  Future<String?> _showNewCallerInForm(
    _NewCallerInput input,
    _NewCallerAnswers answers,
    ({int userId, int? departmentId}) created,
    String message,
  ) async {
    final s = state;
    final lookupNow = ref.read(lookupServiceProvider).value?.service;
    final departmentIdNow = _formDepartmentId(
      lookupNow,
      created: created.departmentId,
    );
    final equipTrim = s.equipmentText.trim();
    final departmentTrim = s.departmentText.trim();
    // Όνομα τμήματος: από το lookup αν το ξέρει ήδη, αλλιώς από το πεδίο —
    // το νεοδημιουργημένο τμήμα δεν έχει προλάβει να μπει στο cache.
    final departmentNameNow = departmentIdNow == null
        ? null
        : (lookupNow?.departmentIdToName[departmentIdNow] ?? departmentTrim);
    state = state.copyWith(
      selectedCaller: UserModel(
        id: created.userId,
        firstName: input.parsed.firstName,
        lastName: input.parsed.lastName,
        phones: answers.phones,
        departmentId: departmentIdNow,
        departmentName: departmentNameNow,
      ),
      selectedDepartmentId: departmentIdNow,
      selectedEquipment: equipTrim.isNotEmpty
          ? EquipmentModel(code: equipTrim)
          : s.selectedEquipment,
      callerDisplayText: s.callerDisplayText.trim().isNotEmpty
          ? s.callerDisplayText
          : input.name,
      departmentText: s.departmentText,
    );
    host.callerAwaitingPhoneAssociation = answers.phones.isEmpty;
    await refreshDirectoryCaches(
      ref,
      users: true,
      equipment: input.equipmentCode.isNotEmpty,
      departments: input.departmentText.isNotEmpty,
    );
    if (!ref.mounted) return _containerGone;

    final refreshedLookup = (await ref.read(
      lookupServiceProvider.future,
    )).service;
    final matchedEquipment = equipTrim.isEmpty
        ? const <EquipmentModel>[]
        : refreshedLookup.findEquipmentsByCode(equipTrim);
    // Πλήρες EquipmentModel με id — αλλιώς το hasEquipmentAssociation μένει
    // false και το submit κλήσης ξανατρέχει συσχέτιση + δεύτερη γρήγορη
    // εκκρεμότητα.
    if (matchedEquipment.isNotEmpty) {
      state = state.copyWith(selectedEquipment: matchedEquipment.first);
    }
    await _quickTask.sync(
      newEntityEligible: true,
      associationWorkDone: true,
      summaryText: message,
      callerName: state.selectedCaller?.name ?? state.callerDisplayText.trim(),
      callerId: created.userId,
      departmentId:
          departmentIdNow ??
          refreshedLookup.findDepartmentByName(s.departmentText)?.id,
      equipmentId: matchedEquipment.isEmpty ? null : matchedEquipment.first.id,
      phoneText: s.selectedPhone?.trim(),
      userText: _nullIfEmpty(s.callerDisplayText),
      equipmentText: _nullIfEmpty(equipTrim),
      departmentText: _nullIfEmpty(departmentTrim),
    );
    return null;
  }

  /// Το μήνυμα για νέο καλούντα, γραμμή-γραμμή.
  String _newCallerMessage(_NewCallerInput input, _NewCallerAnswers answers) {
    final department = input.departmentText;
    // Το τηλέφωνο που ΣΥΝΔΕΘΗΚΕ, όχι αυτό της φόρμας: «μένει στο τμήμα
    // του» στην ερώτηση σύγκρουσης σημαίνει ότι δεν δέθηκε με τον καλούντα.
    final phone = answers.phones.isEmpty ? null : answers.phoneForAssociation;
    final code = input.equipmentCode;
    final released = answers.equipmentMove.ownersToRelease;
    final fullName =
        (UserModel(
                  firstName: input.parsed.firstName,
                  lastName: input.parsed.lastName,
                ).name ??
                state.callerDisplayText)
            .trim();
    return <String>[
      'Δημιουργήθηκε νέος χρήστης $fullName'
          '${department.isNotEmpty ? ' στο τμήμα: $department' : ''}',
      if (department.isNotEmpty && !input.departmentExisted)
        'Δημιουργήθηκε νέο τμήμα: $department',
      if (phone != null && phone.isNotEmpty)
        input.phoneExisted
            ? 'Συσχετίστηκε τηλέφωνο: $phone'
            : 'Δημιουργήθηκε νέο τηλέφωνο: $phone',
      if (code.isNotEmpty)
        input.equipmentExisted
            ? 'Συσχετίστηκε εξοπλισμός: $code'
            : 'Δημιουργήθηκε νέος εξοπλισμός: $code',
      if (released.isNotEmpty)
        'Ο εξοπλισμός $code αφαιρέθηκε από: '
            '${released.map((o) => o.name ?? '').join(', ')}',
    ].join('\n');
  }

  // ── Υπάρχων καλών ──────────────────────────────────────────────────────

  Future<String?> associateExistingCaller({
    required Database db,
    required LookupService? lookup,
    required int auditSince,
    required bool updatePrimaryDepartment,
    required BuildContext? context,
  }) async {
    final work = await _readExistingCallerWork(
      db,
      lookup,
      updatePrimaryDepartment,
    );
    if (context != null && !context.mounted) return null;
    try {
      final answers = await _askExistingCallerQuestions(work, lookup, context);
      if (answers == null) return null;
      final written = await _writeExistingCaller(db, work, answers);
      return await _finishExistingCaller(work, answers, written, auditSince);
    } catch (e, st) {
      return await association.saveFailed(e, st);
    }
  }

  /// Τι έχει να γίνει για τον υπάρχοντα καλούντα, και τι από αυτό είναι
  /// **νέα** εγγραφή (κρίνει αν γεννιέται γρήγορη εκκρεμότητα).
  Future<_ExistingCallerWork> _readExistingCallerWork(
    Database db,
    LookupService? lookup,
    bool updatePrimaryDepartment,
  ) async {
    final caller = state.selectedCaller!;
    final phone = state.hasPhoneAssociation(lookup)
        ? null
        : state.selectedPhone?.trim();
    final eqCode = state.hasEquipmentAssociation(lookup)
        ? null
        : state.equipmentText.trim();
    final hadPhoneWork = phone != null && phone.isNotEmpty;
    final hadEqWork = eqCode != null && eqCode.isNotEmpty;
    final newPhoneRow =
        hadPhoneWork && !await PhoneRepository(db).phoneNumberExists(phone);
    final newEquipmentRow =
        hadEqWork && !await EquipmentRepository(db).equipmentCodeExists(eqCode);
    final departmentText = state.departmentText.trim();
    final callerHadNoPrimaryDept =
        caller.departmentId == null &&
        (caller.departmentName ?? '').trim().isEmpty;
    // Όταν ο καλών δεν είχε κύριο τμήμα, η πρώτη ανάθεση τμήματος στο
    // πορτοκαλί βήμα δεν μπλοκάρεται από dialog «Όχι» (δεν υπάρχει παλιό
    // τμήμα προς διατήρηση).
    final updatesPrimaryDepartment =
        updatePrimaryDepartment ||
        (state.hasPendingDepartmentChange &&
            callerHadNoPrimaryDept &&
            departmentText.isNotEmpty);
    final newDepartmentRow =
        updatesPrimaryDepartment &&
        departmentText.isNotEmpty &&
        !await DepartmentRepository(db).departmentNameExists(departmentText);
    return (
      userId: caller.id!,
      phone: phone,
      eqCode: eqCode,
      hadEqWork: hadEqWork,
      updatesPrimaryDepartment: updatesPrimaryDepartment,
      newDepartmentRow: newDepartmentRow,
      newEntityEligible: newPhoneRow || newEquipmentRow || newDepartmentRow,
      // Κρατιέται ΠΡΙΝ από κάθε αλλαγή: μετά την εγγραφή ο καλών έχει ήδη
      // το νέο τμήμα και η γραμμή δεν θα έβγαινε. Μπαίνει στο μήνυμα μόνο
      // αν η μεταφορά έγινε πράγματι.
      departmentChangeLine: state.pendingDepartmentChangeTooltip(lookup),
      callerName: caller.name ?? 'άγνωστος',
    );
  }

  /// Όλες οι ερωτήσεις του «+», πριν από κάθε εγγραφή: `null` = «Ακύρωση»
  /// σε οποιαδήποτε, και τότε δεν γράφεται **τίποτα** — ούτε ο εξοπλισμός.
  Future<_ExistingCallerAnswers?> _askExistingCallerQuestions(
    _ExistingCallerWork work,
    LookupService? lookup,
    BuildContext? context,
  ) async {
    final caller = state.selectedCaller!;
    final departmentText = state.departmentText.trim();
    final knownTargetDepartmentId = _formDepartmentId(lookup);

    // Εξοπλισμός που ανήκει σε υπάλληλο άλλου τμήματος: ρητή ερώτηση.
    final equipmentMove = await _questions.askEquipmentMove(
      context: context,
      lookup: lookup,
      equipmentCode: work.hadEqWork ? work.eqCode! : '',
      newOwnerId: work.userId,
      targetDepartmentId: work.updatesPrimaryDepartment
          ? knownTargetDepartmentId
          : caller.departmentId,
      newOwnerName: work.callerName,
    );
    if (equipmentMove.cancelled) return null;

    // Αλλαγή κύριου τμήματος: «τι απογίνονται όσα κουβαλά». Νέο τμήμα
    // (χωρίς id ακόμη) διαβάζεται ως νοσοκομείο από την ερώτηση.
    final movesDepartment =
        work.updatesPrimaryDepartment &&
        departmentText.isNotEmpty &&
        (knownTargetDepartmentId == null ||
            knownTargetDepartmentId != caller.departmentId);
    AssetsOnDepartmentChange? stayingBehind;
    if (movesDepartment) {
      if (context != null && !context.mounted) return null;
      stayingBehind = await _questions.confirmAssetsOnDepartmentChange(
        context: context,
        caller: caller,
        targetDepartmentId: knownTargetDepartmentId,
        fallbackTargetDepartmentName: state.departmentText.trim(),
      );
      if (stayingBehind == null) return null;
    }

    final phone = work.phone;
    if (phone == null || phone.isEmpty) {
      return (
        equipmentMove: equipmentMove,
        stayingBehind: stayingBehind,
        phoneToLink: phone,
        phoneResolutions: null,
        phoneDepartmentId: null,
      );
    }
    final phoneDepartmentId = caller.departmentId ?? _formDepartmentId(lookup);
    if (context != null && !context.mounted) return null;
    final prepared = await _questions.askPhoneAssociation(
      context: context,
      phone: phone,
      targetDepartmentId: phoneDepartmentId,
      editingUserId: work.userId,
      userDisplayName: caller.name ?? state.callerDisplayText.trim(),
      targetDepartmentName: phoneDepartmentId != null
          ? (lookup?.departmentIdToName[phoneDepartmentId] ?? departmentText)
          : departmentText,
    );
    if (prepared.cancelled) return null;
    return (
      equipmentMove: equipmentMove,
      stayingBehind: stayingBehind,
      phoneToLink: prepared.phone,
      phoneResolutions: prepared.resolutions,
      phoneDepartmentId: phoneDepartmentId,
    );
  }

  /// Οι εγγραφές του υπάρχοντος καλούντα. Επιστρέφει το τμήμα της φόρμας
  /// (δημιουργημένο, αν χρειάστηκε) και αν έγινε κύριο τμήμα του καλούντα.
  Future<_ExistingCallerWrite> _writeExistingCaller(
    Database db,
    _ExistingCallerWork work,
    _ExistingCallerAnswers answers,
  ) async {
    // Από εδώ και κάτω αρχίζουν οι εγγραφές.
    await _applyPhoneResolutions(
      phonesRepo: PhoneRepository(db),
      resolutions: answers.phoneResolutions,
      targetDepartmentId: answers.phoneDepartmentId,
    );
    await UserRepository(db).updateAssociationsIfNeeded(
      work.userId,
      answers.phoneToLink,
      work.hadEqWork ? work.eqCode : null,
    );
    await _releaseMovedEquipment(
      EquipmentRepository(db),
      answers.equipmentMove,
    );

    final lookup = ref.read(lookupServiceProvider).value?.service;
    var departmentId = _formDepartmentId(lookup);
    if (work.updatesPrimaryDepartment &&
        state.departmentText.trim().isNotEmpty) {
      // Αν το τμήμα δεν υπάρχει ακόμα στη βάση, το δημιουργούμε ώστε να
      // πάρουμε id.
      departmentId ??= await DepartmentRepository(
        db,
      ).getOrCreateDepartmentIdByName(state.departmentText.trim());
    }

    // Η ερώτηση «τι απογίνονται όσα κουβαλά» έγινε ήδη· εδώ εφαρμόζεται
    // μόνο η απάντηση.
    final caller = state.selectedCaller!;
    final decision = answers.stayingBehind;
    if (decision == null ||
        departmentId == null ||
        departmentId == caller.departmentId) {
      return (departmentId: departmentId, changed: false);
    }
    // Γράφεται ΜΟΝΟ το τμήμα. Ολόκληρη η καρτέλα από τη μνήμη της φόρμας θα
    // έσβηνε ό,τι δεν κρατά εκείνη (ψευδώνυμο) και θα ξεδένε το τηλέφωνο
    // που μόλις συνδέθηκε πιο πάνω.
    await UserRepository(db).updateUser(work.userId, <String, dynamic>{
      'department_id': departmentId,
    }, expected: null);
    await applyAssetsStayingBehind(
      db: db,
      userId: work.userId,
      oldDepartmentId: caller.departmentId,
      phones: decision.phones,
      equipment: decision.equipment,
      currentPhones: caller.phones,
      equipmentTakenFromCoOwners: decision.takenFromCoOwners,
      newDepartmentId: departmentId,
      phonesLeftWithCoOwners: decision.phonesLeftWithCoOwners,
      phonesTakenFromCoOwners: decision.phonesTakenFromCoOwners,
    );
    return (departmentId: departmentId, changed: true);
  }

  /// Η φόρμα, οι κατάλογοι, το μήνυμα και η γρήγορη εκκρεμότητα του
  /// υπάρχοντος καλούντα.
  Future<String?> _finishExistingCaller(
    _ExistingCallerWork work,
    _ExistingCallerAnswers answers,
    _ExistingCallerWrite written,
    int auditSince,
  ) async {
    final departmentChanged = written.changed;
    final newDepartmentId = departmentChanged ? written.departmentId : null;
    final lookup = ref.read(lookupServiceProvider).value?.service;
    final s = state;
    final phoneToLink = answers.phoneToLink;
    final phoneLinked = phoneToLink != null && phoneToLink.isNotEmpty;
    final currentPhones = List<String>.from(
      s.selectedCaller?.phones ?? const [],
    );
    final updatedPhones =
        phoneLinked &&
            !PhoneListParser.containsPhone(
              PhoneListParser.joinPhones(currentPhones),
              phoneToLink,
            )
        ? [...currentPhones, phoneToLink]
        : currentPhones;
    final eqCode = work.eqCode;
    state = state.copyWith(
      // Αντίγραφο με ΟΛΑ τα στοιχεία του καλούντα: ό,τι έλειπε εδώ
      // (ψευδώνυμο, τοποθεσία, Lansweeper) χανόταν στην επόμενη εγγραφή.
      selectedCaller: s.selectedCaller!.copyWith(
        phones: updatedPhones,
        departmentId: newDepartmentId ?? s.selectedCaller!.departmentId,
        // Αλλαγή κύριου τμήματος: νέο όνομα από lookup ή από το πεδίο
        // (το φρεσκοδημιουργημένο τμήμα λείπει ακόμα από το cache).
        departmentName: !departmentChanged
            ? null
            : (lookup?.departmentIdToName[newDepartmentId] ??
                  s.departmentText.trim()),
      ),
      selectedDepartmentId: newDepartmentId ?? s.selectedDepartmentId,
      selectedEquipment: work.hadEqWork
          ? EquipmentModel(
              id: s.selectedEquipment?.id,
              code: eqCode,
              type: s.selectedEquipment?.type,
              notes: s.selectedEquipment?.notes,
            )
          : s.selectedEquipment,
    );

    await refreshDirectoryCaches(
      ref,
      users: true,
      equipment: work.hadEqWork,
      departments: departmentChanged || work.newDepartmentRow,
    );
    if (!ref.mounted) return _containerGone;
    final refreshedLookup = (await ref.read(
      lookupServiceProvider.future,
    )).service;
    final matchedEquipment = work.hadEqWork
        ? refreshedLookup.findEquipmentsByCode(eqCode!)
        : const <EquipmentModel>[];
    if (matchedEquipment.isNotEmpty) {
      state = state.copyWith(selectedEquipment: matchedEquipment.first);
    }

    final resultMessage = _existingCallerMessage(
      work,
      answers,
      departmentChanged: departmentChanged,
    );
    await _quickTask.sync(
      newEntityEligible: work.newEntityEligible,
      associationWorkDone: phoneLinked || work.hadEqWork || departmentChanged,
      summaryText: resultMessage,
      callerName: s.selectedCaller?.name ?? s.callerDisplayText.trim(),
      callerId: s.selectedCaller?.id,
      departmentId:
          written.departmentId ??
          refreshedLookup.findDepartmentByName(s.departmentText)?.id,
      equipmentId: matchedEquipment.isNotEmpty
          ? matchedEquipment.first.id
          : s.selectedEquipment?.id,
      phoneText: s.selectedPhone?.trim(),
      userText: _nullIfEmpty(s.callerDisplayText),
      equipmentText: _nullIfEmpty(s.equipmentText),
      departmentText: _nullIfEmpty(s.departmentText),
    );
    await host.trackDerivativeAuditsSince(auditSince);
    return resultMessage;
  }

  /// Το μήνυμα για υπάρχοντα καλούντα — `null` όταν τελικά δεν έγινε τίποτα.
  ///
  /// Περιγράφει ό,τι ΕΓΙΝΕ, όχι ό,τι προβλεπόταν πριν από τις ερωτήσεις: ένα
  /// «Όχι» στη μεταφορά δεν αφήνει γραμμή αλλαγής τμήματος.
  String? _existingCallerMessage(
    _ExistingCallerWork work,
    _ExistingCallerAnswers answers, {
    required bool departmentChanged,
  }) {
    final phone = answers.phoneToLink;
    final code = work.eqCode;
    final released = answers.equipmentMove.ownersToRelease;
    final addedParts = <String>[
      if (phone != null && phone.isNotEmpty) 'τηλεφώνου: $phone',
      if (work.hadEqWork) 'εξοπλισμού: $code',
    ];
    final lines = <String>[
      if (addedParts.isNotEmpty)
        'Προσθήκη ${addedParts.join(' και ')} στο ${work.callerName}',
      if (released.isNotEmpty)
        'Ο εξοπλισμός $code αφαιρέθηκε από: '
            '${released.map((o) => o.name ?? '').join(', ')}',
      if (departmentChanged && work.departmentChangeLine != null)
        work.departmentChangeLine!,
    ];
    return lines.isEmpty ? null : lines.join('\n');
  }
}

/// Ό,τι γράφει η φόρμα για τον νέο καλούντα, και τι υπήρχε ήδη στον
/// κατάλογο πριν από το «+».
typedef _NewCallerInput = ({
  String name,
  ({String firstName, String lastName}) parsed,
  String? phone,
  String equipmentCode,
  String departmentText,
  bool departmentExisted,
  bool phoneExisted,
  bool equipmentExisted,
  LookupService? lookup,
  int? departmentId,
  bool createsDepartment,
});

/// Οι απαντήσεις στις ερωτήσεις του «+» για νέο καλούντα.
typedef _NewCallerAnswers = ({
  EquipmentMoveAnswer equipmentMove,
  List<String> phones,
  String? phoneForAssociation,
  UserPhoneConflictBatchResult? phoneResolutions,
});

/// Τι έχει να γίνει για τον υπάρχοντα καλούντα.
typedef _ExistingCallerWork = ({
  int userId,
  String? phone,
  String? eqCode,
  bool hadEqWork,
  bool updatesPrimaryDepartment,
  bool newDepartmentRow,
  bool newEntityEligible,
  String? departmentChangeLine,
  String callerName,
});

/// Οι απαντήσεις στις ερωτήσεις του «+» για υπάρχοντα καλούντα.
typedef _ExistingCallerAnswers = ({
  EquipmentMoveAnswer equipmentMove,
  AssetsOnDepartmentChange? stayingBehind,
  String? phoneToLink,
  UserPhoneConflictBatchResult? phoneResolutions,
  int? phoneDepartmentId,
});

/// Το τμήμα της φόρμας μετά τις εγγραφές, και αν έγινε κύριο του καλούντα.
typedef _ExistingCallerWrite = ({int? departmentId, bool changed});
