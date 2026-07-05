// Widget test: Άμεση Καταχώρηση Lansweeper με >1 επιλεγμένες κλήσεις.
//
// Ολόκληρο αρχείο:
//   flutter test test/features/history/lansweeper_report_multi_immediate_submit_test.dart

import 'package:call_logger/core/database/calls_repository.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/features/calls/models/call_model.dart';
import 'package:call_logger/features/history/models/dashboard_summary_model.dart';
import 'package:call_logger/features/history/models/lansweeper_sync_state.dart';
import 'package:call_logger/features/history/providers/dashboard_provider.dart';
import 'package:call_logger/features/history/providers/gemini_settings_provider.dart';
import 'package:call_logger/features/history/providers/lansweeper_connection_probe_provider.dart';
import 'package:call_logger/features/history/providers/lansweeper_settings_provider.dart';
import 'package:call_logger/features/history/providers/lansweeper_sync_provider.dart';
import 'package:call_logger/features/history/widgets/lansweeper_report_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/misc.dart' show Override;

import '../../test_reporter.dart';
import '../../test_setup.dart';
import 'lansweeper_report_test_doubles.dart';

const _kLansweeperMultiSubmitMarker = 'LS_MULTI_SUBMIT_TEST';
const _kFakeLansweeperTicketId = 'TEST-99942';

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

class _RecordingLansweeperSyncNotifier extends LansweeperSyncNotifier {
  final List<int> submittedCallIds = <int>[];
  bool submitFinished = false;

  @override
  Future<LansweeperCommandResult> submitCall({
    required int callId,
    required LansweeperSubmitInput input,
    List<int> companionCallIds = const <int>[],
  }) async {
    submitFinished = false;
    submittedCallIds.add(callId);
    final db = await DatabaseHelper.instance.database;
    final repo = CallsRepository(db);
    await repo.markLansweeperSynced(
      callId: callId,
      ticketId: _kFakeLansweeperTicketId,
      provider: 'lansweeper',
      metadata: const <String, dynamic>{'mode': 'api', 'test': true},
    );
    for (final companionId in companionCallIds) {
      if (companionId == callId) continue;
      await repo.markLansweeperSynced(
        callId: companionId,
        ticketId: _kFakeLansweeperTicketId,
        provider: 'lansweeper',
        metadata: <String, dynamic>{
          'mode': 'api_batch',
          'test': true,
          'primaryCallId': callId,
        },
      );
    }
    if (ref.mounted) {
      state = const AsyncData(null);
    }
    submitFinished = true;
    return const LansweeperCommandResult(
      success: true,
      message: 'Mock Lansweeper API OK',
      ticketId: _kFakeLansweeperTicketId,
    );
  }
}

List<Override> _lansweeperMultiSubmitTestOverrides({
  required _RecordingLansweeperSyncNotifier syncNotifier,
  required List<CallModel> reportCalls,
}) {
  return <Override>[
    ...callLoggerTestProviderOverrides(),
    lansweeperConnectionProbeProvider.overrideWith(
      AlwaysAvailableLansweeperConnectionProbe.new,
    ),
    lansweeperApiUrlProvider.overrideWith(FixedLansweeperApiUrlNotifier.new),
    lansweeperTicketFormUrlProvider.overrideWith(
      FixedLansweeperTicketFormUrlNotifier.new,
    ),
    lansweeperTicketViewUrlProvider.overrideWith(
      FixedLansweeperTicketViewUrlNotifier.new,
    ),
    lansweeperApiKeyProvider.overrideWith(FixedLansweeperApiKeyNotifier.new),
    lansweeperAgentUsernameProvider.overrideWith(
      FixedLansweeperAgentUsernameNotifier.new,
    ),
    dashboardFilterProvider.overrideWith(AllDatesDashboardFilterNotifier.new),
    dashboardStatsProvider.overrideWith((ref) async => _kEmptyDashboardStats),
    dashboardCallsForReportProvider.overrideWith((ref) async => reportCalls),
    geminiApiKeyProvider.overrideWith(FixedGeminiApiKeyNotifier.new),
    geminiPromptTemplateProvider.overrideWith(
      FixedGeminiPromptTemplateNotifier.new,
    ),
    geminiEndpointProvider.overrideWith(FixedGeminiEndpointNotifier.new),
    geminiPrimaryModelProvider.overrideWith(
      FixedGeminiPrimaryModelNotifier.new,
    ),
    geminiFallbackEnabledProvider.overrideWith(
      FixedGeminiFallbackEnabledNotifier.new,
    ),
    geminiFallbackModelProvider.overrideWith(
      FixedGeminiFallbackModelNotifier.new,
    ),
    lansweeperSyncProvider.overrideWith(() => syncNotifier),
  ];
}

