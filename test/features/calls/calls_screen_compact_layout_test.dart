// Widget tests: θέση Τελευταίες Κλήσεις — κλειστό = κάτω δεξιά, ανοιχτό expanded = slot πλάνου.
//
//   flutter test test/features/calls/calls_screen_compact_layout_test.dart

import 'package:call_logger/features/calls/layout/calls_field_groups_provider.dart';
import 'package:call_logger/features/calls/provider/calls_dashboard_providers.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:call_logger/features/calls/screens/calls_screen.dart';
import 'package:call_logger/features/calls/screens/widgets/global_recent_calls_list.dart';
import 'package:call_logger/features/calls/screens/widgets/notes_sticky_field.dart';
import 'package:call_logger/features/calls/screens/widgets/smart_entity_selector_widget.dart';
import 'package:call_logger/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../test_reporter.dart';
import '../../test_setup.dart';

/// Ζώνη κάτω-δεξιά όπου μένει ο διακόπτης όταν η κάρτα ΤΚ είναι κλειστή (px).
const double kTkBottomRightAnchorInset = 96;

/// Κατώφλι: κάτω από αυτό το ποσοστό του viewport θεωρείται «γωνία οθόνης».
const double kTkBottomCornerMaxCenterRatio = 0.82;

/// Αποδεκτή ζώνη κάθετου κέντρου γραμμής πεδίων στη συμπτυγμένη όψη.
const double kCompactFieldRowCenterMinRatio = 0.44;
const double kCompactFieldRowCenterMaxRatio = 0.56;

Finder _globalRecentToggleFinder() =>
    find.widgetWithText(TextButton, 'Τελευταίες Κλήσεις');

Rect _callsViewportRect(WidgetTester tester) {
  final expandedFinder = find.ancestor(
    of: find.byType(CallsScreen),
    matching: find.byType(Expanded),
  );
  expect(
    expandedFinder,
    findsWidgets,
    reason: greekExpectMsg('Περιοχή περιεχομένου οθόνης Κλήσεων (Expanded)'),
  );

  Rect largest = Rect.zero;
  for (final element in expandedFinder.evaluate()) {
    final box = element.renderObject;
    if (box is! RenderBox || !box.hasSize) continue;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    if (rect.height > largest.height) {
      largest = rect;
    }
  }
  return largest;
}

bool _isAnchoredBottomRight(Rect widget, Rect viewport) {
  return widget.bottom >= viewport.bottom - kTkBottomRightAnchorInset &&
      widget.right >= viewport.right - kTkBottomRightAnchorInset;
}

double _verticalCenterRatio(Rect widget, Rect viewport) {
  return (widget.center.dy - viewport.top) / viewport.height;
}

void _expectToggleInteractive(WidgetTester tester, {required String phase}) {
  expect(
    _globalRecentToggleFinder(),
    findsOneWidget,
    reason: greekExpectMsg(
      'Το κουμπί «Τελευταίες Κλήσεις» πρέπει να είναι ορατό ($phase)',
    ),
  );
  final button = tester.widget<TextButton>(_globalRecentToggleFinder());
  expect(
    button.onPressed,
    isNotNull,
    reason: greekExpectMsg(
      'Το κουμπί «Τελευταίες Κλήσεις» πρέπει να είναι αλληλεπιδραστικό ($phase)',
    ),
  );
}

void _expectToggleAnchoredBottomRight(WidgetTester tester, {required String phase}) {
  _expectToggleInteractive(tester, phase: phase);
  final viewport = _callsViewportRect(tester);
  final toggleRect = tester.getRect(_globalRecentToggleFinder());
  expect(
    _isAnchoredBottomRight(toggleRect, viewport),
    isTrue,
    reason: greekExpectMsg(
      'Κλειστή ΤΚ: ο διακόπτης πρέπει να αγκυρώνεται κάτω δεξιά ($phase)',
    ),
  );
}

void _expectToggleAbsent({required String phase}) {
  expect(
    _globalRecentToggleFinder(),
    findsNothing,
    reason: greekExpectMsg(
      'Ανοιχτή ΤΚ: ο εξωτερικός διακόπτης κρύβεται — η κάρτα έχει δικό της Switch ($phase)',
    ),
  );
}

