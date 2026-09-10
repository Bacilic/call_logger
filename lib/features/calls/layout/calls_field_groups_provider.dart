import 'package:flutter/widgets.dart';
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

class CallsFieldConfirmationsNotifier
    extends Notifier<CallsFieldConfirmations> {
  @override
  CallsFieldConfirmations build() => CallsFieldConfirmations.empty;

  void confirmPhone() {
    ref.read(callsScreenExpandedLatchProvider.notifier).engage();
    if (state.phone) return;
    state = state.copyWith(phone: true);
  }

  void unconfirmPhone() {
    if (!state.phone) return;
    state = state.copyWith(phone: false);
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

/// Δίνει στο [child] **δική του** κατάσταση οθόνης Κλήσεων.
///
/// **Το πρόβλημα που λύνει:** τα πεδία Τηλέφωνο/Καλών/Τμήμα/Εξοπλισμός είναι
/// ένα κοινό widget. Όπου κι αν σταθεί, γράφει στους παραπάνω providers — οπότε
/// η πληκτρολόγηση μέσα σε άλλη φόρμα άλλαζε την εικόνα της οθόνης Κλήσεων:
/// κάρτες που εξαφανίζονταν, μεγάλη προβολή που άνοιγε μόνη της.
///
/// Κάθε διάλογος που φιλοξενεί αυτά τα πεδία χωρίς να ΕΙΝΑΙ η οθόνη Κλήσεων
/// τυλίγεται σε αυτό. Η λίστα ζει εδώ, δίπλα στους ίδιους τους providers:
/// όποιος προσθέσει καινούριο κρίκο κατάστασης τον βλέπει και τον προσθέτει.
class IsolatedCallsScreenState extends StatelessWidget {
  const IsolatedCallsScreenState({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        callsFieldConfirmationsProvider.overrideWith(
          CallsFieldConfirmationsNotifier.new,
        ),
        callsScreenExpandedLatchProvider.overrideWith(
          CallsScreenExpandedLatchNotifier.new,
        ),
      ],
      child: child,
    );
  }
}

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
