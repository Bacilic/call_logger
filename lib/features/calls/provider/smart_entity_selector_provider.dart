import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/database/directory_support.dart';
import '../../../core/database/department_repository.dart';
import '../../../core/database/equipment_repository.dart';
import '../../../core/database/phone_repository.dart';
import '../../../core/database/user_repository.dart';
import '../../../core/services/lookup_service.dart';
import '../../../core/utils/name_parser.dart';
import '../../../core/utils/phone_list_parser.dart';
import '../../../core/utils/search_text_normalizer.dart';
import 'lookup_provider.dart';
import '../models/equipment_model.dart';
import '../models/user_model.dart';
import '../../directory/models/department_model.dart';
import '../../directory/providers/directory_cache_refresh.dart';
import '../../tasks/models/task.dart';
import '../../tasks/providers/task_service_provider.dart';
import 'call_mutation_refresh.dart';
import '../models/call_model.dart';
import 'smart_entity_selector_state.dart';

export 'smart_entity_selector_state.dart';

part 'smart_entity_selector_lookups.dart';
part 'smart_entity_selector_conflicts.dart';
part 'smart_entity_selector_association.dart';

/// Notifier για τον έξυπνο επιλογέα: update/clear, recentPhones, clearAfterSubmit.
/// Focus και controllers ανήκουν στο widget· το notifier δουλεύει μόνο με state.
class SmartEntitySelectorNotifier extends Notifier<SmartEntitySelectorState>
    with
        SmartEntitySelectorLookupsMixin,
        SmartEntitySelectorConflictsMixin,
        SmartEntitySelectorAssociationMixin {
  bool _isFillingFromLookup = false;
  int _phoneLookupGeneration = 0;
  static const int _criticalTaskPriority = 2;
  static const int _maxRecentPhones = 20;

  /// v2 §Β: ένα συμπληρωμένο πεδίο εξοπλισμού (isFilled) προστατεύεται και δεν


  /// Έως ένα quick task ανά κύκλο φόρμας· set μόνο μετά επιτυχή insert.
  int? _associationQuickTaskId;

  /// True μετά πράσινο (+) που δημιούργησε καλόντα χωρίς τηλέφωνο — το πρώτο
  /// πληκτρολόγημα τηλεφώνου συμπληρώνει, όχι νέο lookup.
  bool _callerAwaitingPhoneAssociation = false;

  /// Παράγωγες εγγραφές audit πριν το id κλήσης/εκκρεμότητας (καλωδίωση Φάσης 3).
  final PendingAuditOriginRows _pendingAuditOriginRows = PendingAuditOriginRows();

  static const Set<String> _kMainAuditActionsWithoutOrigin = {
    'ΔΗΜΙΟΥΡΓΙΑ ΚΛΗΣΗΣ',
    'ΔΗΜΙΟΥΡΓΙΑ ΕΚΚΡΕΜΟΤΗΤΑΣ',
  };

  Future<int> maxAuditLogId(DatabaseExecutor executor) async {
    final rows = await executor.rawQuery('SELECT MAX(id) AS m FROM audit_log');
    return (rows.first['m'] as int?) ?? 0;
  }

  /// Καταγράφει νέες παράγωγες εγγραφές audit μετά από associate (όχι κύριες κλήσης/εκκρεμότητας).
  Future<void> trackDerivativeAuditsSince(int sinceId) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'audit_log',
      columns: ['id', 'action'],
      where: 'id > ?',
      whereArgs: [sinceId],
    );
    for (final row in rows) {
      final action = (row['action'] as String?)?.trim() ?? '';
      if (_kMainAuditActionsWithoutOrigin.contains(action)) continue;
      _pendingAuditOriginRows.track(row['id'] as int?);
    }
  }

  /// Εφαρμόζει «από κλήση #N» στις εκκρεμείς παράγωγες εγγραφές (μέσα σε transaction submit).
  Future<void> stampPendingAuditOriginsForCall(
    DatabaseExecutor txn,
    int callId,
  ) async {
    if (_pendingAuditOriginRows.isEmpty) return;
    await _pendingAuditOriginRows.applyOriginSuffix(
      txn,
      DirectorySupport.auditOriginSuffixFromCall(callId),
    );
  }

  /// Εφαρμόζει «από εκκρεμότητα #N» στις εκκρεμείς παράγωγες εγγραφές.
  Future<void> stampPendingAuditOriginsForTask(
    DatabaseExecutor txn,
    int taskId,
  ) async {
    if (_pendingAuditOriginRows.isEmpty) return;
    await _pendingAuditOriginRows.applyOriginSuffix(
      txn,
      DirectorySupport.auditOriginSuffixFromTask(taskId),
    );
  }

  void clearPendingAuditOrigins() => _pendingAuditOriginRows.clear();

  bool _computeHasAnyContent({
    String? phoneText,
    String? callerText,
    String? equipmentText,
    String? departmentText,
  }) {
    final phone =
        phoneText?.trim().isNotEmpty ??
        state.selectedPhone?.trim().isNotEmpty ??
        false;
    final caller =
        callerText?.trim().isNotEmpty ??
        state.callerDisplayText.trim().isNotEmpty;
    final equipment =
        equipmentText?.trim().isNotEmpty ??
        state.equipmentText.trim().isNotEmpty;
    final department =
        departmentText?.trim().isNotEmpty ??
        state.departmentText.trim().isNotEmpty;
    return phone ||
        caller ||
        equipment ||
        department ||
        state.selectedCaller != null ||
        state.selectedEquipment != null ||
        state.callerCandidates.isNotEmpty ||
        state.equipmentCandidates.isNotEmpty;
  }

  /// Κλήση μετά από Enter ή focus out· ενημερώνει hasAnyContent για εμφάνιση κουμπιού "Καθαρισμός όλων"
  /// και αποθηκεύει το equipmentText/departmentText. Το UI περνάει τις τρέχουσες τιμές πεδίων.
  /// Κρατά υπάρχουσα τιμή state όταν το UI περνάει κενό πεδίο πριν συγχρονιστεί με provider.
  static String _mergeTextFieldIntoState(String? fieldValue, String stateValue) {
    if (fieldValue == null) return stateValue;
    if (fieldValue.isEmpty && stateValue.trim().isNotEmpty) return stateValue;
    return fieldValue;
  }

  void checkContent({
    String? phoneText,
    String? callerText,
    String? equipmentText,
    String? departmentText,
  }) {
    final mergedEquipment = equipmentText != null
        ? _mergeTextFieldIntoState(equipmentText.trim(), state.equipmentText)
        : state.equipmentText;
    final mergedDepartment = _mergeTextFieldIntoState(
      departmentText,
      state.departmentText,
    );
    // v2 §Ζ.3: αν αλλάζει το πεδίο εξοπλισμού κατά την πληκτρολόγηση, καθαρίζουμε
    // τους ✱ μέχρι το επόμενο commit/lookup.
    final clearConflictsOnEdit = equipmentText != null;
    state = state.copyWith(
      hasAnyContent: _computeHasAnyContent(
        phoneText: phoneText,
        callerText: callerText,
        equipmentText: equipmentText,
        departmentText: departmentText,
      ),
      equipmentText: mergedEquipment,
      // Στο departmentText κρατάμε το ακριβές input του χρήστη (με κενά),
      // ώστε να μην αφαιρούνται αυτόματα τα διαστήματα πληκτρολόγησης.
      departmentText: mergedDepartment,
      clearConflicts: clearConflictsOnEdit,
    );
  }

  @override
  SmartEntitySelectorState build() {
    return SmartEntitySelectorState();
  }

  /// Φόρτωση πεδίων επιλογέα από υπάρχον `Task` (λειτουργία επεξεργασίας).
  Future<void> loadFromTask(Task task) async {
    final lookupBundle = await ref.read(lookupServiceProvider.future);
    if (!ref.mounted) return;
    final lookupService = lookupBundle.service;
    final user = task.callerId != null
        ? lookupService.findUserById(task.callerId)
        : null;

    final phoneRaw = task.phoneText?.trim();
    final phoneValue = phoneRaw != null && phoneRaw.isNotEmpty
        ? phoneRaw
        : null;

    final trimmedUserText = (task.userText ?? '').trim();
    final nameTrim = (user?.name ?? '').trim();
    final callerDisplayText = trimmedUserText.isNotEmpty
        ? trimmedUserText
        : nameTrim;

    final hasAnyContent =
        user != null ||
        phoneValue != null ||
        trimmedUserText.isNotEmpty ||
        (task.departmentText?.trim().isNotEmpty ?? false) ||
        (task.equipmentText?.trim().isNotEmpty ?? false);

    state = state.copyWith(
      selectedCaller: user,
      clearSelectedCaller: user == null,
      selectedPhone: phoneValue,
      clearSelectedPhone: phoneValue == null,
      callerDisplayText: callerDisplayText,
      departmentText: task.departmentText ?? '',
      equipmentText: task.equipmentText ?? '',
      hasAnyContent: hasAnyContent,
      clearPhoneCandidates: true,
      clearCallerCandidates: true,
      clearEquipmentCandidates: true,
      isPhoneAmbiguous: false,
      isEquipmentAmbiguous: false,
      callerNoMatch: false,
      equipmentNoMatch: false,
    );
  }

  /// Φόρτωση πεδίων επιλογέα από υπάρχουσα `CallModel` (λειτουργία επεξεργασίας ιστορικού).
  ///
  /// Ακολουθεί το ίδιο pattern με `loadFromTask`: μόνο in-memory lookup cache και
  /// fallback σε snapshot κειμένων της κλήσης όταν οι συσχετισμένες οντότητες
  /// λείπουν ή είναι soft-deleted.
  Future<void> loadFromCall(CallModel call) async {
    final lookupBundle = await ref.read(lookupServiceProvider.future);
    if (!ref.mounted) return;
    final lookupService = lookupBundle.service;

    final user = call.callerId != null
        ? lookupService.findUserById(call.callerId)
        : null;

    final equipmentTextTrimmed = (call.equipmentText ?? '').trim();
    final equipment = equipmentTextTrimmed.isEmpty
        ? null
        : lookupService.findEquipmentsByCode(equipmentTextTrimmed).firstOrNull;

    final phoneRaw = call.phoneText?.trim();
    final phoneValue = phoneRaw != null && phoneRaw.isNotEmpty
        ? phoneRaw
        : null;

    final snapshotCaller = (call.callerText ?? '').trim();
    final callerDisplayText = snapshotCaller.isNotEmpty
        ? snapshotCaller
        : (user?.name ?? user?.fullNameWithDepartment ?? '').trim();

    final hasAnyContent =
        user != null ||
        equipment != null ||
        phoneValue != null ||
        snapshotCaller.isNotEmpty ||
        (call.departmentText?.trim().isNotEmpty ?? false) ||
        equipmentTextTrimmed.isNotEmpty;

    state = state.copyWith(
      selectedCaller: user,
      clearSelectedCaller: user == null,
      selectedEquipment: equipment,
      clearSelectedEquipment: equipment == null,
      selectedPhone: phoneValue,
      clearSelectedPhone: phoneValue == null,
      callerDisplayText: callerDisplayText,
      departmentText: call.departmentText ?? '',
      equipmentText: call.equipmentText ?? '',
      hasAnyContent: hasAnyContent,
      clearPhoneCandidates: true,
      clearCallerCandidates: true,
      clearEquipmentCandidates: true,
      isPhoneAmbiguous: false,
      isEquipmentAmbiguous: false,
      callerNoMatch: false,
      equipmentNoMatch: false,
    );
  }

  void updatePhone(String? value) {
    if (value == state.selectedPhone && state.selectedCaller != null) return;
    if (_isFillingFromLookup) {
      state = state.copyWith(
        selectedPhone: value,
        clearSelectedPhone: value == null,
        clearPhoneError: true,
        clearPhoneCandidates: true,
      );
      return;
    }
    // Πρώτο τηλέφωνο μετά πράσινο (+) χωρίς τηλέφωνο: συμπλήρωση συσχέτισης.
    final committedCallerId = state.selectedCaller?.id;
    final phoneFieldWasEmpty =
        state.selectedPhone == null || state.selectedPhone!.trim().isEmpty;
    if (committedCallerId != null &&
        _callerAwaitingPhoneAssociation &&
        phoneFieldWasEmpty &&
        value != null &&
        value.trim().isNotEmpty) {
      state = state.copyWith(
        selectedPhone: value,
        clearSelectedPhone: false,
        clearPhoneError: true,
        clearPhoneCandidates: true,
        isPhoneAmbiguous: false,
        clearConflicts: true,
      );
      _callerAwaitingPhoneAssociation = false;
      return;
    }
    final preserveEquipment = _hasManualEquipmentSelection;
    state = state.copyWith(
      selectedPhone: value,
      clearSelectedPhone: value == null,
      clearPhoneError: true,
      clearPhoneCandidates: true,
    );
    // v2 §Ζ.3: κατά την πληκτρολόγηση τηλεφώνου καθαρίζονται οι ✱ μέχρι το
    // επόμενο commit/lookup.
    if (value == null || value.trim().isEmpty) {
      state = state.copyWith(
        clearCallerCandidates: true,
        clearSelectedCaller: true,
        clearEquipmentCandidates: true,
        clearSelectedEquipment: !preserveEquipment,
        isPhoneAmbiguous: false,
        isEquipmentAmbiguous: false,
        callerNoMatch: false,
        equipmentNoMatch: false,
        clearConflicts: true,
      );
      final lookupForRestore =
          ref.read(lookupServiceProvider).value?.service;
      _restoreDepartmentPhoneCandidatesIfNeeded(lookupForRestore);
      if (!preserveEquipment) {
        _restoreDepartmentEquipmentCandidatesIfNeeded(lookupForRestore);
      }
    } else {
      state = state.copyWith(
        clearCallerCandidates: true,
        clearSelectedCaller: true,
        clearEquipmentCandidates: true,
        clearSelectedEquipment: !preserveEquipment,
        isPhoneAmbiguous: false,
        isEquipmentAmbiguous: false,
        callerNoMatch: false,
        equipmentNoMatch: false,
        clearConflicts: true,
      );
    }
  }

  /// Ρητή επιλογή τηλεφώνου από λίστα προτάσεων (Autocomplete/Search).
  /// Δεν κάνει destructive reset caller/equipment και κρατά ως source την επιλογή λίστας.
  void setPhone(String phone) {
    final trimmed = phone.trim();
    if (trimmed.isEmpty) {
      updatePhone(null);
      return;
    }
    state = state.copyWith(
      selectedPhone: trimmed,
      clearSelectedPhone: false,
      clearPhoneError: true,
      clearPhoneCandidates: true,
      isPhoneAmbiguous: false,
    );
  }

  List<String> _recentPhonesWithPhoneBumped(String trimmed) {
    final list = List<String>.from(state.recentPhones);
    list.remove(trimmed);
    list.insert(0, trimmed);
    if (list.length > _maxRecentPhones) {
      list.length = _maxRecentPhones;
    }
    return list;
  }

  /// Επιλογή τηλεφώνου από τη λίστα `phoneCandidates` (ήδη γνωστός καλούντας).
  /// Δεν καθαρίζει context καλούντα / εξοπλισμού.
  void selectPhoneFromCandidates(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    state = state.copyWith(
      selectedPhone: trimmed,
      clearSelectedPhone: false,
      clearPhoneError: true,
      clearPhoneCandidates: true,
      isPhoneAmbiguous: false,
      recentPhones: _recentPhonesWithPhoneBumped(trimmed),
    );

    final callerId = state.selectedCaller?.id;
    final canAutofillEquipment = state.equipmentText.trim().isEmpty;
    if (callerId != null && canAutofillEquipment) {
      performEquipmentLookup(callerId);
    }
    _recomputeConflicts(
      SelectorField.phone,
      ref.read(lookupServiceProvider).value?.service,
    );
  }

  void clearPhone() {
    _resetAssociationQuickTaskCycle();
    state = state.copyWithClearSelections();
  }

  /// Μηδενίζει selectedPhone, selectedCaller, selectedEquipment, phoneError, candidates.
  /// Ο καθαρισμός των πεδίων κειμένου γίνεται από το UI.
  void clearAll() {
    _resetAssociationQuickTaskCycle();
    state = state.copyWithClearSelections();
  }

  /// Μηδενίζει μόνο τις λίστες candidates και τα ambiguous flags (όχι τα επιλεγμένα πεδία).
  void clearAllCandidates() {
    state = state.copyWith(
      clearPhoneCandidates: true,
      clearCallerCandidates: true,
      clearEquipmentCandidates: true,
      isPhoneAmbiguous: false,
      isEquipmentAmbiguous: false,
      callerNoMatch: false,
      equipmentNoMatch: false,
    );
  }

  void clearPhoneCandidates() {
    state = state.copyWith(clearPhoneCandidates: true, isPhoneAmbiguous: false);
  }

  void setCaller(UserModel? value) {
    final departmentAlreadyFilled = state.departmentText.trim().isNotEmpty;
    final shouldAutofillDepartment = !departmentAlreadyFilled && value != null;

    if (shouldAutofillDepartment) {
      final deptText = _departmentTextForUser(value);
      state = state.copyWith(
        selectedCaller: value,
        clearPhoneCandidates: true,
        clearCallerCandidates: true,
        isPhoneAmbiguous: false,
        callerNoMatch: false,
        callerDisplayText: value.name ?? value.fullNameWithDepartment,
        departmentText: deptText,
        selectedDepartmentId: value.departmentId,
      );
    } else {
      state = state.copyWith(
        selectedCaller: value,
        clearSelectedCaller: value == null,
        clearPhoneCandidates: true,
        clearCallerCandidates: true,
        isPhoneAmbiguous: false,
        callerNoMatch: false,
        callerDisplayText: value?.name ?? value?.fullNameWithDepartment ?? '',
      );
    }
    if (value != null) {
      final pool = value.phoneJoined.trim();
      final sp = state.selectedPhone?.trim() ?? '';
      if (pool.isNotEmpty &&
          sp.isNotEmpty &&
          sp == pool &&
          _splitPhones(sp).length > 1) {
        state = state.copyWith(clearSelectedPhone: true, clearPhoneError: true);
      }
      _recomputeConflicts(
        SelectorField.caller,
        ref.read(lookupServiceProvider).value?.service,
      );
    }
  }

  void updateSelectedCaller(UserModel? value) {
    setCaller(value);
  }

  void updateCallerDisplayText(String text) {
    // v2 §Ζ.3: κατά την πληκτρολόγηση δεν εμφανίζονται ✱· καθαρίζονται μέχρι
    // το επόμενο commit/lookup.
    state = state.copyWith(callerDisplayText: text, clearConflicts: true);
  }

  void clearCaller() {
    state = state.copyWith(
      clearSelectedCaller: true,
      clearPhoneCandidates: true,
      clearCallerCandidates: true,
      isPhoneAmbiguous: false,
      callerDisplayText: '',
      clearConflicts: true,
    );
  }

  void updateDepartmentText(String text) {
    final trimmed = text.trim();
    int? matchedDepartmentId;
    if (trimmed.isNotEmpty) {
      final lookup = ref.read(lookupServiceProvider).value?.service;
      if (lookup != null) {
        final normalized = SearchTextNormalizer.normalizeForSearch(trimmed);
        for (final dep in lookup.departments) {
          if (SearchTextNormalizer.normalizeForSearch(dep.name) == normalized) {
            matchedDepartmentId = dep.id;
            break;
          }
        }
      }
    }
    // Όταν το κείμενο δεν ταιριάζει σε γνωστό τμήμα, μηδενίζουμε το id·
    // αλλιώς μένει stale id (π.χ. από autofill) και το hasPendingDepartmentChange
    // συγκρίνει λάθος μόνο ids → κρύβεται το «Προσθήκη».
    final clearDeptId = trimmed.isEmpty || matchedDepartmentId == null;
    final hasPhoneInput = state.selectedPhone?.trim().isNotEmpty == true;
    final hasEquipmentInput = state.equipmentText.trim().isNotEmpty;
    final hasCallerInput =
        state.callerDisplayText.trim().isNotEmpty ||
        state.selectedCaller != null;

    state = state.copyWith(
      // Αποθηκεύουμε το raw κείμενο (με κενά) ώστε ο χρήστης να βλέπει
      // ακριβώς αυτό που πληκτρολόγησε. Το trimming χρησιμοποιείται μόνο
      // για matching/clearSelectedDepartmentId.
      departmentText: text,
      selectedDepartmentId: matchedDepartmentId,
      clearSelectedDepartmentId: clearDeptId,
      clearConflicts: true,
      clearPhoneCandidates: clearDeptId && !hasPhoneInput,
      clearEquipmentCandidates: clearDeptId && !hasEquipmentInput,
      clearCallerCandidates: clearDeptId && !hasCallerInput,
      isPhoneAmbiguous: clearDeptId && !hasPhoneInput
          ? false
          : state.isPhoneAmbiguous,
      isEquipmentAmbiguous: clearDeptId && !hasEquipmentInput
          ? false
          : state.isEquipmentAmbiguous,
      hasAnyContent: _computeHasAnyContent(departmentText: text),
    );
  }

  void selectDepartment(DepartmentModel dept) {
    final departmentId = dept.id;
    if (departmentId == null) {
      updateDepartmentText(dept.name);
      return;
    }
    final asyncLookup = ref.read(lookupServiceProvider);
    final lookup = asyncLookup.value?.service;

    List<UserModel>? callerCandidates;
    List<EquipmentModel>? equipmentCandidates;
    List<String>? phoneCandidates;
    final hasCallerInput = state.callerDisplayText.trim().isNotEmpty;
    final keepCallerUntouched = hasCallerInput || state.selectedCaller != null;
    final hasPhoneInput = state.selectedPhone?.trim().isNotEmpty == true;
    final hasEquipmentInput = state.equipmentText.trim().isNotEmpty;

    if (lookup != null) {
      // Αν ο καλών είναι ήδη ορισμένος/ορατός, δεν τον πειράζουμε στην αλλαγή τμήματος.
      // Prefill λίστας caller μόνο όταν το πεδίο είναι πραγματικά κενό.
      if (!keepCallerUntouched) {
        callerCandidates = lookup.getUsersByDepartment(departmentId);
      }
      if (!hasEquipmentInput) {
        equipmentCandidates = lookup.getAllEquipmentByDepartment(departmentId);
      }
      if (!hasPhoneInput) {
        phoneCandidates = lookup.getPhonesByDepartment(departmentId);
      }
    }

    state = state.copyWith(
      departmentText: dept.name,
      selectedDepartmentId: departmentId,
      clearSelectedCaller: !keepCallerUntouched,
      callerDisplayText: keepCallerUntouched ? state.callerDisplayText : '',
      callerCandidates: keepCallerUntouched
          ? state.callerCandidates
          : (callerCandidates ?? state.callerCandidates),
      equipmentCandidates: equipmentCandidates ?? state.equipmentCandidates,
      phoneCandidates: phoneCandidates ?? state.phoneCandidates,
      callerNoMatch: false,
      equipmentNoMatch: false,
      isPhoneAmbiguous: false,
      isEquipmentAmbiguous: false,
    );
    _recomputeConflicts(SelectorField.department, lookup);
  }

  void setEquipment(EquipmentModel? value) {
    final text = value == null
        ? ''
        : (value.code?.trim().isNotEmpty == true
              ? value.code!.trim()
              : value.displayLabel.trim());
    state = state.copyWith(
      selectedEquipment: value,
      clearSelectedEquipment: value == null,
      equipmentText: text,
      clearEquipmentCandidates: true,
      isEquipmentAmbiguous: false,
      equipmentNoMatch: false,
    );
  }

  void clearEquipment() {
    state = state.copyWith(
      clearSelectedEquipment: true,
      clearEquipmentCandidates: true,
      isEquipmentAmbiguous: false,
      equipmentNoMatch: false,
      equipmentText: '',
      hasAnyContent: _computeHasAnyContent(equipmentText: ''),
      clearConflicts: true,
    );
    final lookupForRestore = ref.read(lookupServiceProvider).value?.service;
    _restoreDepartmentEquipmentCandidatesIfNeeded(lookupForRestore);
    if (state.selectedPhone?.trim().isEmpty ?? true) {
      _restoreDepartmentPhoneCandidatesIfNeeded(lookupForRestore);
    }
  }

  void setPhoneError(String? message) {
    state = state.copyWith(
      phoneError: message,
      clearPhoneError: message == null,
    );
  }

  void clearPhoneError() {
    state = state.copyWith(clearPhoneError: true);
  }

  void markPhoneUsed(String phone) {
    final trimmed = phone.trim();
    if (trimmed.isEmpty) return;
    state = state.copyWith(recentPhones: _recentPhonesWithPhoneBumped(trimmed));
  }

  void clearAfterSubmit() {
    _resetAssociationQuickTaskCycle();
    state = state.copyWithClearSelections();
  }

  /// Ανανεώνει το [selectedEquipment] από τον τρέχοντα κατάλογο lookup
  /// (μετά αποθήκευση εξοπλισμού). Αν το [equipmentText] ταυτίζεται με τον
  /// παλιό κωδικό και ο κωδικός άλλαξε, συγχρονίζεται και το κείμενο πεδίου.
  /// Ενημερώνει επίσης μπαγιάτικα αντίγραφα στο [equipmentCandidates].
  Future<void> refreshSelectedEquipmentFromLookup() async {
    final current = state.selectedEquipment;
    final id = current?.id;
    if (id == null) return;
    final bundle = await ref.read(lookupServiceProvider.future);
    if (!ref.mounted) return;
    final fresh = bundle.service.findEquipmentById(id);
    if (fresh == null) return;

    final oldCode = current!.code?.trim() ?? '';
    final newCode = fresh.code?.trim() ?? '';
    final trimmedText = state.equipmentText.trim();
    String? syncedEquipmentText;
    if (oldCode.isNotEmpty &&
        newCode.isNotEmpty &&
        oldCode != newCode &&
        trimmedText == oldCode) {
      syncedEquipmentText = newCode;
    }

    List<EquipmentModel>? refreshedCandidates;
    if (state.equipmentCandidates.any((e) => e.id == id)) {
      refreshedCandidates = state.equipmentCandidates
          .map((e) => e.id == id ? fresh : e)
          .toList();
    }

    state = state.copyWith(
      selectedEquipment: fresh,
      equipmentText: syncedEquipmentText ?? state.equipmentText,
      equipmentCandidates: refreshedCandidates ?? state.equipmentCandidates,
    );
  }
}

