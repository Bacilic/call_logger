import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/services/lookup_service.dart';
import '../../tasks/models/task_filter.dart';
import '../../tasks/providers/task_service_provider.dart';
import '../../tasks/providers/tasks_provider.dart';
import '../models/call_model.dart';
import '../models/equipment_model.dart';
import '../models/user_model.dart';
import 'call_header_provider.dart';
import 'lookup_provider.dart';

/// Κατάσταση φόρμας εισαγωγής κλήσης.
class CallEntryState {
  CallEntryState({
    this.internalDigits = '',
    this.selectedUser,
    this.selectedEquipment,
    this.notes = '',
    this.category = '',
    this.isPending = false,
    this.durationSeconds = 0,
  });

  final String internalDigits;
  final UserModel? selectedUser;
  final EquipmentModel? selectedEquipment;
  final String notes;
  final String category;
  final bool isPending;
  final int durationSeconds;

  CallEntryState copyWith({
    String? internalDigits,
    UserModel? selectedUser,
    EquipmentModel? selectedEquipment,
    String? notes,
    String? category,
    bool? isPending,
    int? durationSeconds,
  }) {
    return CallEntryState(
      internalDigits: internalDigits ?? this.internalDigits,
      selectedUser: selectedUser ?? this.selectedUser,
      selectedEquipment: selectedEquipment ?? this.selectedEquipment,
      notes: notes ?? this.notes,
      category: category ?? this.category,
      isPending: isPending ?? this.isPending,
      durationSeconds: durationSeconds ?? this.durationSeconds,
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
      state = state.copyWith(durationSeconds: state.durationSeconds + 1);
    });
    state = state.copyWith(durationSeconds: state.durationSeconds);
  }

  void stopTimer() {
    _timer?.cancel();
    _timer = null;
    state = state.copyWith(durationSeconds: state.durationSeconds);
  }

  void setDurationManually(int seconds) {
    stopTimer();
    state = state.copyWith(durationSeconds: seconds);
  }

  /// Επαναφορά χρονομέτρου σε αναμονή (stop + duration 0) όταν το πεδίο τηλεφώνου γίνεται κενό.
  void resetTimerToStandby() {
    stopTimer();
    state = state.copyWith(durationSeconds: 0);
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

  void setCategory(String value) {
    state = state.copyWith(category: value);
  }

  /// Υποβολή κλήσης: διαβάζει caller/equipment από call_header_provider.
  /// Αν τροποποιήθηκε τμήμα σε υπάρχοντα καλούντα, ενημερώνει το department_id πριν την εισαγωγή κλήσης.
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

    final lookupService = ref.read(lookupServiceProvider).value?.service;
    final selectedDepartmentId =
        header.selectedDepartmentId ??
        (header.departmentText.trim().isNotEmpty && lookupService != null
            ? lookupService.findDepartmentByName(header.departmentText)?.id
            : null);
    if (user != null &&
        user.id != null &&
        selectedDepartmentId != null &&
        selectedDepartmentId != user.departmentId) {
      final userId = user.id;
      if (userId == null) return false;
      final updatedMap = Map<String, dynamic>.from(user.toMap());
      updatedMap['department_id'] = selectedDepartmentId;
      await DatabaseHelper.instance.updateUser(userId, updatedMap);
      ref.invalidate(lookupServiceProvider);
    }

    try {
      stopTimer();
      final callId = await DatabaseHelper.instance.insertCall(
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
          status: state.isPending ? 'pending' : 'completed',
          duration: state.durationSeconds,
        ),
      );
      final userId = user?.id;
      if (userId != null) {
        ref.invalidate(recentCallsProvider(userId));
      }
      final selectedPhone = header.selectedPhone;
      if (selectedPhone != null) {
        ref
            .read(callHeaderProvider.notifier)
            .markPhoneUsed(selectedPhone);
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
      isPending: false,
      durationSeconds: 0,
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
callsFormPendingTaskFields(
  Ref ref, {
  required String internalDigits,
}) {
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

/// Τελευταίες κλήσεις ανά caller_id (limit 3).
final recentCallsProvider = FutureProvider.family<List<CallModel>, int>((
  ref,
  callerId,
) async {
  final maps = await DatabaseHelper.instance.getRecentCallsByCallerId(
    callerId,
    limit: 3,
  );
  return maps.map((m) => CallModel.fromMap(m)).toList();
});
