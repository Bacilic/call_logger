import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/calls_repository.dart';
import '../../../core/database/sqlite_types.dart';
import '../../../core/errors/call_save_exception.dart';
import '../../../core/errors/task_save_exception.dart';
import '../../../core/database/database_helper.dart';
import '../../tasks/models/task_filter.dart';
import '../../tasks/providers/task_service_provider.dart';
import '../../tasks/providers/tasks_provider.dart';
import '../models/call_model.dart';
import '../models/equipment_model.dart';
import '../models/user_model.dart';
import 'call_header_provider.dart';
import 'call_mutation_refresh.dart';

/// Κατάσταση φόρμας εισαγωγής κλήσης.
class CallEntryState {
  CallEntryState({
    this.internalDigits = '',
    this.selectedUser,
    this.selectedEquipment,
    this.notes = '',
    this.category = '',
    this.categoryId,
    this.isPending = false,
    this.durationSeconds = 0,
    this.isCallTimerRunning = false,
    this.retainPlayPauseAfterManualZero = false,
    this.isSubmitting = false,
  });

  final String internalDigits;
  final UserModel? selectedUser;
  final EquipmentModel? selectedEquipment;
  final String notes;
  final String category;
  final int? categoryId;
  final bool isPending;
  final int durationSeconds;

  /// Συγχρονισμένο με το ενεργό `Timer` — για `ref.watch(select(...))` όταν η διάρκεια δεν αλλάζει (παύση).
  final bool isCallTimerRunning;

  /// Όταν η διάρκεια μηδενίστηκε από τον διάλογο προσαρμογής, κρατά ορατό το Play/Pause στο `CallStatusBar`.
  final bool retainPlayPauseAfterManualZero;

  /// Αποτρέπει διπλή υποβολή κατά async αποθήκευση.
  final bool isSubmitting;

  CallEntryState copyWith({
    String? internalDigits,
    UserModel? selectedUser,
    EquipmentModel? selectedEquipment,
    String? notes,
    String? category,
    int? categoryId,
    bool? isPending,
    int? durationSeconds,
    bool? isCallTimerRunning,
    bool? retainPlayPauseAfterManualZero,
    bool? isSubmitting,
  }) {
    return CallEntryState(
      internalDigits: internalDigits ?? this.internalDigits,
      selectedUser: selectedUser ?? this.selectedUser,
      selectedEquipment: selectedEquipment ?? this.selectedEquipment,
      notes: notes ?? this.notes,
      category: category ?? this.category,
      categoryId: categoryId ?? this.categoryId,
      isPending: isPending ?? this.isPending,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      isCallTimerRunning: isCallTimerRunning ?? this.isCallTimerRunning,
      retainPlayPauseAfterManualZero:
          retainPlayPauseAfterManualZero ?? this.retainPlayPauseAfterManualZero,
      isSubmitting: isSubmitting ?? this.isSubmitting,
    );
  }
}

/// Notifier για τη φόρμα εισαγωγής κλήσης (FocusNode, submit, reset).
class CallEntryNotifier extends Notifier<CallEntryState> {
  Timer? _timer;

  bool get isTimerRunning => _timer?.isActive ?? false;

  @override
  CallEntryState build() {
    ref.onDispose(() {
      // Μόνο ακύρωση timer — όχι αλλαγή state (Riverpod 3: απαγορεύεται μέσα σε dispose).
      _timer?.cancel();
      _timer = null;
    });
    // Timer και durationSeconds αρχικοποιούνται μόνο μέσω startTimerOnce() από το UI (focus loss / Enter).
    return CallEntryState();
  }

  void togglePending() {
    state = state.copyWith(isPending: !state.isPending);
  }