Future<List<int>> _seedLansweeperMultiSubmitCalls() async {
  final db = await DatabaseHelper.instance.database;
  final repo = CallsRepository(db);
  final id1 = await repo.insertCall(
    CallModel(
      phoneText: kTestPhoneDigits,
      issue: '$_kLansweeperMultiSubmitMarker A',
      status: 'completed',
      lansweeperState: LansweeperSyncState.unsent,
    ),
  );
  final id2 = await repo.insertCall(
    CallModel(
      phoneText: kTestPhoneDigits,
      issue: '$_kLansweeperMultiSubmitMarker B',
      status: 'completed',
      lansweeperState: LansweeperSyncState.unsent,
    ),
  );
  return <int>[id1, id2];
}

Future<List<CallModel>> _loadSeededReportCalls(List<int> callIds) async {
  final db = await DatabaseHelper.instance.database;
  final repo = CallsRepository(db);
  final calls = <CallModel>[];
  for (final id in callIds) {
    final call = await repo.getCallById(id);
    if (call != null) {
      calls.add(call);
    }
  }
  return calls;
}

Future<void> _deleteLansweeperMultiSubmitCalls() async {
  final db = await DatabaseHelper.instance.database;
  await db.delete(
    'calls',
    where: 'issue LIKE ?',
    whereArgs: <Object>['%$_kLansweeperMultiSubmitMarker%'],
  );
}

