// Widget test: η αναβολή ακύρωσης του tasksProvider ζητά το frame που περιμένει.
//
//   flutter test test/features/tasks/defer_tasks_invalidate_test.dart

import 'package:call_logger/features/tasks/providers/tasks_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'το future ολοκληρώνεται και όταν καλείται από αδρανή εφαρμογή (χωρίς frame σε εξέλιξη)',
    (tester) async {
      late WidgetRef capturedRef;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                capturedRef = ref;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(SchedulerBinding.instance.hasScheduledFrame, isFalse);

      var completed = false;
      final future = deferTasksProviderInvalidate(
        capturedRef,
      ).then((_) => completed = true);

      expect(
        SchedulerBinding.instance.hasScheduledFrame,
        isTrue,
        reason:
            'Ο καλών περιμένει το future· αν κανείς δεν ζητήσει frame, '
            'το postFrame δεν τρέχει ποτέ σε αδρανή εφαρμογή.',
      );

      await tester.pump();
      await future;
      expect(completed, isTrue);
    },
  );
}
