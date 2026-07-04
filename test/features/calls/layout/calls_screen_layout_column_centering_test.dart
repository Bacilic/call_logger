// Widget tests: πυκνό πλέγμα σε ευρύ viewport (μη-στενή όψη).
//
// Οι στήλες της γραμμής πακετάρονται κεντραρισμένες με σταθερό κενό (16px)
// αντί για ισόποσους Expanded διαδρόμους που άφηναν μεγάλα νεκρά κενά,
// και οι κάρτες περιεχομένου (π.χ. κάρτα χρήστη) αγκαλιάζουν το περιεχόμενό τους.
//
//   flutter test test/features/calls/layout/calls_screen_layout_column_centering_test.dart

import 'package:call_logger/core/database/calls_repository.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/features/calls/models/call_model.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:call_logger/features/calls/screens/widgets/global_recent_calls_list.dart';
import 'package:call_logger/features/calls/screens/widgets/mini_map_card.dart';
import 'package:call_logger/features/calls/screens/widgets/user_info_card.dart';
import 'package:call_logger/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../test_reporter.dart';
import '../../../test_setup.dart';

/// Μέγιστο αποδεκτό οριζόντιο κενό ανάμεσα σε γειτονικές στήλες πλέγματος (px).
/// Το ονομαστικό κενό είναι 16px — ανοχή για στρογγυλοποιήσεις layout.
const double kMaxAdjacentLaneGap = 28;

/// Ελάχιστο «κέρδος» πλάτους ώστε να αποδεικνύεται ότι η κάρτα αγκαλιάζει
/// το περιεχόμενό της αντί να γεμίζει ολόκληρη τη στήλη (px).
const double kMinHugSlack = 40;

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

/// Στήλη πλέγματος (capped ConstrainedBox του [_LayoutColumnWidthCap]) που
/// φιλοξενεί την κάρτα — επιστρέφει το ορθογώνιό της.
Rect _laneRect(WidgetTester tester, Finder cardFinder) {
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
    final widget = element.widget;
    if (widget is ConstrainedBox && widget.constraints.maxWidth.isFinite ||
        widget is SizedBox && (widget.width ?? double.infinity).isFinite) {
      columnCap = element;
      return;
    }
    element.visitChildren(walkCap);
  }

  walkCap(layoutBuilder!);

  expect(
    columnCap,
    isNotNull,
    reason: greekExpectMsg('Αναμενόταν στήλη πλέγματος με περιορισμό πλάτους'),
  );

  return tester.getRect(
    find.byElementPredicate((element) => element == columnCap),
  );
}

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  setUpAll(() async {
    await _seedRecentCallsForCardPanels();
  });

  group('ανάπτυγμένο πλέγμα — πυκνή διάταξη (ευρύ viewport)', () {
    testWidgets(
      'γειτονικές στήλες: μικρό σταθερό κενό, όχι σκόρπιοι διάδρομοι',
      (tester) async {
        await _pumpExpandedCallsScreen(tester);
        expect(find.byType(UserInfoCard), findsOneWidget);
        expect(find.byType(MiniMapCard), findsOneWidget);
        await pumpUntilSettled(tester, steps: 20);

        final callerLane = _laneRect(tester, find.byType(UserInfoCard));
        final mapLane = _laneRect(tester, find.byType(MiniMapCard));

        // Σειρά στηλών: caller stack αριστερά, χάρτης δεξιά.
        final leftLane = callerLane.left <= mapLane.left ? callerLane : mapLane;
        final rightLane = identical(leftLane, callerLane) ? mapLane : callerLane;

        final gap = rightLane.left - leftLane.right;
        expect(
          gap,
          lessThanOrEqualTo(kMaxAdjacentLaneGap),
          reason: greekExpectMsg(
            'Οι γειτονικές στήλες πρέπει να πακετάρονται με μικρό σταθερό κενό '
            '(βρέθηκε κενό ${gap.toStringAsFixed(1)}px)',
          ),
        );
        await tester.pump(const Duration(seconds: 11));
      },
      semanticsEnabled: false,
    );

    testWidgets(
      'η ομάδα στηλών ξεκινά από αριστερά — ο ελεύθερος χώρος μένει δεξιά',
      (tester) async {
        await _pumpExpandedCallsScreen(tester);
        expect(find.byType(MiniMapCard), findsOneWidget);
        await pumpUntilSettled(tester, steps: 20);

        final lanes = <Rect>[
          _laneRect(tester, find.byType(UserInfoCard)),
          _laneRect(tester, find.byType(MiniMapCard)),
          if (find.byType(GlobalRecentCallsList).evaluate().isNotEmpty)
            _laneRect(tester, find.byType(GlobalRecentCallsList)),
        ];
        final scrollRect = tester.getRect(
          find
              .ancestor(
                of: find.byType(MiniMapCard),
                matching: find.byType(SingleChildScrollView),
              )
              .first,
        );

        final clusterLeft =
            lanes.map((r) => r.left).reduce((a, b) => a < b ? a : b);
        final leftSpace = clusterLeft - scrollRect.left;

        expect(
          leftSpace,
          lessThan(24),
          reason: greekExpectMsg(
            'Η ομάδα στηλών πρέπει να στοιχίζεται αριστερά (χωρίς νεκρό '
            'αριστερό περιθώριο — βρέθηκε ${leftSpace.toStringAsFixed(1)}px)',
          ),
        );
        await tester.pump(const Duration(seconds: 11));
      },
      semanticsEnabled: false,
    );

    testWidgets(
      'κάρτες περιεχομένου: πλάτος από το περιεχόμενο, όχι πλήρωση στήλης',
      (tester) async {
        await _pumpExpandedCallsScreen(tester);
        expect(find.byType(UserInfoCard), findsOneWidget);
        await pumpUntilSettled(tester, steps: 20);

        // Με τα σύντομα δεδομένα δοκιμής, οι κάρτες πρέπει να μένουν πολύ
        // κάτω από το παλιό γέμισμα στήλης (560px) — «έξυπνο» πλάτος.
        final userCardWidth = tester.getSize(find.byType(UserInfoCard)).width;
        expect(
          userCardWidth,
          lessThan(560 - kMinHugSlack),
          reason: greekExpectMsg(
            'Η κάρτα χρήστη πρέπει να αγκαλιάζει το περιεχόμενό της '
            '(βρέθηκε ${userCardWidth.toStringAsFixed(1)}px)',
          ),
        );

        final laneRect = _laneRect(tester, find.byType(UserInfoCard));
        final cardRect = tester.getRect(find.byType(UserInfoCard));
        expect(
          cardRect.top - laneRect.top,
          lessThan(16),
          reason: greekExpectMsg(
            'Το περιεχόμενο παραμένει στοιχισμένο στην κορυφή της στήλης',
          ),
        );
        await tester.pump(const Duration(seconds: 11));
      },
      semanticsEnabled: false,
    );
  });
}