/// Κατάσταση έξυπνου επιλογέα για τη φόρμα **Κλήσεων** (ξεχωριστό instance από Tasks).
final callSmartEntityProvider =
    NotifierProvider<SmartEntitySelectorNotifier, SmartEntitySelectorState>(
      SmartEntitySelectorNotifier.new,
    );

/// Κατάσταση έξυπνου επιλογέα για φόρμες **Εκκρεμοτήτων** / άλλες οθόνες.
final taskSmartEntityProvider =
    NotifierProvider<SmartEntitySelectorNotifier, SmartEntitySelectorState>(
      SmartEntitySelectorNotifier.new,
    );

/// Κατάσταση έξυπνου επιλογέα για dialog επεξεργασίας από Ιστορικό κλήσεων.
final historyEditSmartEntityProvider =
    NotifierProvider<SmartEntitySelectorNotifier, SmartEntitySelectorState>(
      SmartEntitySelectorNotifier.new,
    );

/// Ανανεώνει το `selectedEquipment` σε όλους τους ενεργούς επιλογείς (κλήση,
/// εκκρεμότητα, επεξεργασία ιστορικού) μετά από invalidate του lookup.
Future<void> refreshSelectedEquipmentInAllSelectors(WidgetRef ref) async {
  await ref
      .read(callSmartEntityProvider.notifier)
      .refreshSelectedEquipmentFromLookup();
  await ref
      .read(taskSmartEntityProvider.notifier)
      .refreshSelectedEquipmentFromLookup();
  await ref
      .read(historyEditSmartEntityProvider.notifier)
      .refreshSelectedEquipmentFromLookup();
}