Finder _globalRecentCardSwitchFinder() {
  return find.descendant(
    of: find.byType(GlobalRecentCallsList),
    matching: find.byType(Switch),
  );
}

Future<void> _closeGlobalRecentViaCardSwitch(WidgetTester tester) async {
  await tester.tap(_globalRecentCardSwitchFinder());
  await pumpUntilSettled(tester);
}

void _expectGlobalRecentListAbsent({required String phase}) {
  expect(
    find.byType(GlobalRecentCallsList),
    findsNothing,
    reason: greekExpectMsg(
      'Κλειστή ΤΚ: η κάρτα δεν εμφανίζεται στο πλέγμα ($phase)',
    ),
  );
}

/// Αναπτυγμένη + ανοιχτή: η κάρτα μπαίνει στο πλέγμα (Πρότυπο-Α #1, στήλη γραμμής 3),
/// όχι στη γωνία όπου αγκυρώνεται ο κλειστός διακόπτης.
void _expectGlobalRecentListInPlanSlot(
  WidgetTester tester, {
  required String phase,
}) {
  expect(
    find.byType(GlobalRecentCallsList),
    findsOneWidget,
    reason: greekExpectMsg(
      'Ανοιχτή ΤΚ expanded: εμφανίζεται η κάρτα στο πλέγμα ($phase)',
    ),
  );

  final viewport = _callsViewportRect(tester);
  final listRect = tester.getRect(find.byType(GlobalRecentCallsList));
  final notesRect = tester.getRect(find.byType(NotesStickyField));

  expect(
    _isAnchoredBottomRight(listRect, viewport),
    isFalse,
    reason: greekExpectMsg(
      'Ανοιχτή ΤΚ expanded: η κάρτα δεν πρέπει να μένει κάτω δεξιά ($phase)',
    ),
  );

  expect(
    _verticalCenterRatio(listRect, viewport),
    lessThan(kTkBottomCornerMaxCenterRatio),
    reason: greekExpectMsg(
      'Ανοιχτή ΤΚ expanded: η κάρτα πρέπει να ανήκει στη ζώνη πλέγματος, '
      'όχι στη γωνία οθόνης ($phase)',
    ),
  );

  expect(
    listRect.top,
    greaterThanOrEqualTo(notesRect.top - 8),
    reason: greekExpectMsg(
      'Ανοιχτή ΤΚ expanded (Πρότυπο-Α #1): η κάρτα πρέπει να βρίσκεται '
      'στην ίδια ζώνη περιεχομένου με τις Σημειώσεις ($phase)',
    ),
  );
}

Future<void> _pumpCallsApp(WidgetTester tester) async {
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
  await tester.pump(const Duration(milliseconds: 300));
  await tester.sendKeyDownEvent(LogicalKeyboardKey.tab);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.tab);
  await tester.pump(const Duration(milliseconds: 450));
  await pumpUntilSettled(tester, steps: 40, step: const Duration(milliseconds: 60));
}

Future<void> _setGlobalRecentOpen(WidgetTester tester, bool open) async {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(CallsScreen)),
  );
  await tester.runAsync(() async {
    await container
        .read(showGlobalCallsToggleProvider.notifier)
        .setVisible(open);
  });
  await pumpUntilSettled(tester);
}

