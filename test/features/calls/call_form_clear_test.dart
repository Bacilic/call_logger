// Πλήρης εκκαθάριση φόρμας κλήσης + ξέπλυμα αλυσίδας providers της οθόνης.
//
// Αναπαράγει την κατάρρευση «setState() or markNeedsBuild() called during build»
// (πραγματικό περιστατικό 24/07): διακοπή κλήσης από τον διάλογο-φρουρό ενώ ο
// χρήστης βρίσκεται σε ΑΛΛΗ οθόνη, μετά χειροκίνητη επιστροφή στις Κλήσεις.
//
//   flutter test test/features/calls/call_form_clear_test.dart

import 'package:call_logger/features/calls/layout/call_form_clear.dart';
import 'package:call_logger/features/calls/layout/calls_field_groups_provider.dart';
import 'package:call_logger/features/calls/provider/call_entry_provider.dart';
import 'package:call_logger/features/calls/provider/call_header_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Γεμίζει τη φόρμα και επιβεβαιώνει πεδία (όπως μια πραγματική ημιτελής κλήση).
void _fillHalfEnteredCall(ProviderContainer container) {
  container
      .read(callHeaderProvider.notifier)
      .updateCallerDisplayText('Βαρβάρα Νακαστσή');
  container
      .read(callHeaderProvider.notifier)
      .updateDepartmentText('Γραμματεία ΤΕΠ');
  container
      .read(callEntryProvider.notifier)
      .setNotes('Δεν συνδέεται ο εκτυπωτής');
  container.read(callEntryProvider.notifier).setCategory('Δίκτυο');
  // Οι επιβεβαιώσεις πεδίων ενεργοποιούν ΚΑΙ το μάνταλο μεγάλης προβολής.
  container.read(callsFieldConfirmationsProvider.notifier).confirmCaller();
  container.read(callsFieldConfirmationsProvider.notifier).confirmDepartment();
}

/// Δέντρο ΧΩΡΙΣ την αλυσίδα της οθόνης κλήσεων (ο χρήστης είναι σε άλλη οθόνη).
Widget _treeWithoutCallsScreen(
  ProviderContainer container,
  void Function(WidgetRef) captureRef,
) {
  return UncontrolledProviderScope(
    container: container,
    child: Consumer(
      builder: (context, ref, _) {
        captureRef(ref);
        return const SizedBox.shrink();
      },
    ),
  );
}

/// Το πρώτο `watch` της οθόνης κλήσεων ([CallsScreenLayout.build]).
class _CallsChainConsumer extends ConsumerWidget {
  const _CallsChainConsumer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(callsScreenIsExpandedProvider);
    ref.watch(callsFieldGroupsProvider.select((g) => g.anyGroupActive));
    return const SizedBox.shrink();
  }
}