  void startTimerOnce() {
    if (_timer != null) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!ref.mounted) return;
      final next = state.durationSeconds + 1;
      state = state.copyWith(
        durationSeconds: next,
        retainPlayPauseAfterManualZero: next > 0
            ? false
            : state.retainPlayPauseAfterManualZero,
      );
    });
    state = state.copyWith(
      durationSeconds: state.durationSeconds,
      isCallTimerRunning: true,
    );
  }

  void stopTimer() {
    _timer?.cancel();
    _timer = null;
    state = state.copyWith(
      durationSeconds: state.durationSeconds,
      isCallTimerRunning: false,
    );
  }

  void setDurationManually(
    int seconds, {
    bool retainPlayPauseAfterManualZero = false,
  }) {
    stopTimer();
    state = state.copyWith(
      durationSeconds: seconds,
      retainPlayPauseAfterManualZero:
          seconds == 0 && retainPlayPauseAfterManualZero,
    );
  }

  /// Επαναφορά χρονομέτρου σε αναμονή (stop + duration 0) όταν το πεδίο τηλεφώνου γίνεται κενό.
  void resetTimerToStandby() {
    stopTimer();
    state = state.copyWith(
      durationSeconds: 0,
      retainPlayPauseAfterManualZero: false,
    );
  }

  void setNotes(String value) {
    final notesEmpty = value.trim().isEmpty;
    state = state.copyWith(
      notes: value,
      // Χωρίς σημειώσεις δεν νοείται εκκρεμότητα (το checkbox γίνεται ανενεργό·
      // αποφεύγουμε «κολλημένο» true μετά από εκκαθάριση πεδίου).
      isPending: notesEmpty ? false : state.isPending,
    );
  }

  void setCategory(String value, {int? categoryId}) {
    state = state.copyWith(category: value, categoryId: categoryId);
  }

  String? _equipmentCodeForRecentInvalidation({
    required dynamic header,
  }) {
    final fromModel = header.selectedEquipment?.code?.trim();
    if (fromModel != null && fromModel.isNotEmpty) return fromModel;
    final fromText = header.equipmentText?.trim();
    if (fromText != null && fromText.isNotEmpty) return fromText;
    return null;
  }

  /// Υποβολή κλήσης: διαβάζει caller/equipment από call_header_provider.
  ///
  /// CONTRACT (μην αλλοιωθεί):
  /// - Η submit ροή ΠΟΤΕ δεν δημιουργεί/ενημερώνει οντότητες καταλόγου (users/phones/equipment/departments).
  /// - Γράφει μόνο ιστορικό κλήσης στον πίνακα `calls` (και προαιρετικά task όταν είναι pending).
  /// - Αν δεν υπάρχει FK οντότητα, κρατά snapshot στα text πεδία (`caller_text`, `phone_text`, κ.λπ.).
  ///
  /// Η δημιουργία/συσχέτιση οντοτήτων επιτρέπεται αποκλειστικά από τη ροή του κουμπιού `+`
  /// μέσω `associateCurrentIfNeeded()` στον smart entity selector provider.
  ///
  /// Μετά επιτυχία: markPhoneUsed, reset notes, clearAll (focus τηλεφώνου: UI / SmartEntitySelectorWidget).
  ///
  /// Χρησιμοποιεί το [Notifier.ref] (όχι εξωτερικό [WidgetRef]) ώστε το async να ολοκληρώνεται
  /// αξιόπιστα και στα widget tests όπου το callback του κουμπιού δεν «δένεται» πάντα με await.
  Future<bool> submitCall() async {
    if (state.isSubmitting) return false;
    if (!ref.read(callHeaderProvider).canSubmitCall) {
      return false;
    }
    final header = ref.read(callHeaderProvider);
    final user = header.selectedCaller;
    final notes = state.notes.trim();
    final callerId = header.selectedCaller?.id;
    final callerTextRaw = header.callerDisplayText.trim();
    final callerText = callerId != null
        ? null
        : (callerTextRaw.isEmpty ? 'Άγνωστος' : callerTextRaw);
    final createsPendingTask = state.isPending && notes.isNotEmpty;

    state = state.copyWith(isSubmitting: true);
    try {
      stopTimer();
      final callModel = CallModel(
        date: null,
        time: null,
        callerId: callerId ?? user?.id,
        equipmentId: header.selectedEquipment?.id,
        callerText: callerText,
        phoneText: () {
          final phone = header.selectedPhone;
          if (phone == null) return null;
          final trimmedPhone = phone.trim();
          return trimmedPhone.isEmpty ? null : trimmedPhone;
        }(),
        departmentText: header.departmentText.trim().isEmpty
            ? null
            : header.departmentText.trim(),
        equipmentText: header.equipmentText.trim().isEmpty
            ? null
            : header.equipmentText.trim(),
        issue: notes.isEmpty ? null : notes,
        category: state.category.isEmpty ? null : state.category,
        categoryId: state.categoryId,
        status: createsPendingTask ? 'pending' : 'completed',
        duration: state.durationSeconds,
      );

      final taskService = ref.read(taskServiceProvider);
      Map<String, dynamic>? pendingTaskRow;
      if (createsPendingTask) {
        final callerName =
            user?.name ??
            (callerTextRaw.trim().isEmpty ? null : callerTextRaw.trim());
        final taskFields = callsFormPendingTaskFields(
          ref,
          internalDigits: state.internalDigits,
        );
        final categoryName = state.category.trim().isEmpty
            ? null
            : state.category.trim();
        pendingTaskRow = await taskService.buildCreateFromCallRow(
          callId: null,
          callerName: callerName,
          description: state.notes,
          callDate: DateTime.now(),
          callerId: taskFields.callerId,
          equipmentId: taskFields.equipmentId,
          departmentId: taskFields.departmentId,
          phoneId: taskFields.phoneId,
          phoneText: taskFields.phoneText,
          userText: taskFields.userText,
          equipmentText: taskFields.equipmentText,
          departmentText: taskFields.departmentText,
          categoryName: categoryName,
        );
      }

      final db = await DatabaseHelper.instance.database;
      final callsRepo = CallsRepository(db);
      await db.transaction((DatabaseExecutor txn) async {
        final id = await callsRepo.insertCallOnExecutor(txn, callModel);
        if (pendingTaskRow != null) {
          pendingTaskRow['call_id'] = id;
          await taskService.createFromCallOnExecutor(txn, row: pendingTaskRow);
        }
      });

      final userId = user?.id;
      refreshAfterCallMutation(
        ref,
        callerId: userId,
        equipmentCode: _equipmentCodeForRecentInvalidation(header: header),
      );
      if (createsPendingTask) {
        ref
            .read(taskFilterProvider.notifier)
            .update((_) => TaskFilter.initial());
        invalidateTaskListProviders(ref);
      }
      final selectedPhone = header.selectedPhone;
      if (selectedPhone != null) {
        ref.read(callHeaderProvider.notifier).markPhoneUsed(selectedPhone);
      }
      reset();
      ref.read(callHeaderProvider.notifier).clearAll();
      return true;
    } on CallSaveException {
      rethrow;
    } on TaskSaveException {
      rethrow;
    } catch (e, st) {
      developer.log(
        'submitCall failed',
        name: 'CallEntryNotifier',
        error: e,
        stackTrace: st,
      );
      return false;
    } finally {
      if (ref.mounted) {
        state = state.copyWith(isSubmitting: false);
      }
    }
  }

  /// Καταχώρηση μόνο εκκρεμότητας (task) χωρίς εισαγωγή κλήσης.
  ///
  /// CONTRACT (μην αλλοιωθεί):
  /// - Δεν επιτρέπεται καμία δημιουργία/συσχέτιση οντοτήτων καταλόγου από αυτή τη ροή.
  /// - Η ροή του `+` είναι η μοναδική πύλη για directory mutations.
  Future<bool> submitOnlyPending() async {
    if (state.isSubmitting) return false;
    final header = ref.read(callHeaderProvider);
    final user = header.selectedCaller;
    final callerTextRaw = header.callerDisplayText.trim();
    final callerName =
        user?.name ??
        (callerTextRaw.trim().isEmpty ? null : callerTextRaw.trim());
    final callDate = DateTime.now();

    state = state.copyWith(isSubmitting: true);
    try {
      stopTimer();
      final taskFields = callsFormPendingTaskFields(
        ref,
        internalDigits: state.internalDigits,
      );
      final categoryName = state.category.trim().isEmpty
          ? null
          : state.category.trim();
      await ref
          .read(taskServiceProvider)
          .createFromCall(
            callId: null,
            callerName: callerName,
            description: state.notes,
            callDate: callDate,
            callerId: taskFields.callerId,
            equipmentId: taskFields.equipmentId,
            departmentId: taskFields.departmentId,
            phoneId: taskFields.phoneId,
            phoneText: taskFields.phoneText,
            userText: taskFields.userText,
            equipmentText: taskFields.equipmentText,
            departmentText: taskFields.departmentText,
            categoryName: categoryName,
          );
      ref.read(taskFilterProvider.notifier).update((_) => TaskFilter.initial());
      invalidateTaskListProviders(ref);
      reset();
      ref.read(callHeaderProvider.notifier).clearAll();
      return true;
    } on TaskSaveException {
      rethrow;
    } catch (e, st) {
      developer.log(
        'submitOnlyPending failed',
        name: 'CallEntryNotifier',
        error: e,
        stackTrace: st,
      );
      return false;
    } finally {
      if (ref.mounted) {
        state = state.copyWith(isSubmitting: false);
      }
    }
  }

  /// Επαναφορά όλων των πεδίων της φόρμας κλήσης (χρονόμετρο, πεδία, σημειώσεις, κατηγορία, checkbox).
  void reset() {
    stopTimer();
    state = CallEntryState(
      internalDigits: '',
      selectedUser: null,
      selectedEquipment: null,
      notes: '',
      category: '',
      categoryId: null,
      isPending: false,
      durationSeconds: 0,
      isCallTimerRunning: false,
      retainPlayPauseAfterManualZero: false,
    );
  }
}

