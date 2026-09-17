// Η γρήγορη καταχώρηση ανακοινώνει το αποτέλεσμα ακόμη και όταν η κεφαλίδα
// έχει φύγει από τη σκηνή.
//
// Η καταχώρηση έχει ήδη γραφτεί όταν φτάνει η ανακοίνωση· αν στο μεταξύ το
// widget ξηλωθεί, ο χρήστης δεν πρέπει ούτε να χάσει το μήνυμα ούτε να δει σφάλμα.
//
//   flutter test test/features/calls/caller_quick_add_bindings_unmount_test.dart

import 'package:call_logger/features/calls/controllers/caller_quick_add_controller.dart';
import 'package:call_logger/features/calls/controllers/call_submit_controller.dart';
import 'package:call_logger/features/calls/screens/widgets/call_submit_bindings.dart';
import 'package:call_logger/features/calls/screens/widgets/caller_quick_add_bindings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Κρατά τον controller που γεννήθηκε μέσα στο δέντρο, ώστε να κληθεί αφού φύγει.
class _Host extends ConsumerStatefulWidget {
  const _Host({required this.onReady, this.onSubmitReady});

  final void Function(CallerQuickAddController controller) onReady;
  final void Function(CallSubmitController controller)? onSubmitReady;

  @override
  ConsumerState<_Host> createState() => _HostState();
}

class _HostState extends ConsumerState<_Host> {
  @override
  Widget build(BuildContext context) {
    widget.onReady(
      buildCallerQuickAddController(
        ref: ref,
        context: context,
        messenger: ScaffoldMessenger.of(context),
      ),
    );
    widget.onSubmitReady?.call(
      buildCallSubmitController(ref: ref, context: context),
    );
    return const SizedBox.shrink();
  }
}

void main() {
  testWidgets('η ανακοίνωση φτάνει και όταν η κεφαλίδα έχει ξηλωθεί', (
    tester,
  ) async {
    late CallerQuickAddController controller;
    var showHeader = true;
    late StateSetter rebuild;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return showHeader
                    ? _Host(onReady: (c) => controller = c)
                    : const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );

    // Η κεφαλίδα φεύγει όσο η καταχώρηση ολοκληρώνεται.
    rebuild(() => showHeader = false);
    await tester.pump();

    controller.prompts.announce('Καταχωρήθηκε.');
    await tester.pump();

    expect(
      find.text('Καταχωρήθηκε.'),
      findsOneWidget,
      reason: 'Η καταχώρηση έγινε — το μήνυμα οφείλει να φτάσει στον χρήστη.',
    );
  });

  testWidgets('η υποβολή διαβάζει την κεφαλίδα και μετά το ξήλωμα', (
    tester,
  ) async {
    late CallSubmitController controller;
    var showHeader = true;
    late StateSetter rebuild;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return showHeader
                    ? _Host(
                        onReady: (_) {},
                        onSubmitReady: (c) => controller = c,
                      )
                    : const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );

    // Η φόρμα φεύγει όσο είναι ανοιχτός ο διάλογος ταυτοποίησης.
    rebuild(() => showHeader = false);
    await tester.pump();

    expect(
      () => controller.actions.header,
      returnsNormally,
      reason:
          'Η υποβολή συνεχίζει μετά τον διάλογο, ακόμη κι αν η φόρμα έφυγε.',
    );
  });
}
