// Widget test: αναζήτηση στην οθόνη Ιστορικού (μετά από seed κλήσης).
//
// Ολόκληρο αρχείο:
//   flutter test test/features/history/history_search_test.dart

import 'package:call_logger/core/database/calls_repository.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:call_logger/features/history/providers/history_provider.dart';
import 'package:call_logger/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/misc.dart' show Override;

import '../../test_reporter.dart';
import '../../test_setup.dart';

Map<String, dynamic> _seededHistorySearchRow() {
  return {
    'id': 1,
    'date': '2026-06-27',
    'time': '10:00',
    'issue': '$kTestHistorySearchMarker ιστορικό αναζήτηση',
    'phone_text': kTestPhoneDigits,
    'user_phone': kTestPhoneDigits,
    'user_first_name': '',
    'user_last_name': '',
    'user_department': '-',
    'equipment_code': '-',
    'category': '',
    'duration': null,
    'caller_is_deleted': 0,
    'equipment_is_deleted': 0,
    'category_is_deleted': 0,
  };
}

List<Override> historySearchWidgetTestOverrides() {
  final seededRow = _seededHistorySearchRow();
  return [
    ...callLoggerTestProviderOverrides(),
    totalCallsCountProvider.overrideWith((ref) async => 1),
    historyCategoryDateCallCountProvider.overrideWith((ref) async => 1),
    historyCategoriesProvider.overrideWith((ref) async => <String>[]),
    historyCallsProvider.overrideWith((ref) async {
      final keyword = ref.watch(historyFilterProvider).keyword.trim();
      if (keyword.isEmpty) {
        return [seededRow];
      }
      final normalized = SearchTextNormalizer.normalizeForSearch(keyword);
      if (normalized.contains('test ell marker')) {
        return [seededRow];
      }
      return [];
    }),
  ];
}

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  group('Αναζήτηση Ιστορικού (widget)', () {
    setUpAll(() async {
      await seedTestCallRowForHistorySearch();
      LookupService.instance.resetForReload();
      await LookupService.instance.loadFromDatabase();
      final db = await DatabaseHelper.instance.database;
      final rows = await CallsRepository(db).getHistoryCalls(
        keyword: SearchTextNormalizer.normalizeForSearch(
          kTestHistorySearchMarker,
        ),
      );
      expect(rows, isNotEmpty, reason: 'Seed κλήσης για αναζήτηση ιστορικού');
    });

    // Μετάβαση στο Ιστορικό, αναζήτηση με marker seed — εμφάνιση γραμμής στον πίνακα.
    //   flutter test test/features/history/history_search_test.dart --plain-name "Ιστορικό: φίλτρο κειμένου εμφανίζει τη δοκιμαστική κλήση"
    testWidgets(
      'Ιστορικό: φίλτρο κειμένου εμφανίζει τη δοκιμαστική κλήση',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final reporter = GreekTestReportCollector();
        reporter.logStep('Φόρτωση εφαρμογής για αναζήτηση στο Ιστορικό');

        await tester.runAsync(() async {
          await tester.pumpWidget(
            ProviderScope(
              overrides: historySearchWidgetTestOverrides(),
              child: const MyApp(),
            ),
          );
          await tester.pump();
          await pumpUntilSettledLong(tester);
        });

        reporter.logStep('Μετάβαση στο Ιστορικό μέσω πλοήγησης');
        await tester.tap(find.byKey(const ValueKey('nav_rail_history')));
        await pumpUntilSettled(tester);

        expect(
          find.text('Ιστορικό Κλήσεων'),
          findsOneWidget,
          reason: greekExpectMsg('Μετάβαση στην οθόνη Ιστορικού'),
        );

        final container = ProviderScope.containerOf(
          tester.element(find.byType(MaterialApp)),
        );
        reporter.logStep('Εφαρμογή φίλτρου αναζήτησης στο Ιστορικό');
        container.read(historyFilterProvider.notifier).update(
          (s) => s.copyWith(keyword: kTestHistorySearchMarker),
        );
        await pumpUntilSettled(tester);

        expect(
          find.textContaining(kTestHistorySearchMarker),
          findsWidgets,
          reason: greekExpectMsg('Ο πίνακας ιστορικού πρέπει να εμφανίζει το σημείο αναζήτησης'),
        );
        reporter.recordPass('Αναζήτηση στο Ιστορικό');
        await flushCallLoggerSqfliteLockTimers(tester);
      },
      semanticsEnabled: false,
    );
  });
}