Finder _groupSelectAllCheckbox() {
  return find.byWidgetPredicate(
    (widget) => widget is CheckboxListTile && widget.tristate == true,
  );
}

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  group('Lansweeper αναφορά — Άμεση Καταχώρηση πολλαπλών κλήσεων', () {
    late List<int> callIds;
    late List<CallModel> reportCalls;
    late _RecordingLansweeperSyncNotifier syncNotifier;

    setUp(() async {
      syncNotifier = _RecordingLansweeperSyncNotifier();
      callIds = await _seedLansweeperMultiSubmitCalls();
      reportCalls = await _loadSeededReportCalls(callIds);
      expect(reportCalls, hasLength(2));
    });

    tearDown(() async {
      await _deleteLansweeperMultiSubmitCalls();
    });

    testWidgets(
      'Άμεση Καταχώρηση: όλες οι επιλεγμένες κλήσεις παίρνουν το ίδιο ticket_id',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final reporter = GreekTestReportCollector();
        addTearDown(
          () => reporter.printFinalSummary(
            title: 'Lansweeper — μαζική Άμεση Καταχώρηση',
          ),
        );

        final container = ProviderContainer(
          overrides: _lansweeperMultiSubmitTestOverrides(
            syncNotifier: syncNotifier,
            reportCalls: reportCalls,
          ),
        );
        addTearDown(container.dispose);

        reporter.logStep('Άνοιγμα διαλόγου αναφοράς Lansweeper');

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
        await pumpUntilSettledLong(tester);

        expect(
          find.textContaining('Αναφορά Lansweeper'),
          findsOneWidget,
          reason: greekExpectMsg('Ο διάλογος αναφοράς Lansweeper φορτώνει'),
        );
        reporter.logStepDone('Διάλογος φορτώθηκε με δύο κλήσεις');

        reporter.logStep('Επιλογή και των δύο κλήσεων (ομαδικό checkbox)');

        final groupCheckbox = _groupSelectAllCheckbox();
        expect(
          groupCheckbox,
          findsOneWidget,
          reason: greekExpectMsg(
            'Υπάρχει ομαδικό checkbox για επιλογή όλων των κλήσεων του καλούντα',
          ),
        );
        await tester.tap(groupCheckbox);
        await pumpUntilSettled(tester);

        expect(
          find.textContaining('Επιλεγμένες: 2'),
          findsOneWidget,
          reason: greekExpectMsg('Επιλέχθηκαν και οι δύο κλήσεις'),
        );

        final immediateSubmitButton = find.widgetWithText(
          FilledButton,
          'Άμεση Καταχώρηση',
        );
        expect(
          immediateSubmitButton,
          findsOneWidget,
          reason: greekExpectMsg('Το κουμπί Άμεση Καταχώρηση είναι ορατό'),
        );
        expect(
          tester.widget<FilledButton>(immediateSubmitButton).onPressed,
          isNotNull,
          reason: greekExpectMsg(
            'Το κουμπί Άμεση Καταχώρηση είναι ενεργό με έγκυρες ρυθμίσεις API',
          ),
        );
        reporter.logStepDone('Και οι δύο κλήσεις επιλέχθηκαν');

        reporter.logStep(
          'Πάτημα Άμεση Καταχώρηση (mock API, χωρίς πραγματικό ticket)',
        );

        await tester.runAsync(() async {
          await tester.tap(immediateSubmitButton);
          await tester.pump();
          final deadline = DateTime.now().add(const Duration(seconds: 5));
          while (!syncNotifier.submitFinished &&
              DateTime.now().isBefore(deadline)) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
            await tester.pump(const Duration(milliseconds: 20));
          }
        });
        expect(
          syncNotifier.submitFinished,
          isTrue,
          reason: greekExpectMsg(
            'Η Άμεση Καταχώρηση Lansweeper ολοκληρώθηκε',
          ),
        );
        await pumpUntilSettled(tester);

        expect(
          syncNotifier.submittedCallIds,
          hasLength(1),
          reason: greekExpectMsg(
            'Η κλήση API Lansweeper πρέπει να γίνεται μία φορά για όλες τις επιλεγμένες κλήσεις',
          ),
        );
        reporter.logStepDone(
          'Mock API κλήθηκε μία φορά (ticket $_kFakeLansweeperTicketId)',
        );

        reporter.logStep('Έλεγχος κατάστασης και ticket_id στη βάση');

        final loadedCalls = await tester.runAsync(() async {
          final db = await DatabaseHelper.instance.database;
          final repo = CallsRepository(db);
          return Future.wait(callIds.map(repo.getCallById));
        });
        expect(loadedCalls, isNotNull);

        for (final call in loadedCalls!) {
          expect(
            call,
            isNotNull,
            reason: greekExpectMsg('Η κλήση ${call?.id} υπάρχει στη βάση'),
          );
          expect(
            call!.lansweeperState,
            LansweeperSyncState.sent,
            reason: greekExpectMsg(
              'Η κλήση #${call.id} πρέπει να επισημαίνεται ως καταχωρημένη',
            ),
          );
          expect(
            call.lansweeperMainTicketId,
            _kFakeLansweeperTicketId,
            reason: greekExpectMsg(
              'Η κλήση #${call.id} πρέπει να έχει το ίδιο ticket_id με τις υπόλοιπες',
            ),
          );
        }

        reporter.recordPass(
          'Όλες οι επιλεγμένες κλήσεις καταχωρήθηκαν με κοινό ticket_id',
        );
        await tester.pump(const Duration(seconds: 11));
      },
      semanticsEnabled: false,
    );
  });
}
