// Unit test: εκτέλεση στο επόμενο frame με εγγυημένη ολοκλήρωση.
//
//   flutter test test/core/utils/run_after_next_frame_test.dart

import 'dart:async';

import 'package:call_logger/core/utils/run_after_next_frame.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'ζητά ρητά frame: το future ολοκληρώνεται και όταν η εφαρμογή είναι αδρανής',
    (tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      // Αφετηρία: καμία εκκρεμότητα — κανείς δεν έχει ζητήσει frame.
      expect(SchedulerBinding.instance.hasScheduledFrame, isFalse);

      var ran = false;
      var completed = false;
      final future = runAfterNextFrame(() => ran = true)
          .then((_) => completed = true);

      // Το συμβόλαιο: η ίδια η συνάρτηση ζητά το frame. Χωρίς αυτό, σε
      // πραγματική αδρανή εφαρμογή το future δεν θα ολοκληρωνόταν ποτέ.
      expect(
        SchedulerBinding.instance.hasScheduledFrame,
        isTrue,
        reason:
            'Το addPostFrameCallback δεν προγραμματίζει frame από μόνο του· '
            'χωρίς ensureVisualUpdate ο καλών περιμένει για πάντα.',
      );

      await tester.pump();
      await future;
      expect(ran, isTrue);
      expect(completed, isTrue);
    },
  );

  testWidgets('εξαίρεση μέσα στο action δεν αφήνει τον καλούντα να κρέμεται', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();

    var completed = false;
    unawaited(
      runAfterNextFrame(() => throw StateError('σφάλμα στο action')).then(
        (_) => completed = true,
      ),
    );

    await tester.pump();
    expect(completed, isTrue);
    // Η εξαίρεση δηλώνεται κανονικά στο framework, δεν καταπίνεται σιωπηλά.
    expect(tester.takeException(), isStateError);
  });
}
