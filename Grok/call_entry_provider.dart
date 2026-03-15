import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/services/lookup_service.dart';
import '../../tasks/providers/task_service_provider.dart';
import '../../tasks/providers/tasks_provider.dart';
import '../models/call_model.dart';
import '../models/equipment_model.dart';
import '../models/user_model.dart';
import 'call_header_provider.dart';

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
    required this.internalFocusNode,
    required this.internalController,
    required this.notesController,
  });

  final String internalDigits;
  final UserModel? selectedUser;
  final EquipmentModel? selectedEquipment;
  final String notes;
  final String category;
  final bool isPending;
  final int durationSeconds;
  final FocusNode internalFocusNode;
  final TextEditingController internalController;
  final TextEditingController notesController;

  CallEntryState copyWith({
    String? internalDigits,
    UserModel? selectedUser,
    EquipmentModel? selectedEquipment,
    String? notes,
    String? category,
    bool? isPending,
    int? durationSeconds,
    FocusNode? internalFocusNode,
    TextEditingController? internalController,
    TextEditingController? notesController,
  }) {
    return CallEntryState(
      internalDigits: internalDigits ?? this.internalDigits,
      selectedUser: selectedUser ?? this.selectedUser,
      selectedEquipment: selectedEquipment ?? this.selectedEquipment,
      notes: notes ?? this.notes,
      category: category ?? this.category,
      isPending: isPending ?? this.isPending,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      internalFocusNode: internalFocusNode ?? this.internalFocusNode,
      internalController: internalController ?? this.internalController,
      notesController: notesController ?? this.notesController,
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
      stopTimer();
    });
    // Timer και durationSeconds αρχικοποιούνται μόνο μέσω startTimerOnce() από το UI (focus loss / Enter).
    return CallEntryState(
      internalFocusNode: FocusNode(),
      internalController: TextEditingController(),
      notesController: TextEditingController(),
    );
  }

  void togglePending() {
    state = state.copyWith(isPending: !state.isPending);
  }

  void startTimerOnce() {
    if (_timer != null) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
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
    debugPrint('[setInternalDigits] value="$value" digits="$digits" length=${digits.length}');
    LookupResult? result;
    if (digits.length >= 3 && lookupService != null) {
      result = lookupService.search(digits);
      debugPrint('[setInternalDigits] lookup result: user=${result?.user.name}');
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
  /// Μετά επιτυχία: markPhoneUsed, reset notes, clearAll + requestPhoneFocus.
  Future<bool> submitCall(WidgetRef ref) async {
    if (!ref.read(callHeaderProvider).canSubmitCall) {
      return false;
    }
    final header = ref.read(callHeaderProvider);
    final user = header.selectedCaller;
    final notes = state.notesController.text.trim();
    final callerId = header.selectedCaller?.id;
    final callerTextRaw = header.callerDisplayText.trim();
    final callerText = callerId != null
        ? null
        : (callerTextRaw.isEmpty ? 'Άγνωστος' : callerTextRaw);
    try {
      stopTimer();
      final callId = await DatabaseHelper.instance.insertCall(CallModel(
        date: null,
        time: null,
        callerId: callerId ?? user?.id,
        equipmentId: header.selectedEquipment?.id,
        callerText: callerText,
        issue: notes.isEmpty ? null : notes,
        solution: null,
        category: state.category.isEmpty ? null : state.category,
        status: state.isPending ? 'pending' : 'completed',
        duration: state.durationSeconds,
      ));
      if (user?.id != null) {
        ref.invalidate(recentCallsProvider(user!.id!));
      }
      if (header.selectedPhone != null) {
        ref.read(callHeaderProvider.notifier).markPhoneUsed(header.selectedPhone!);
      }
      if (state.isPending) {
        final callerName = user?.name ?? (callerTextRaw.trim().isEmpty ? null : callerTextRaw.trim());
        final callDate = DateTime.now();
        await ref.read(taskServiceProvider).createFromCall(
          callId: callId,
          callerName: callerName,
          description: notes,
          callDate: callDate,
        );
        ref.invalidate(tasksProvider);
      }
      reset();
      ref.read(callHeaderProvider.notifier).clearAll();
      ref.read(callHeaderProvider.notifier).requestPhoneFocus();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Επαναφορά όλων των πεδίων της φόρμας κλήσης (χρονόμετρο, πεδία, σημειώσεις, κατηγορία, checkbox).
  void reset() {
    stopTimer();
    state.internalController.clear();
    state.notesController.clear();
    state = CallEntryState(
      internalFocusNode: state.internalFocusNode,
      internalController: state.internalController,
      notesController: state.notesController,
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

final callEntryProvider =
    NotifierProvider<CallEntryNotifier, CallEntryState>(CallEntryNotifier.new);

/// Τελευταίες κλήσεις ανά userId (limit 3).
final recentCallsProvider =
    FutureProvider.family<List<CallModel>, int>((ref, userId) async {
  final maps = await DatabaseHelper.instance.getRecentCallsByUserId(
    userId,
    limit: 3,
  );
  return maps.map((m) => CallModel.fromMap(m)).toList();
});
