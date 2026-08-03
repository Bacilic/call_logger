// Μετά από μαζική ενέργεια Καταλόγου, η αλυσίδα της οθόνης κλήσεων ξεπλένεται
// ΕΚΤΟΣ φάσης build.
//
// Χωρίς αυτό, η ακύρωση του `lookupServiceProvider` αφήνει το
// `callsScreenIsExpandedProvider` → `callsFieldGroupsProvider` «dirty χωρίς
// listeners» (η οθόνη κλήσεων δεν είναι προσαρτημένη όσο ο χρήστης δουλεύει
// στον Κατάλογο). Η αλυσίδα ξεπλένεται αργότερα σύγχρονα μέσα σε build — όταν
// αλλάξει το `TickerMode` επειδή άνοιξε ή έκλεισε διάλογος — και η εφαρμογή
// πέφτει με «setState() called during build».
//
// Ολόκληρο αρχείο (από ρίζα έργου):
//   flutter test test/features/directory/directory_cache_refresh_flush_test.dart

import 'package:call_logger/features/calls/layout/call_form_clear.dart';
import 'package:call_logger/features/calls/layout/calls_field_groups_provider.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_setup.dart';

/// Ελάχιστο widget που παίζει τον ρόλο καρτέλας Καταλόγου: ακυρώνει το lookup
/// όπως κάθε μαζική ενέργεια και μετά ξεπλένει την αλυσίδα.
class _MutatingTab extends ConsumerStatefulWidget {
  const _MutatingTab();

  @override
  ConsumerState<_MutatingTab> createState() => _MutatingTabState();
}

class _MutatingTabState extends ConsumerState<_MutatingTab> {
  void runMutation() {
    ref.invalidate(lookupServiceProvider);
    flushCallsChainAfterDirectoryMutation(ref);
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  testWidgets(
    'μετά από μαζική ενέργεια η αλυσίδα των Κλήσεων έχει ξεπλυθεί',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: callLoggerTestProviderOverrides(),
          child: const MaterialApp(home: _MutatingTab()),
        ),
      );
      await tester.pump();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(_MutatingTab)),
      );

      // Ο χρήστης δεν έχει ανοίξει την οθόνη κλήσεων: η αλυσίδα δεν υπάρχει.
      expect(container.exists(callsFieldGroupsProvider), isFalse);
      expect(container.exists(callsScreenIsExpandedProvider), isFalse);

      final state = tester.state<_MutatingTabState>(find.byType(_MutatingTab));
      state.runMutation();

      // Ο καλών βρίσκεται εκτός build (μετά από `await` της μετάλλαξης), οπότε
      // το ξέπλυμα γίνεται αμέσως: δεν μένει τίποτα «dirty» για επόμενο build.
      expect(container.exists(callsFieldGroupsProvider), isTrue);
      expect(container.exists(callsScreenIsExpandedProvider), isTrue);

      await flushCallLoggerSqfliteLockTimers(tester);
    },
    semanticsEnabled: false,
  );
}
