// Widget tests: ανώτατο πλάτος στήλης πλέγματος ανά κάρτα (μη-στενή όψη).
//
//   flutter test test/features/calls/layout/calls_screen_layout_column_width_test.dart

import 'package:call_logger/core/database/calls_repository.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/features/calls/layout/calls_screen_layout.dart';
import 'package:call_logger/features/calls/models/call_model.dart';
import 'package:call_logger/features/calls/provider/calls_dashboard_providers.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:call_logger/features/calls/screens/calls_screen.dart';
import 'package:call_logger/features/calls/screens/widgets/equipment_recent_calls_panel.dart';
import 'package:call_logger/features/calls/screens/widgets/global_recent_calls_list.dart';
import 'package:call_logger/features/calls/screens/widgets/mini_map_card.dart';
import 'package:call_logger/features/calls/screens/widgets/recent_calls_list.dart';
import 'package:call_logger/features/calls/screens/widgets/user_info_card.dart';
import 'package:call_logger/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../test_reporter.dart';
import '../../../test_setup.dart';

/// Ανοχή στρογγυλοποίησης/layout (px).
const double kColumnWidthTolerance = 6;

/// Ελάχιστο πλάτος στήλης σε ευρύ viewport πριν το cap (αναπαράγει το σύμπτωμα).
const double kWideViewportMinColumnWidth = 420;

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
      status: 'completed',
      date: '2026-06-20',
      time: '10:00',
    ),
  );
  await repo.insertCall(
    CallModel(
      equipmentId: equipmentId,
      equipmentText: kTestEquipmentCode,
      phoneText: kTestPhoneDigits,
      issue: 'δοκιμή ιστορικού εξοπλισμού',
      status: 'completed',
      date: '2026-06-21',
      time: '11:00',
    ),
  );
}

Future<void> _openGlobalRecentCard(WidgetTester tester) async {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(CallsScreen)),
  );
  await tester.runAsync(() async {
    await container
        .read(showGlobalCallsToggleProvider.notifier)
        .setVisible(true);
  });
  await pumpUntilSettled(tester, steps: 40, step: const Duration(milliseconds: 60));
}

/// Πλάτος της capped στήλης πλέγματος (ConstrainedBox μέσα στο [_LayoutColumnWidthCap]).
double _layoutColumnHostWidth(WidgetTester tester, Finder cardFinder) {
  Element? layoutBuilder;
  final cardElement = tester.element(cardFinder);
  cardElement.visitAncestorElements((ancestor) {
    if (ancestor.widget is LayoutBuilder &&
        ancestor.findAncestorWidgetOfExactType<SingleChildScrollView>() !=
            null) {
      layoutBuilder = ancestor;
      return false;
    }
    return true;
  });

  expect(
    layoutBuilder,
    isNotNull,
    reason: greekExpectMsg(
      'Η κάρτα πρέπει να βρίσκεται μέσα σε capped στήλη πλέγματος',
    ),
  );

  Element? columnCap;
  void walkCap(Element element) {
    if (columnCap != null) return;
    if (element.widget is ConstrainedBox) {
      final maxW = (element.widget as ConstrainedBox).constraints.maxWidth;
      if (maxW.isFinite && maxW <= 600) {
        columnCap = element;
        return;
      }
    }
    element.visitChildren(walkCap);
  }

  walkCap(layoutBuilder!);

  expect(
    columnCap,
    isNotNull,
    reason: greekExpectMsg('Αναμενόταν ConstrainedBox πλάτους στήλης πλέγματος'),
  );

  final box = columnCap!.renderObject;
  expect(box, isA<RenderBox>());
  return (box! as RenderBox).size.width;
}

