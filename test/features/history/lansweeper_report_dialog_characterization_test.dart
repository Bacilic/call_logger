// Widget test: διάλογος αναφοράς Lansweeper — χαρακτηρισμός split.
//
// Ολόκληρο αρχείο:
//   flutter test test/features/history/lansweeper_report_dialog_characterization_test.dart

import 'package:call_logger/core/database/calls_repository.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/services/gemini_ticket_service.dart';
import 'package:call_logger/features/calls/models/call_model.dart';
import 'package:call_logger/features/history/models/dashboard_date_preset.dart';
import 'package:call_logger/features/history/models/dashboard_filter_model.dart';
import 'package:call_logger/features/history/models/dashboard_summary_model.dart';
import 'package:call_logger/features/history/models/lansweeper_connection_status.dart';
import 'package:call_logger/features/history/models/lansweeper_sync_state.dart';
import 'package:call_logger/features/history/providers/dashboard_provider.dart';
import 'package:call_logger/features/history/providers/lansweeper_connection_probe_provider.dart';
import 'package:call_logger/features/history/widgets/lansweeper_report_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/misc.dart' show Override;

import '../../test_reporter.dart';
import '../../test_setup.dart';

const _kCharRenderMarkerA = 'LS_CHAR_RENDER_A';
const _kCharRenderMarkerB = 'LS_CHAR_RENDER_B';
const _kCharFilterUnsent = 'LS_UNSENT';
const _kCharFilterSent = 'LS_SENT';
const _kCharSelectMarker = 'LS_CHAR_SELECT_ONE';
const _kFakeLansweeperApiUrl = 'https://test.example.com/api.aspx';

const _kEmptyDashboardStats = DashboardSummaryModel(
  totalCalls: 2,
  totalDurationSeconds: 0,
  avgDurationSeconds: 0,
  previousPeriodTotalCalls: 0,
  previousPeriodTotalDurationSeconds: 0,
  previousPeriodAvgDurationSeconds: 0,
  isAllDatesMode: true,
  dailyTrend: <DailyTrendPoint>[],
  sparklineLast7Days: <DailyTrendPoint>[],
  topCallers: <CallerStat>[],
  longestCalls: <LongestCallEntry>[],
  hourlyDistribution: <HourlyBucket>[],
  byDepartment: <DepartmentStat>[],
  byIssue: <IssueStat>[],
);

class _AlwaysAvailableLansweeperConnectionProbe
    extends LansweeperConnectionProbeNotifier {
  @override
  LansweeperConnectionStatus build() => const LansweeperConnectionAvailable();

  @override
  Future<void> ensureCheck() async {}

  @override
  Future<void> check({bool force = true}) async {
    state = const LansweeperConnectionAvailable();
  }
}

class _AllDatesDashboardFilterNotifier extends DashboardFilterNotifier {
  @override
  DashboardFilterModel build() {
    return DashboardDatePreset.applyToFilter(
      const DashboardFilterModel(),
      DashboardDatePreset.all,
    );
  }
}

class _FixedLansweeperApiUrlNotifier extends LansweeperApiUrlNotifier {
  @override
  String build() => _kFakeLansweeperApiUrl;
}

class _FixedLansweeperTicketFormUrlNotifier
    extends LansweeperTicketFormUrlNotifier {
  @override
  String build() => 'https://test.example.com/ticketform.aspx';
}

class _FixedLansweeperTicketViewUrlNotifier
    extends LansweeperTicketViewUrlNotifier {
  @override
  String build() => 'https://test.example.com/ticket.aspx?tid={tid}';
}

class _FixedLansweeperApiKeyNotifier extends LansweeperApiKeyNotifier {
  @override
  String build() => 'test-api-key';
}

class _FixedLansweeperAgentUsernameNotifier
    extends LansweeperAgentUsernameNotifier {
  @override
  String build() => 'test.agent@example.com';
}

class _FixedGeminiApiKeyNotifier extends GeminiApiKeyNotifier {
  @override
  String build() => '';
}

class _FixedGeminiPromptTemplateNotifier extends GeminiPromptTemplateNotifier {
  @override
  String build() => kDefaultGeminiPromptTemplate;
}

class _FixedGeminiEndpointNotifier extends GeminiEndpointNotifier {
  @override
  String build() => kDefaultGeminiEndpoint;
}

class _FixedGeminiPrimaryModelNotifier extends GeminiPrimaryModelNotifier {
  @override
  String build() => '';
}

