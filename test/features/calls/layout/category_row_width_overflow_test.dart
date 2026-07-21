// Regression: η γραμμή «Κατηγορία + χρονόμετρο + Καταγραφή»
// ([_CategoryTimerSubmitRow]) δεν πρέπει να υπερχειλίζει (RenderFlex overflow)
// σε ΚΑΝΕΝΑ πλάτος — ούτε στο ελάχιστο επιτρεπτό παράθυρο ούτε σε πολύ πλατύ.
//
// Ιστορικό: το πεδίο κατηγορίας ήταν σταθερό `SizedBox(width: 380)` ενώ το
// κατώφλι στοίβαξης ήταν 560px· στη ζώνη ~560–632px η γραμμή υπερχείλιζε
// (10–25px). Το προηγούμενο τεστ δοκίμαζε μόνο 1050/1150px — άνετα πλάτη που
// ΔΕΝ άγγιζαν ποτέ το όριο. Εδώ σαρώνουμε ΚΑΙ τα σύνορα (ελάχιστο) ΚΑΙ ένα
// μέγιστο πλάτος.
//
//   flutter test test/features/calls/layout/header_min_width_overflow_repro_test.dart

import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:call_logger/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../test_setup.dart';

Future<void> _pumpCallsAtWidth(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.runAsync(() async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: callLoggerTestProviderOverrides(),
        child: const MyApp(),
      ),
    );
    await tester.pump();
    await pumpUntilSettledLong(tester);
    await GoogleFonts.pendingFonts();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    await container.read(lookupServiceProvider.future);
  });
}

Future<void> _confirmPhoneField(WidgetTester tester) async {
  final phoneField = callLoggerPhoneTextField();
  await tester.tap(phoneField);
  await pumpUntilSettled(tester);
  await tester.enterText(phoneField, kTestPhoneDigits);
  await tester.pump();
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pump(const Duration(milliseconds: 400));
  await pumpUntilSettled(tester, steps: 40);
}

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  group('Γραμμή Κατηγορίας — χωρίς overflow σε όρια πλάτους', () {
    // 840–922: ζώνη γύρω/κάτω από το ελάχιστο επιτρεπτό παράθυρο, όπου η παλιά
    // υλοποίηση υπερχείλιζε. 1500: αντιπροσωπευτικό «μέγιστο» πλάτος.
    for (final width in [840.0, 890.0, 905.0, 922.0, 1500.0]) {
      testWidgets('expanded, επιβεβαιωμένο τηλέφωνο: $width px χωρίς overflow',
          (tester) async {
        await _pumpCallsAtWidth(tester, width);
        await _confirmPhoneField(tester);
        await tester.pump(const Duration(milliseconds: 500));
        expect(
          tester.takeException(),
          isNull,
          reason: greekExpectMsgOrNull(width),
        );
        await tester.pump(const Duration(seconds: 11));
      }, semanticsEnabled: false);
    }
  });
}

String greekExpectMsgOrNull(double width) =>
    'Πλάτος $width px: η γραμμή Κατηγορία+Χρονόμετρο+Καταγραφή υπερχείλισε '
    '(RenderFlex overflow) — το πεδίο κατηγορίας πρέπει να συρρικνώνεται ελαστικά.';