final callEntryProvider = NotifierProvider<CallEntryNotifier, CallEntryState>(
  CallEntryNotifier.new,
);

/// Πεδία FK + snapshot κειμένου από τη φόρμα Κλήσεων για εισαγωγή εκκρεμότητας.
({
  int? callerId,
  int? equipmentId,
  int? departmentId,
  int? phoneId,
  String? phoneText,
  String? userText,
  String? equipmentText,
  String? departmentText,
})
callsFormPendingTaskFields(Ref ref, {required String internalDigits}) {
  final smart = ref.read(callSmartEntityProvider);
  final digitsOnly = internalDigits.replaceAll(RegExp(r'[^0-9]'), '');
  final phoneId = digitsOnly.isEmpty ? null : int.tryParse(digitsOnly);
  final phone = smart.selectedPhone?.trim();
  final phoneText = (phone == null || phone.isEmpty) ? null : phone;
  final userTrim = smart.callerDisplayText.trim();
  final userText = userTrim.isEmpty ? null : userTrim;
  final eqTrim = smart.equipmentText.trim();
  final equipmentText = eqTrim.isEmpty ? null : eqTrim;
  final deptTrim = smart.departmentText.trim();
  final departmentText = deptTrim.isEmpty ? null : deptTrim;
  return (
    callerId: smart.selectedCaller?.id,
    equipmentId: smart.selectedEquipment?.id,
    departmentId:
        smart.selectedDepartmentId ?? smart.selectedCaller?.departmentId,
    phoneId: phoneId,
    phoneText: phoneText,
    userText: userText,
    equipmentText: equipmentText,
    departmentText: departmentText,
  );
}