class _FixedGeminiFallbackEnabledNotifier extends GeminiFallbackEnabledNotifier {
  @override
  bool build() => false;
}

class _FixedGeminiFallbackModelNotifier extends GeminiFallbackModelNotifier {
  @override
  String build() => '';
}

List<Override> _lansweeperCharacterizationOverrides({
  required List<CallModel> reportCalls,
}) {
  return <Override>[
    ...callLoggerTestProviderOverrides(),
    lansweeperConnectionProbeProvider.overrideWith(
      _AlwaysAvailableLansweeperConnectionProbe.new,
    ),
    lansweeperApiUrlProvider.overrideWith(_FixedLansweeperApiUrlNotifier.new),
    lansweeperTicketFormUrlProvider.overrideWith(
      _FixedLansweeperTicketFormUrlNotifier.new,
    ),
    lansweeperTicketViewUrlProvider.overrideWith(
      _FixedLansweeperTicketViewUrlNotifier.new,
    ),
    lansweeperApiKeyProvider.overrideWith(_FixedLansweeperApiKeyNotifier.new),
    lansweeperAgentUsernameProvider.overrideWith(
      _FixedLansweeperAgentUsernameNotifier.new,
    ),
    dashboardFilterProvider.overrideWith(_AllDatesDashboardFilterNotifier.new),
    dashboardStatsProvider.overrideWith((ref) async => _kEmptyDashboardStats),
    dashboardCallsForReportProvider.overrideWith((ref) async => reportCalls),
    geminiApiKeyProvider.overrideWith(_FixedGeminiApiKeyNotifier.new),
    geminiPromptTemplateProvider.overrideWith(
      _FixedGeminiPromptTemplateNotifier.new,
    ),
    geminiEndpointProvider.overrideWith(_FixedGeminiEndpointNotifier.new),
    geminiPrimaryModelProvider.overrideWith(
      _FixedGeminiPrimaryModelNotifier.new,
    ),
    geminiFallbackEnabledProvider.overrideWith(
      _FixedGeminiFallbackEnabledNotifier.new,
    ),
    geminiFallbackModelProvider.overrideWith(
      _FixedGeminiFallbackModelNotifier.new,
    ),
  ];
}

Future<void> _deleteCharacterizationCalls() async {
  final db = await DatabaseHelper.instance.database;
  await db.delete(
    'calls',
    where: 'issue LIKE ?',
    whereArgs: <Object>['%LS_CHAR_%'],
  );
}

Future<List<CallModel>> _seedRenderCalls() async {
  final db = await DatabaseHelper.instance.database;
  final repo = CallsRepository(db);
  final id1 = await repo.insertCall(
    CallModel(
      phoneText: kTestPhoneDigits,
      issue: _kCharRenderMarkerA,
      status: 'completed',
      lansweeperState: LansweeperSyncState.unsent,
    ),
  );
  final id2 = await repo.insertCall(
    CallModel(
      phoneText: kTestPhoneDigits,
      issue: _kCharRenderMarkerB,
      status: 'completed',
      lansweeperState: LansweeperSyncState.unsent,
    ),
  );
  return _loadCallsByIds(<int>[id1, id2]);
}

Future<List<CallModel>> _seedFilterCalls() async {
  final db = await DatabaseHelper.instance.database;
  final repo = CallsRepository(db);
  final unsentId = await repo.insertCall(
    CallModel(
      phoneText: kTestPhoneDigits,
      issue: _kCharFilterUnsent,
      status: 'completed',
      lansweeperState: LansweeperSyncState.unsent,
    ),
  );
  final sentId = await repo.insertCall(
    CallModel(
      phoneText: kTestPhoneDigits,
      issue: _kCharFilterSent,
      status: 'completed',
      lansweeperState: LansweeperSyncState.sent,
    ),
  );
  return _loadCallsByIds(<int>[unsentId, sentId]);
}

Future<List<CallModel>> _seedSelectCall() async {
  final db = await DatabaseHelper.instance.database;
  final repo = CallsRepository(db);
  final id = await repo.insertCall(
    CallModel(
      phoneText: kTestPhoneDigits,
      issue: _kCharSelectMarker,
      status: 'completed',
      lansweeperState: LansweeperSyncState.unsent,
    ),
  );
  return _loadCallsByIds(<int>[id]);
}

