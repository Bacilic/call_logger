import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../provider/call_header_provider.dart';
import '../provider/lookup_provider.dart';
import 'calls_field_confirmations.dart';
import 'calls_field_groups.dart';

/// Field confirmation flags updated on blur / submit / selection.
final callsFieldConfirmationsProvider =
    NotifierProvider<CallsFieldConfirmationsNotifier, CallsFieldConfirmations>(
      CallsFieldConfirmationsNotifier.new,
    );

class CallsFieldConfirmationsNotifier extends Notifier<CallsFieldConfirmations> {
  @override
  CallsFieldConfirmations build() => CallsFieldConfirmations.empty;

  void confirmPhone() {
    ref.read(callsScreenExpandedLatchProvider.notifier).engage();
    if (state.phone) return;
    state = state.copyWith(phone: true);
  }

  void confirmEquipment() {
    ref.read(callsScreenExpandedLatchProvider.notifier).engage();
    if (state.equipment) return;
    state = state.copyWith(equipment: true);
  }

  void confirmDepartment() {
    ref.read(callsScreenExpandedLatchProvider.notifier).engage();
    if (state.department) return;
    state = state.copyWith(department: true);
  }

  void confirmCaller() {
    ref.read(callsScreenExpandedLatchProvider.notifier).engage();
    if (state.caller) return;
    state = state.copyWith(caller: true);
  }

  void resetAll() {
    state = CallsFieldConfirmations.empty;
  }
}

/// Resolved active field groups from header + confirmations.
final callsFieldGroupsProvider = Provider<CallsFieldGroups>((ref) {
  final header = ref.watch(callHeaderProvider);
  final confirmations = ref.watch(callsFieldConfirmationsProvider);
  final lookup = ref.watch(lookupServiceProvider).value?.service;
  return CallsFieldGroupsResolver.resolve(header, confirmations, lookup);
});

/// Derived expanded/compact screen mode (respects editing latch — red X never collapses).
final callsScreenExpandedLatchProvider =
    NotifierProvider<CallsScreenExpandedLatchNotifier, bool>(
      CallsScreenExpandedLatchNotifier.new,
    );

class CallsScreenExpandedLatchNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void engage() {
    if (!state) state = true;
  }

  void release() => state = false;
}

/// True when the screen should show expanded layout (active groups or editing latch).
final callsScreenIsExpandedProvider = Provider<bool>((ref) {
  final groups = ref.watch(callsFieldGroupsProvider);
  final latch = ref.watch(callsScreenExpandedLatchProvider);
  return latch || groups.anyGroupActive;
});

/// @deprecated Use [callsScreenIsExpandedProvider].
final callsScreenModeProvider = callsScreenIsExpandedProvider;
