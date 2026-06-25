// Widget tests: οριζόντιο κεντράρισμα περιεχομένου στήλης σε ευρύ viewport (μη-στενή όψη).
//
//   flutter test test/features/calls/layout/calls_screen_layout_column_centering_test.dart

import 'package:call_logger/core/database/calls_repository.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/features/calls/models/call_model.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:call_logger/features/calls/screens/widgets/equipment_recent_calls_panel.dart';
import 'package:call_logger/features/calls/screens/widgets/mini_map_card.dart';
import 'package:call_logger/features/calls/screens/widgets/user_info_card.dart';
import 'package:call_logger/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../test_reporter.dart';
import '../../../test_setup.dart';

/// Ανοχή οριζόντιας απόκλισης κέντρου περιεχομένου από κέντρο διαδρόμου (px).
const double kColumnCenteringTolerance = 12;

Future<void> _pumpExpandedCallsScreen(
  WidgetTester tester, {
  Size viewport = const Size(2000, 1000),
}) async {
  tester.view.physicalSize = viewport;
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

  final phoneField = callLoggerPhoneTextField();
  await tester.tap(phoneField);
  await pumpUntilSettled(tester);
  await tester.enterText(phoneField, kTestPhoneDigits);
  await tester.pump();
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pump(const Duration(milliseconds: 300));
  await pumpUntilSettled(tester, steps: 40, step: const Duration(milliseconds: 60));
}

Future<void> _seedRecentCallsForCardPanels() async {
  final db = await DatabaseHelper.instance.database;
  final users = await db.query('users', limit: 1);
  final equipment = await db.query('equipment', limit: 1);
  final userId = users.first['id'] as int;
  final equipmentId = equipment.first['id'] as int;
  final repo = CallsRepository(db);
  await repo.insertCall(
    CallModel(
      callerId: userId,
      phoneText: kTestPhoneDigits,
      issue: 'δοκιμή ιστορικού υπαλλήλου',
      equipmentId: equipmentId,
    ),
  );
}

/// Διάδρομος [Expanded] στη γραμμή πλέγματος (μη-στενή όψη) που φιλοξενεί την κάρτα.
Rect _layoutColumnLaneRect(WidgetTester tester, Finder cardFinder) {
  Element? expandedElement;
  for (final cardElement in cardFinder.evaluate()) {
    cardElement.visitAncestorElements((ancestor) {
      if (ancestor.widget is! Expanded) return true;
      final inLayoutGrid = ancestor
              .findAncestorWidgetOfExactType<SingleChildScrollView>() !=
          null;
      if (!inLayoutGrid) return true;

      Element? rowHost;
      ancestor.visitAncestorElements((rowAncestor) {
        if (rowAncestor.widget is Row) {
          rowHost = rowAncestor;
          return false;
        }
        return true;
      });
      if (rowHost == null) return true;

      expandedElement = ancestor;
      return false;
    });
    if (expandedElement != null) break;
  }

  expect(
    expandedElement,
    isNotNull,
    reason: greekExpectMsg(
      'Η κάρτα πρέπει να βρίσκεται σε στήλη Expanded του πλέγματος (ευρύ viewport)',
    ),
  );

  return tester.getRect(
    find.byElementPredicate((element) => element == expandedElement),
  );
}

void _expectContentHorizontallyCenteredInLane(
  WidgetTester tester,
  Finder cardFinder,
) {
  final cardRect = tester.getRect(cardFinder);
  final laneRect = _layoutColumnLaneRect(tester, cardFinder);

  final leftInset = cardRect.left - laneRect.left;
  final rightInset = laneRect.right - cardRect.right;
  expect(
    (leftInset - rightInset).abs(),
    lessThan(kColumnCenteringTolerance),
    reason: greekExpectMsg(
      'Το περιεχόμενο πρέπει να κεντράρεται οριζόντια μέσα στον ισόποσο διάδρομο',
    ),
  );

  expect(
    cardRect.top - laneRect.top,
    lessThan(16),
    reason: greekExpectMsg(
      'Το περιεχόμενο παραμένει στοιχισμένο στην κορυφή του διαδρόμου',
    ),
  );
}

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  setUpAll(() async {
    await _seedRecentCallsForCardPanels();
  });

  group('ανάπτυγμένο πλέγμα — κεντράρισμα στήλης (ευρύ viewport)', () {
    testWidgets('MiniMapCard: κεντραρισμένη οριζόντια στον διάδρομο στήλης', (
      tester,
    ) async {
      await _pumpExpandedCallsScreen(tester);
      expect(find.byType(MiniMapCard), findsOneWidget);
      await pumpUntilSettled(tester, steps: 20);

      _expectContentHorizontallyCenteredInLane(
        tester,
        find.byType(MiniMapCard),
      );
      await tester.pump(const Duration(seconds: 11));
    }, semanticsEnabled: false);

    testWidgets('UserInfoCard: κεντραρισμένη οριζόντια στον διάδρομο στήλης', (
      tester,
    ) async {
      await _pumpExpandedCallsScreen(tester);
      expect(find.byType(UserInfoCard), findsOneWidget);

      _expectContentHorizontallyCenteredInLane(
        tester,
        find.byType(UserInfoCard),
      );
      await tester.pump(const Duration(seconds: 11));
    }, semanticsEnabled: false);

    testWidgets(
      'EquipmentRecentCallsPanel: κεντραρισμένη οριζόντια στον διάδρομο στήλης',
      (tester) async {
        await _pumpExpandedCallsScreen(tester);
        expect(find.byType(EquipmentRecentCallsPanel), findsOneWidget);

        _expectContentHorizontallyCenteredInLane(
          tester,
          find.byType(EquipmentRecentCallsPanel),
        );
        await tester.pump(const Duration(seconds: 11));
      },
      semanticsEnabled: false,
    );
  });
}