Future<List<CallModel>> _loadCallsByIds(List<int> ids) async {
  final db = await DatabaseHelper.instance.database;
  final repo = CallsRepository(db);
  final calls = <CallModel>[];
  for (final id in ids) {
    final call = await repo.getCallById(id);
    if (call != null) calls.add(call);
  }
  return calls;
}

Future<void> _pumpLansweeperReportDialog(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(
          body: LansweeperReportDialog(),
        ),
      ),
    ),
  );
  await tester.pump();
  await pumpUntilSettled(tester, steps: 45, step: const Duration(milliseconds: 60));
}

Finder _immediateSubmitButton() {
  return find.widgetWithText(FilledButton, 'Άμεση Καταχώρηση');
}

Finder _itemCheckboxes() {
  return find.byWidgetPredicate(
    (widget) => widget is Checkbox && widget.tristate != true,
  );
}

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  group('Lansweeper αναφορά — χαρακτηρισμός (widget)', () {
    tearDown(() async {
      await _deleteCharacterizationCalls();
    });

    testWidgets(
      'απόδοση: εμφανίζει κλήσεις από τη βάση στη λίστα',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final reportCalls = await tester.runAsync(_seedRenderCalls) ?? <CallModel>[];
        expect(reportCalls, hasLength(2));

        final container = ProviderContainer(
          overrides: _lansweeperCharacterizationOverrides(
            reportCalls: reportCalls,
          ),
        );
        addTearDown(container.dispose);

        await _pumpLansweeperReportDialog(tester, container);

        expect(find.textContaining('Αναφορά Lansweeper'), findsOneWidget);
        expect(find.textContaining(_kCharRenderMarkerA), findsOneWidget);
        expect(find.textContaining(_kCharRenderMarkerB), findsOneWidget);
        await tester.pump(const Duration(seconds: 11));
      },
      semanticsEnabled: false,
    );

    testWidgets(
      'επιλογή: η αλλαγή επιλογής ενεργοποιεί την Άμεση Καταχώρηση',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final reportCalls = await tester.runAsync(_seedSelectCall) ?? <CallModel>[];
        expect(reportCalls, hasLength(1));

        final container = ProviderContainer(
          overrides: _lansweeperCharacterizationOverrides(
            reportCalls: reportCalls,
          ),
        );
        addTearDown(container.dispose);

        await _pumpLansweeperReportDialog(tester, container);

        final submitButton = _immediateSubmitButton();
        expect(submitButton, findsOneWidget);
        expect(
          tester.widget<FilledButton>(submitButton).onPressed,
          isNull,
          reason: greekExpectMsg(
            'Χωρίς επιλογή η Άμεση Καταχώρηση είναι απενεργοποιημένη',
          ),
        );

        final itemBoxes = _itemCheckboxes();
        expect(itemBoxes, findsWidgets);
        await tester.tap(itemBoxes.first);
        await pumpUntilSettled(tester);

        expect(
          tester.widget<FilledButton>(submitButton).onPressed,
          isNotNull,
          reason: greekExpectMsg(
            'Με επιλεγμένη κλήση η Άμεση Καταχώρηση ενεργοποιείται',
          ),
        );
        expect(find.textContaining('Επιλεγμένες: 1'), findsOneWidget);
        await tester.pump(const Duration(seconds: 11));
      },
      semanticsEnabled: false,
    );

    testWidgets(
      'φίλτρα: τα chips κατάστασης φιλτράρουν τη λίστα',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final reportCalls = await tester.runAsync(_seedFilterCalls) ?? <CallModel>[];
        expect(reportCalls, hasLength(2));

        final container = ProviderContainer(
          overrides: _lansweeperCharacterizationOverrides(
            reportCalls: reportCalls,
          ),
        );
        addTearDown(container.dispose);

        await _pumpLansweeperReportDialog(tester, container);

        expect(find.textContaining(_kCharFilterUnsent), findsOneWidget);
        expect(find.textContaining(_kCharFilterSent), findsNothing);

        await tester.tap(find.text('Καταχωρημένες'));
        await pumpUntilSettled(tester);

        expect(find.textContaining(_kCharFilterUnsent), findsNothing);
        expect(find.textContaining(_kCharFilterSent), findsOneWidget);

        await tester.tap(find.text('Όλες'));
        await pumpUntilSettled(tester);

        expect(find.textContaining(_kCharFilterUnsent), findsOneWidget);
        expect(find.textContaining(_kCharFilterSent), findsOneWidget);
        await tester.pump(const Duration(seconds: 11));
      },
      semanticsEnabled: false,
    );
  });
}