void _expectColumnWidthAtMost(
  WidgetTester tester,
  Finder cardFinder,
  double maxWidth, {
  required String cardLabel,
}) {
  final width = _layoutColumnHostWidth(tester, cardFinder);
  expect(
    width,
    lessThanOrEqualTo(maxWidth + kColumnWidthTolerance),
    reason: greekExpectMsg(
      'Η στήλη της κάρτας $cardLabel δεν πρέπει να ξεπερνά $maxWidth px',
    ),
  );
}

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  setUpAll(() async {
    await _seedRecentCallsForCardPanels();
  });

  group('ανάπτυγμένο πλέγμα — max πλάτος στήλης ανά κάρτα', () {
    testWidgets('MiniMapCard: η στήλη δεν ξεπερνά το πλάτος χάρτη', (
      tester,
    ) async {
      await _pumpExpandedCallsScreen(tester);

      expect(find.byType(MiniMapCard), findsOneWidget);
      await pumpUntilSettled(tester, steps: 20);

      _expectColumnWidthAtMost(
        tester,
        find.byType(MiniMapCard),
        CallsScreenLayout.kMapCardColumnMaxWidth,
        cardLabel: 'MiniMapCard',
      );
      await tester.pump(const Duration(seconds: 11));
    }, semanticsEnabled: false);

    testWidgets('UserInfoCard: η στήλη δεν ξεπερνά το max πλάτος κάρτας', (
      tester,
    ) async {
      await _pumpExpandedCallsScreen(tester);

      expect(find.byType(UserInfoCard), findsOneWidget);

      _expectColumnWidthAtMost(
        tester,
        find.byType(UserInfoCard),
        CallsScreenLayout.kRecentCallsCardColumnMaxWidth,
        cardLabel: 'UserInfoCard (στοίβα caller+ιστορικό)',
      );
      await tester.pump(const Duration(seconds: 11));
    }, semanticsEnabled: false);

    testWidgets('RecentCallsList: η στήλη δεν ξεπερνά το max πλάτος κάρτας', (
      tester,
    ) async {
      await _pumpExpandedCallsScreen(tester);

      expect(find.byType(RecentCallsList), findsOneWidget);
      await pumpUntilSettled(tester, steps: 20);

      _expectColumnWidthAtMost(
        tester,
        find.byType(RecentCallsList),
        CallsScreenLayout.kRecentCallsCardColumnMaxWidth,
        cardLabel: 'RecentCallsList',
      );
      await tester.pump(const Duration(seconds: 11));
    }, semanticsEnabled: false);

    testWidgets(
      'GlobalRecentCallsList: η στήλη δεν ξεπερνά το max πλάτος κάρτας',
      (tester) async {
        await _pumpExpandedCallsScreen(tester);
        await _openGlobalRecentCard(tester);

        expect(find.byType(GlobalRecentCallsList), findsOneWidget);
        await pumpUntilSettled(tester, steps: 20);

        _expectColumnWidthAtMost(
          tester,
          find.byType(GlobalRecentCallsList),
          CallsScreenLayout.kGlobalRecentCardColumnMaxWidth,
          cardLabel: 'GlobalRecentCallsList',
        );
        await tester.pump(const Duration(seconds: 11));
      },
      semanticsEnabled: false,
    );

    testWidgets(
      'EquipmentRecentCallsPanel: η στήλη δεν ξεπερνά το max πλάτος κάρτας',
      (tester) async {
        await _pumpExpandedCallsScreen(tester);

        expect(find.byType(EquipmentRecentCallsPanel), findsOneWidget);
        await pumpUntilSettled(tester, steps: 20);

        _expectColumnWidthAtMost(
          tester,
          find.byType(EquipmentRecentCallsPanel),
          CallsScreenLayout.kEquipmentRecentCardColumnMaxWidth,
          cardLabel: 'EquipmentRecentCallsPanel',
        );
        await tester.pump(const Duration(seconds: 11));
      },
      semanticsEnabled: false,
    );

    testWidgets(
      'ευρύ viewport: πριν το cap η στήλη MiniMapCard θα ήταν υπερ-φαρδιά',
      (tester) async {
        await _pumpExpandedCallsScreen(tester);
        expect(find.byType(MiniMapCard), findsOneWidget);

        final columnWidth = _layoutColumnHostWidth(
          tester,
          find.byType(MiniMapCard),
        );
        expect(
          columnWidth,
          lessThan(kWideViewportMinColumnWidth),
          reason: greekExpectMsg(
            'Με cap: η στήλη MiniMapCard δεν πρέπει να παίρνει αναλογικό πλάτος γραμμής',
          ),
        );
        await tester.pump(const Duration(seconds: 11));
      },
      semanticsEnabled: false,
    );

    testWidgets('μεσαίο viewport: στοίβα στήλων αντί οριζόντιου πλέγματος — χωρίς overflow', (
      tester,
    ) async {
      await _pumpExpandedCallsScreen(
        tester,
        viewport: const Size(1150, 900),
      );
      await _openGlobalRecentCard(tester);
      expect(
        tester.takeException(),
        isNull,
        reason: greekExpectMsg(
          'Μεσαίο πλάτος παραθύρου: στοίβα στήλων χωρίς RenderFlex overflow',
        ),
      );
      expect(find.byType(MiniMapCard), findsOneWidget);
      await tester.pump(const Duration(seconds: 11));
    }, semanticsEnabled: false);
  });
}