/// Σταθερό `UncontrolledProviderScope` με εναλλασσόμενη οθόνη κλήσεων.
///
/// Κρίσιμο για την πιστή αναπαραγωγή: το scope προσαρτάται ΜΙΑ φορά και δεν
/// ξαναχτίζεται ποτέ. Η οθόνη κλήσεων προσαρτάται μέσα σε build που ήδη τρέχει
/// (όπως στο πραγματικό stack trace: `performRebuild` γονέα → `inflateWidget`
/// → `mount` → `_firstBuild` του `CallsScreenLayout`), οπότε το `markNeedsBuild`
/// πέφτει πάνω σε πρόγονο που ΔΕΝ βρίσκεται σε φάση κατασκευής.
Widget _stableScopeWithToggle(
  ProviderContainer container,
  ValueListenable<bool> showCallsScreen,
  void Function(WidgetRef) captureRef,
) {
  return UncontrolledProviderScope(
    container: container,
    child: Column(
      textDirection: TextDirection.ltr,
      children: [
        Consumer(
          builder: (context, ref, _) {
            captureRef(ref);
            return const SizedBox.shrink();
          },
        ),
        ValueListenableBuilder<bool>(
          valueListenable: showCallsScreen,
          builder: (context, show, _) =>
              show ? const _CallsChainConsumer() : const SizedBox.shrink(),
        ),
      ],
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'τα δύο βήματα (clearAll + reset) αφήνουν κολλημένες επιβεβαιώσεις και μάνταλο',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_treeWithoutCallsScreen(container, (_) {}));
      _fillHalfEnteredCall(container);

      // Ημιτελής εκκαθάριση — ό,τι έκανε ο φρουρός πριν τη διόρθωση.
      container.read(callHeaderProvider.notifier).clearAll();
      container.read(callEntryProvider.notifier).reset();

      expect(
        container.read(callsFieldConfirmationsProvider).caller,
        isTrue,
        reason:
            'Χωρίς resetAll οι επιβεβαιώσεις της ακυρωμένης κλήσης επιβιώνουν',
      );
      expect(
        container.read(callsScreenExpandedLatchProvider),
        isTrue,
        reason: 'Χωρίς release το μάνταλο μεγάλης προβολής μένει οπλισμένο',
      );
    },
  );

  testWidgets(
    'η clearCallFormCompletely μηδενίζει ΚΑΙ επιβεβαιώσεις ΚΑΙ μάνταλο',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      late WidgetRef outerRef;
      await tester.pumpWidget(
        _treeWithoutCallsScreen(container, (ref) => outerRef = ref),
      );
      _fillHalfEnteredCall(container);

      clearCallFormCompletely(outerRef);

      expect(container.read(callsFieldConfirmationsProvider).caller, isFalse);
      expect(
        container.read(callsFieldConfirmationsProvider).department,
        isFalse,
      );
      expect(container.read(callsScreenExpandedLatchProvider), isFalse);
      expect(container.read(callHeaderProvider).selectedCaller, isNull);
      expect(container.read(callEntryProvider).notes, isEmpty);
      expect(container.read(callEntryProvider).category, isEmpty);
    },
  );

  // ΕΙΛΙΚΡΙΝΗΣ ΕΠΙΣΗΜΑΝΣΗ: το τεστ αυτό ΔΕΝ αναπαράγει την αρχική κατάρρευση
  // «markNeedsBuild during build». Στο περιβάλλον του tester το scope προλαβαίνει
  // να σημανθεί dirty από το `scheduleProviderRefresh` και ξαναχτίζεται ΠΡΙΝ το
  // παιδί, οπότε η αλυσίδα έχει ήδη ξεπλυθεί όταν προσαρτάται η οθόνη — περνά και
  // χωρίς το [flushCallsScreenProviderChain] (επαληθεύτηκε πειραματικά).
  // Το κρατάμε ως έλεγχος ΚΑΤΑΣΤΑΣΗΣ: μετά από εκκαθάριση εκτός οθόνης, η
  // επιστροφή δίνει καθαρή compact οθόνη χωρίς εξαίρεση.
  testWidgets(
    'επιστροφή στην οθόνη κλήσεων μετά από εκκαθάριση εκτός οθόνης δίνει compact οθόνη',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final showCallsScreen = ValueNotifier<bool>(true);
      addTearDown(showCallsScreen.dispose);

      late WidgetRef outerRef;
      await tester.pumpWidget(
        _stableScopeWithToggle(
          container,
          showCallsScreen,
          (ref) => outerRef = ref,
        ),
      );

      // Φάση 1: ο χρήστης είναι στην οθόνη Κλήσεων — η αλυσίδα υπολογίζεται.
      await tester.pump();
      _fillHalfEnteredCall(container);
      await tester.pump();

      // Φάση 2: φεύγει σε άλλη οθόνη· η αλυσίδα μένει χωρίς listeners.
      showCallsScreen.value = false;
      await tester.pump();

      // Διακοπή κλήσης από τον διάλογο-φρουρό, με την οθόνη μη προσαρτημένη.
      clearCallFormCompletely(outerRef);

      // Φάση 3: επιστρέφει στις Κλήσεις — η οθόνη προσαρτάται ΜΕΣΑ σε build
      // που ήδη τρέχει, ενώ το scope (πρόγονος) δεν ξαναχτίζεται.
      showCallsScreen.value = true;
      await tester.pump();

      expect(
        tester.takeException(),
        isNull,
        reason: 'Η αλυσίδα πρέπει να έχει ξεπλυθεί ΕΚΤΟΣ φάσης build',
      );
      expect(container.read(callsScreenIsExpandedProvider), isFalse);
    },
  );
}