Future<void> _tapGlobalRecentToggle(WidgetTester tester) async {
  await tester.tap(_globalRecentToggleFinder());
  await pumpUntilSettled(tester);
}

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  group('Οθόνη Κλήσεων — θέση Τελευταίες Κλήσεις', () {
    setUpAll(() async {
      GoogleFonts.config.allowRuntimeFetching = false;
      await seedTestCallRowForHistorySearch();
    });

    testWidgets(
      'συμπτυγμένη: η γραμμή πεδίων είναι κάθετα κεντραρισμένη στο viewport',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await _pumpCallsApp(tester);

        final viewport = _callsViewportRect(tester);
        final selectorRect = tester.getRect(find.byType(SmartEntitySelectorWidget));
        final ratio = _verticalCenterRatio(selectorRect, viewport);

        expect(
          ratio,
          inInclusiveRange(
            kCompactFieldRowCenterMinRatio,
            kCompactFieldRowCenterMaxRatio,
          ),
          reason: greekExpectMsg(
            'Συμπτυγμένη όψη: το κάθετο κέντρο της γραμμής πεδίων πρέπει '
            'να βρίσκεται κοντά στο μέσο του viewport',
          ),
        );
      },
      semanticsEnabled: false,
    );

    testWidgets(
      'κλειστή: διακόπτης κάτω δεξιά· ανοιχτή expanded: κάρτα στο slot του πλάνου',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final reporter = GreekTestReportCollector();

        reporter.logStep('Φόρτωση — συμπτυγμένη όψη');
        await _pumpCallsApp(tester);

        final container = ProviderScope.containerOf(
          tester.element(find.byType(CallsScreen)),
        );
        expect(
          container.read(callsScreenIsExpandedProvider),
          isFalse,
          reason: greekExpectMsg('Αρχική συμπτυγμένη όψη'),
        );

        reporter.logStep('Συμπτυγμένη + κλειστή ΤΚ');
        await _setGlobalRecentOpen(tester, false);
        _expectToggleAnchoredBottomRight(
          tester,
          phase: 'συμπτυγμένη, κλειστή',
        );
        _expectGlobalRecentListAbsent(phase: 'συμπτυγμένη, κλειστή');

        reporter.logStep('Συμπτυγμένη + ανοιχτή ΤΚ — κάρτα κάτω δεξιά, χωρίς εξωτερικό διακόπτη');
        await _tapGlobalRecentToggle(tester);
        _expectToggleAbsent(phase: 'συμπτυγμένη, ανοιχτή');
        expect(
          find.byType(GlobalRecentCallsList),
          findsOneWidget,
          reason: greekExpectMsg(
            'Συμπτυγμένη ανοιχτή: η κάρτα εμφανίζεται κάτω δεξιά',
          ),
        );

        reporter.logStep('Αναπτυγμένη — επιβεβαίωση τηλεφώνου (Πρότυπο-Α #1)');
        await _confirmPhoneField(tester);
        expect(
          container.read(callsScreenIsExpandedProvider),
          isTrue,
          reason: greekExpectMsg('Μετά επιβεβαίωση τηλεφώνου → expanded'),
        );

        reporter.logStep('Αναπτυγμένη + κλειστή ΤΚ — διακόπτης κάτω δεξιά');
        await _setGlobalRecentOpen(tester, false);
        _expectToggleAnchoredBottomRight(
          tester,
          phase: 'αναπτυγμένη, κλειστή',
        );
        _expectGlobalRecentListAbsent(phase: 'αναπτυγμένη, κλειστή');

        reporter.logStep('Αναπτυγμένη + ανοιχτή ΤΚ — κάρτα στο πλέγμα, χωρίς εξωτερικό διακόπτη');
        await _tapGlobalRecentToggle(tester);
        _expectToggleAbsent(phase: 'αναπτυγμένη, ανοιχτή');
        _expectGlobalRecentListInPlanSlot(
          tester,
          phase: 'αναπτυγμένη, ανοιχτή (Πρότυπο-Α #1)',
        );

        reporter.logStep('Αναπτυγμένη — κλείσιμο από Switch κάρτας, διακόπτης κάτω δεξιά');
        await _closeGlobalRecentViaCardSwitch(tester);
        _expectToggleAnchoredBottomRight(
          tester,
          phase: 'αναπτυγμένη, επανακλείσιμο',
        );
        _expectGlobalRecentListAbsent(phase: 'αναπτυγμένη, επανακλείσιμο');

        reporter.logStep('Εκκαθάριση — συμπτυγμένη, διακόπτης κάτω δεξιά');
        final clearFinder = find.widgetWithText(OutlinedButton, 'Εκκαθάριση');
        await tester.tap(clearFinder);
        await pumpUntilSettled(tester);
        await tester.pump(const Duration(milliseconds: 500));

        expect(
          container.read(callsScreenIsExpandedProvider),
          isFalse,
          reason: greekExpectMsg('Μετά Εκκαθάριση → συμπτυγμένη'),
        );
        _expectToggleAnchoredBottomRight(
          tester,
          phase: 'μετά Εκκαθάριση',
        );

        reporter.recordPass(
          'ΤΚ: κλειστή κάτω δεξιά, ανοιχτή expanded στο slot πλάνου',
        );

        await tester.pump(const Duration(seconds: 11));
      },
      semanticsEnabled: false,
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}
