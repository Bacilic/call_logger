// Regression: στενό παράθυρο expanded — χωρίς RenderFlex overflow στα πεδία συμπλήρωσης.
//
//   flutter test test/features/calls/layout/narrow_viewport_overflow_test.dart

import 'package:call_logger/features/calls/layout/calls_field_groups_provider.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:call_logger/features/calls/screens/calls_screen.dart';
import 'package:call_logger/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../test_reporter.dart';
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

  group('Οθόνη Κλήσεων — overflow σε στενό παράθυρο', () {
    for (final width in [1050.0, 1150.0]) {
      testWidgets(
        'expanded με επιβεβαιωμένο τηλέφωνο: πλάτος $width χωρίς overflow',
        (tester) async {
          await _pumpCallsAtWidth(tester, width);
          await _confirmPhoneField(tester);

          final container = ProviderScope.containerOf(
            tester.element(find.byType(CallsScreen)),
          );
          expect(container.read(callsScreenIsExpandedProvider), isTrue);

          await tester.pump(const Duration(milliseconds: 500));
          expect(
            tester.takeException(),
            isNull,
            reason: greekExpectMsg(
              'Στενό παράθυρο ($width px): χωρίς RenderFlex overflow στα πεδία',
            ),
          );
          await tester.pump(const Duration(seconds: 11));
        },
        semanticsEnabled: false,
      );
    }
  });
}
