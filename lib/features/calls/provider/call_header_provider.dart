import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/equipment_model.dart';
import '../models/user_model.dart';

/// Κατάσταση header φόρμας κλήσης: επιλογές, σφάλμα, πρόσφατα τηλέφωνα.
/// FocusNodes ΔΕΝ αποθηκεύονται εδώ — ζουν στο widget State.
class CallHeaderState {
  CallHeaderState({
    this.selectedPhone,
    this.selectedCaller,
    this.selectedEquipment,
    this.phoneError,
    List<String>? recentPhones,
  }) : recentPhones = recentPhones ?? [];

  final String? selectedPhone;
  final UserModel? selectedCaller;
  final EquipmentModel? selectedEquipment;
  final String? phoneError;
  final List<String> recentPhones;

  static const int _maxRecentPhones = 20;

  CallHeaderState copyWith({
    String? selectedPhone,
    UserModel? selectedCaller,
    EquipmentModel? selectedEquipment,
    String? phoneError,
    List<String>? recentPhones,
  }) {
    return CallHeaderState(
      selectedPhone: selectedPhone ?? this.selectedPhone,
      selectedCaller: selectedCaller ?? this.selectedCaller,
      selectedEquipment: selectedEquipment ?? this.selectedEquipment,
      phoneError: phoneError ?? this.phoneError,
      recentPhones: recentPhones ?? this.recentPhones,
    );
  }

  CallHeaderState copyWithClearSelections() {
    return copyWith(
      selectedPhone: null,
      selectedCaller: null,
      selectedEquipment: null,
      phoneError: null,
    );
  }
}

/// Notifier για το header: update/clear, recentPhones, clearAfterSubmit.
/// FocusNodes αποθηκεύονται ως instance fields (εγγράφονται από το widget).
class CallHeaderNotifier extends Notifier<CallHeaderState> {
  FocusNode? _phoneFocusNode;
  FocusNode? _callerFocusNode;
  FocusNode? _equipmentFocusNode;

  FocusNode? get phoneFocusNode => _phoneFocusNode;
  FocusNode? get callerFocusNode => _callerFocusNode;
  FocusNode? get equipmentFocusNode => _equipmentFocusNode;

  void registerFocusNodes({
    required FocusNode phone,
    required FocusNode caller,
    required FocusNode equipment,
  }) {
    _phoneFocusNode = phone;
    _callerFocusNode = caller;
    _equipmentFocusNode = equipment;
  }

  void unregisterFocusNodes() {
    _phoneFocusNode = null;
    _callerFocusNode = null;
    _equipmentFocusNode = null;
  }

  @override
  CallHeaderState build() {
    return CallHeaderState();
  }

  void updatePhone(String? value) {
    state = state.copyWith(selectedPhone: value, phoneError: null);
  }

  void clearPhone() {
    state = state.copyWith(
      selectedPhone: null,
      selectedCaller: null,
      selectedEquipment: null,
      phoneError: null,
    );
  }

  /// Μηδενίζει selectedPhone, selectedCaller, selectedEquipment, phoneError (για clear button).
  void clearAll() {
    state = state.copyWith(
      selectedPhone: null,
      selectedCaller: null,
      selectedEquipment: null,
      phoneError: null,
    );
  }

  void setCaller(UserModel? value) {
    state = state.copyWith(selectedCaller: value);
  }

  void clearCaller() {
    state = state.copyWith(selectedCaller: null);
  }

  void setEquipment(EquipmentModel? value) {
    state = state.copyWith(selectedEquipment: value);
  }

  void clearEquipment() {
    state = state.copyWith(selectedEquipment: null);
  }

  void setPhoneError(String? message) {
    state = state.copyWith(phoneError: message);
  }

  void clearPhoneError() {
    state = state.copyWith(phoneError: null);
  }

  void markPhoneUsed(String phone) {
    final trimmed = phone.trim();
    if (trimmed.isEmpty) return;
    final list = List<String>.from(state.recentPhones);
    list.remove(trimmed);
    list.insert(0, trimmed);
    if (list.length > CallHeaderState._maxRecentPhones) {
      list.length = CallHeaderState._maxRecentPhones;
    }
    state = state.copyWith(recentPhones: list);
  }

  void clearAfterSubmit() {
    state = state.copyWithClearSelections();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _phoneFocusNode?.requestFocus();
    });
  }

  void requestPhoneFocus() {
    _phoneFocusNode?.requestFocus();
  }
}

final callHeaderProvider =
    NotifierProvider<CallHeaderNotifier, CallHeaderState>(CallHeaderNotifier.new);
