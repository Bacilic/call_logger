import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/services/lookup_service.dart';
import '../models/call_model.dart';
import '../models/equipment_model.dart';
import '../models/user_model.dart';

/// Κατάσταση φόρμας εισαγωγής κλήσης.
class CallEntryState {
  CallEntryState({
    this.internalDigits = '',
    this.selectedUser,
    this.selectedEquipment,
    this.notes = '',
    this.category = '',
    required this.internalFocusNode,
    required this.internalController,
    required this.notesController,
  });

  final String internalDigits;
  final UserModel? selectedUser;
  final EquipmentModel? selectedEquipment;
  final String notes;
  final String category;
  final FocusNode internalFocusNode;
  final TextEditingController internalController;
  final TextEditingController notesController;

  CallEntryState copyWith({
    String? internalDigits,
    UserModel? selectedUser,
    EquipmentModel? selectedEquipment,
    String? notes,
    String? category,
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
      internalFocusNode: internalFocusNode ?? this.internalFocusNode,
      internalController: internalController ?? this.internalController,
      notesController: notesController ?? this.notesController,
    );
  }
}

/// Notifier για τη φόρμα εισαγωγής κλήσης (FocusNode, submit, reset).
class CallEntryNotifier extends Notifier<CallEntryState> {
  @override
  CallEntryState build() {
    return CallEntryState(
      internalFocusNode: FocusNode(),
      internalController: TextEditingController(),
      notesController: TextEditingController(),
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

  void setCategory(String value) {
    state = state.copyWith(category: value);
  }

  /// Υποβολή κλήσης, reset φόρμας και επιστροφή focus στο "Εσωτερικό".
  /// Το requestFocus γίνεται σε microtask ώστε να μην συμπέσει με key event/rebuild.
  Future<bool> submitCall() async {
    final user = state.selectedUser;
    final notes = state.notesController.text.trim();
    if (user == null || notes.isEmpty) return false;
    try {
      await DatabaseHelper.instance.insertCall(CallModel(
        callerId: user.id,
        equipmentId: state.selectedEquipment?.id,
        issue: notes,
        solution: null,
        category: state.category.isEmpty ? null : state.category,
        status: 'open',
      ));
      reset();
      Future.microtask(() => state.internalFocusNode.requestFocus());
      return true;
    } catch (_) {
      return false;
    }
  }

  void reset() {
    state.internalController.clear();
    state.notesController.clear();
    state = CallEntryState(
      internalFocusNode: state.internalFocusNode,
      internalController: state.internalController,
      notesController: state.notesController,
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
