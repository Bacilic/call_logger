// Provider test: πολυβηματική ροή Lansweeper (submitTicketWorkflow) χωρίς δίκτυο.
//
//   flutter test test/features/history/lansweeper_sync_workflow_provider_test.dart

import 'dart:convert';

import 'package:call_logger/core/database/calls_repository.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/services/lansweeper_sync_service.dart';
import 'package:call_logger/features/calls/models/call_model.dart';
import 'package:call_logger/features/history/models/lansweeper_sync_state.dart';
import 'package:call_logger/features/history/providers/lansweeper_sync_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_setup.dart';

const _kWorkflowTestMarker = 'LS_WORKFLOW_PROVIDER_TEST';
const _kFakeTicketId = '12345';
const _kExistingTicketId = '555';

class _RecordingPoster {
  final List<({String action, Map<String, String> fields})> calls = [];

  Future<LansweeperRawResponse> call(
    String action,
    Map<String, String> fields,
  ) async {
    calls.add((action: action, fields: Map<String, String>.from(fields)));
    return const LansweeperRawResponse(
      200,
      '{"Success":true,"TicketID":"$_kFakeTicketId"}',
    );
  }
}

ProviderContainer _workflowTestContainer(_RecordingPoster poster) {
  return ProviderContainer(
    overrides: [
      ...callLoggerTestProviderOverrides(),
      lansweeperSyncServiceProvider.overrideWith(
        (ref) => LansweeperSyncService(poster: poster.call),
      ),
    ],
  );
}

const _kDefaultSubmitInput = LansweeperSubmitInput(
  title: 'Τίτλος δοκιμής',
  notes: 'Πρόβλημα δοκιμής',
  solution: 'Λύση δοκιμής.',
  agentUsername: r'CORP\agent',
  durationSeconds: 300,
);

Future<int> _seedWorkflowCall({
  String? lansweeperMainTicketId,
}) async {
  final db = await DatabaseHelper.instance.database;
  final repo = CallsRepository(db);
  return repo.insertCall(
    CallModel(
      phoneText: kTestPhoneDigits,
      issue: _kWorkflowTestMarker,
      status: 'completed',
      lansweeperState: LansweeperSyncState.unsent,
      lansweeperMainTicketId: lansweeperMainTicketId,
    ),
  );
}

Future<void> _deleteWorkflowTestCalls() async {
  final db = await DatabaseHelper.instance.database;
  await db.delete(
    'calls',
    where: 'issue = ?',
    whereArgs: [_kWorkflowTestMarker],
  );
}

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  group('LansweeperSyncNotifier — πολυβηματική ροή submitTicketWorkflow', () {
    late _RecordingPoster poster;

    setUp(() {
      poster = _RecordingPoster();
    });

    tearDown(() async {
      await _deleteWorkflowTestCalls();
    });

    test(
      'Νέα κλήση χωρίς ticketId: το submitCall εκτελεί AddTicket → AddNote → EditTicket με τη σειρά, η κλήση γίνεται sent με ticketId 12345',
      () async {
        final callId = await _seedWorkflowCall();
        final container = _workflowTestContainer(poster);
        addTearDown(container.dispose);

        container.listen(lansweeperSyncProvider, (_, _) {});

        final result = await container
            .read(lansweeperSyncProvider.notifier)
            .submitCall(callId: callId, input: _kDefaultSubmitInput);

        expect(result.success, isTrue);
        expect(result.ticketId, _kFakeTicketId);
        expect(
          poster.calls.map((c) => c.action).toList(),
          ['AddTicket', 'AddNote', 'EditTicket'],
        );

        final db = await DatabaseHelper.instance.database;
        final call = await CallsRepository(db).getCallById(callId);
        expect(call!.lansweeperState, LansweeperSyncState.sent);
        expect(call.lansweeperMainTicketId, _kFakeTicketId);
      },
    );

    test(
      'Στο metadata του external link αποθηκεύονται completedSteps (περιέχει AddTicket, AddNote, EditTicket)',
      () async {
        final callId = await _seedWorkflowCall();
        final container = _workflowTestContainer(poster);
        addTearDown(container.dispose);

        container.listen(lansweeperSyncProvider, (_, _) {});

        await container
            .read(lansweeperSyncProvider.notifier)
            .submitCall(callId: callId, input: _kDefaultSubmitInput);

        final db = await DatabaseHelper.instance.database;
        final links = await CallsRepository(db).getCallExternalLinks(
          callId,
          provider: 'lansweeper',
        );
        expect(links, isNotEmpty);

        final metadata =
            jsonDecode(links.first['metadata'] as String) as Map<String, dynamic>;
        expect(metadata['mode'], 'api_workflow');
        final steps = (metadata['completedSteps'] as List).cast<String>();
        expect(steps, contains('AddTicket'));
        expect(steps, contains('AddNote'));
        expect(steps.any((step) => step.startsWith('EditTicket')), isTrue);
      },
    );

    test(
      'Ιδιοδυναμία: κλήση με προϋπάρχον lansweeperMainTicketId (π.χ. 555) ΠΑΡΑΛΕΙΠΕΙ το AddTicket — το πρώτο καταγεγραμμένο action είναι AddNote και το ticketId παραμένει 555',
      () async {
        final callId = await _seedWorkflowCall(
          lansweeperMainTicketId: _kExistingTicketId,
        );
        final container = _workflowTestContainer(poster);
        addTearDown(container.dispose);

        container.listen(lansweeperSyncProvider, (_, _) {});

        final result = await container
            .read(lansweeperSyncProvider.notifier)
            .submitCall(callId: callId, input: _kDefaultSubmitInput);

        expect(result.success, isTrue);
        expect(result.ticketId, _kExistingTicketId);
        expect(poster.calls, isNotEmpty);
        expect(poster.calls.first.action, 'AddNote');
        expect(poster.calls.first.fields['TicketID'], _kExistingTicketId);
        expect(
          poster.calls.any((call) => call.action == 'AddTicket'),
          isFalse,
        );

        final db = await DatabaseHelper.instance.database;
        final call = await CallsRepository(db).getCallById(callId);
        expect(call!.lansweeperMainTicketId, _kExistingTicketId);
      },
    );

    test(
      'Κενός agentUsername → success=false, καμία αλλαγή κατάστασης κλήσης (παραμένει unsent)',
      () async {
        final callId = await _seedWorkflowCall();
        final container = _workflowTestContainer(poster);
        addTearDown(container.dispose);

        container.listen(lansweeperSyncProvider, (_, _) {});

        final result = await container.read(lansweeperSyncProvider.notifier).submitCall(
              callId: callId,
              input: const LansweeperSubmitInput(
                title: 'Τίτλος',
                notes: 'Πρόβλημα',
                solution: 'Λύση',
                agentUsername: '   ',
              ),
            );

        expect(result.success, isFalse);
        expect(
          result.message,
          'Ο πράκτορας API (AgentUsername) είναι υποχρεωτικός.',
        );
        expect(poster.calls, isEmpty);

        final db = await DatabaseHelper.instance.database;
        final call = await CallsRepository(db).getCallById(callId);
        expect(call!.lansweeperState, LansweeperSyncState.unsent);
      },
    );
  });
}
