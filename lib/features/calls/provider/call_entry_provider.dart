import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/calls_repository.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/services/lookup_service.dart';
import '../../tasks/models/task_filter.dart';
import '../../tasks/providers/task_service_provider.dart';
import '../../tasks/providers/tasks_provider.dart';
import '../models/call_model.dart';
import '../models/equipment_model.dart';
import '../models/user_model.dart';
import 'call_header_provider.dart';
import 'calls_dashboard_providers.dart';

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

  void setInternalDigits(String value, LookupService? lookupService) {
    final digits = value.trim();
    LookupResult? result;
    if (digits.length >= 3 && lookupService != null) {
      result = lookupService.search(digits);
    }
    state = state.copyWith(
      internalDigits: value,
      selectedUser: result?.user,
      selectedEquipment: result?.equipment.isNotEmpty == true
          ? result!.equipment.first
          : null,
    );
  }

  void setNotes(String value) {
    state = state.copyWith(notes: value);
  }

  void setCategory(String value, {int? categoryId}) {
    state = CallEntryState(
      internalDigits: state.internalDigits,
      selectedUser: state.selectedUser,
      selectedEquipment: state.selectedEquipment,
      notes: state.notes,
      category: value,
      categoryId: categoryId,
      isPending: state.isPending,
      durationSeconds: state.durationSeconds,
      isCallTimerRunning: state.isCallTimerRunning,
      retainPlayPauseAfterManualZero: state.retainPlayPauseAfterManualZero,
    );
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

    try {
      stopTimer();
      final dbCalls = await DatabaseHelper.instance.database;
      final callId = await CallsRepository(dbCalls).insertCall(
        CallModel(
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
          solution: null,
          category: state.category.isEmpty ? null : state.category,
          categoryId: state.categoryId,
          status: state.isPending ? 'pending' : 'completed',
          duration: state.durationSeconds,
        ),
      );
      final userId = user?.id;
      if (userId != null) {
        ref.invalidate(recentCallsProvider(userId));
      }
      final equipmentCode = header.selectedEquipment?.code?.trim();
      if (equipmentCode != null && equipmentCode.isNotEmpty) {
        ref.invalidate(recentCallsByEquipmentProvider(equipmentCode));
      }
      ref.invalidate(globalRecentCallsProvider);
      final selectedPhone = header.selectedPhone;
      if (selectedPhone != null) {
        ref.read(callHeaderProvider.notifier).markPhoneUsed(selectedPhone);
      }
      if (state.isPending) {
        final callerName =
            user?.name ??
            (callerTextRaw.trim().isEmpty ? null : callerTextRaw.trim());
        final callDate = DateTime.now();
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
              callId: callId,
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
        ref
            .read(taskFilterProvider.notifier)
            .update((_) => TaskFilter.initial());
        ref.invalidate(tasksProvider);
      }
      reset();
      ref.read(callHeaderProvider.notifier).clearAll();
      return true;
    } catch (e, st) {
      debugPrint('submitCall error: $e');
      debugPrint('$st');
      return false;
    }
  }

  /// Καταχώρηση μόνο εκκρεμότητας (task) χωρίς εισαγωγή κλήσης.
  ///
  /// CONTRACT (μην αλλοιωθεί):
  /// - Δεν επιτρέπεται καμία δημιουργία/συσχέτιση οντοτήτων καταλόγου από αυτή τη ροή.
  /// - Η ροή του `+` είναι η μοναδική πύλη για directory mutations.
  Future<bool> submitOnlyPending() async {
    final header = ref.read(callHeaderProvider);
    final user = header.selectedCaller;
    final callerTextRaw = header.callerDisplayText.trim();
    final callerName =
        user?.name ??
        (callerTextRaw.trim().isEmpty ? null : callerTextRaw.trim());
    final callDate = DateTime.now();
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
      ref.invalidate(tasksProvider);
      reset();
      ref.read(callHeaderProvider.notifier).clearAll();
      return true;
    } catch (e, st) {
      debugPrint('submitOnlyPending error: $e');
      debugPrint('$st');
      return false;
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
