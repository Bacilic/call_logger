// Provider test: πολυβηματική ροή Lansweeper (submitTicketWorkflow) χωρίς δίκτυο.
//
//   flutter test test/features/history/lansweeper_sync_workflow_provider_test.dart

import 'dart:convert';

import 'package:call_logger/core/database/calls_lansweeper_repository.dart';
import 'package:call_logger/core/database/calls_repository.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/services/lansweeper_sync_service.dart';
import 'package:call_logger/features/calls/models/call_model.dart';
import 'package:call_logger/features/calls/models/call_refined_source.dart';
import 'package:call_logger/features/history/models/lansweeper_submit_progress.dart';
import 'package:call_logger/features/history/models/lansweeper_sync_state.dart';
import 'package:call_logger/features/history/providers/lansweeper_submit_progress_provider.dart';
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

class _TicketGoneOncePoster extends _RecordingPoster {
  bool _answeredGone = false;

  @override
  Future<LansweeperRawResponse> call(
    String action,
    Map<String, String> fields,
  ) async {
    if (!_answeredGone && action == 'AddNote') {
      _answeredGone = true;
      calls.add((action: action, fields: Map<String, String>.from(fields)));
      return const LansweeperRawResponse(
        200,
        '{"Success":false,"Message":"No ticket found. The creation was unsuccessful"}',
      );
    }
    return super.call(action, fields);
  }
}

class _StateStepFailsPoster extends _RecordingPoster {
  @override
  Future<LansweeperRawResponse> call(
    String action,
    Map<String, String> fields,
  ) async {
    if (action == 'EditTicket') {
      calls.add((action: action, fields: Map<String, String>.from(fields)));
      return const LansweeperRawResponse(
        200,
        '{"Success":false,"Message":"αποτυχία"}',
      );
    }
    return super.call(action, fields);
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
  refinedSource: CallRefinedSource.ai,
  agentUsername: r'CORP\agent',
  durationSeconds: 300,
);

Future<int> _seedWorkflowCall({String? lansweeperMainTicketId}) async {
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
        expect(poster.calls.map((c) => c.action).toList(), [
          'AddTicket',
          'AddNote',
          'EditTicket',
        ]);

        final db = await DatabaseHelper.instance.database;
        final call = await CallsRepository(db).getCallById(callId);
        expect(call!.lansweeperState, LansweeperSyncState.sent);
        expect(call.lansweeperMainTicketId, _kFakeTicketId);
      },
    );

    test(
      'Μετά την επιτυχή υποβολή το κείμενο του ticket γράφεται στην κλήση, χωρίς να αντικαταστήσει το ωμό issue',
      () async {
        final callId = await _seedWorkflowCall();
        final container = _workflowTestContainer(poster);
        addTearDown(container.dispose);

        container.listen(lansweeperSyncProvider, (_, _) {});

        await container
            .read(lansweeperSyncProvider.notifier)
            .submitCall(callId: callId, input: _kDefaultSubmitInput);

        final db = await DatabaseHelper.instance.database;
        final call = await CallsRepository(db).getCallById(callId);
        // Νέο συμβόλαιο (v43): το κείμενο του ticket ΑΝΤΙΚΑΘΙΣΤΑ την Περιγραφή.
        expect(call!.issue, _kDefaultSubmitInput.notes);
        expect(call.solution, _kDefaultSubmitInput.solution);
        expect(call.refinedSource, CallRefinedSource.ai);
      },
    );

    test(
      'Οι συνοδές κλήσεις του ίδιου ticket παίρνουν κι αυτές το κείμενο',
      () async {
        final callId = await _seedWorkflowCall();
        final companionId = await _seedWorkflowCall();
        final container = _workflowTestContainer(poster);
        addTearDown(container.dispose);

        container.listen(lansweeperSyncProvider, (_, _) {});

        await container
            .read(lansweeperSyncProvider.notifier)
            .submitCall(
              callId: callId,
              input: _kDefaultSubmitInput,
              companionCallIds: <int>[companionId],
            );

        final db = await DatabaseHelper.instance.database;
        final companion = await CallsRepository(db).getCallById(companionId);
        expect(companion!.issue, _kDefaultSubmitInput.notes);
        expect(companion.solution, _kDefaultSubmitInput.solution);
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
        final links = await CallsLansweeperRepository(
          db,
        ).getCallExternalLinks(callId, provider: 'lansweeper');
        expect(links, isNotEmpty);

        final metadata =
            jsonDecode(links.first['metadata'] as String)
                as Map<String, dynamic>;
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
        expect(poster.calls.map((call) => call.fields['TicketID']).toSet(), {
          _kExistingTicketId,
        });
        expect(poster.calls.any((call) => call.action == 'AddTicket'), isFalse);

        final db = await DatabaseHelper.instance.database;
        final call = await CallsRepository(db).getCallById(callId);
        expect(call!.lansweeperMainTicketId, _kExistingTicketId);
      },
    );

    test(
      'κρατημένο αίτημα που σβήστηκε από το Lansweeper: η αποτυχία λέει «δεν βρέθηκε», η αποστολή ως νέο ανοίγει νέο αίτημα και το παλιό μένει στο ιστορικό',
      () async {
        final gonePoster = _TicketGoneOncePoster();
        final callId = await _seedWorkflowCall(
          lansweeperMainTicketId: _kExistingTicketId,
        );
        final container = _workflowTestContainer(gonePoster);
        addTearDown(container.dispose);
        container.listen(lansweeperSyncProvider, (_, _) {});
        final notifier = container.read(lansweeperSyncProvider.notifier);

        final failed = await notifier.submitCall(
          callId: callId,
          input: _kDefaultSubmitInput,
        );
        expect(failed.success, isFalse);
        expect(failed.ticketNotFound, isTrue);

        final retried = await notifier.submitCall(
          callId: callId,
          input: _kDefaultSubmitInput.asNewTicket(),
        );
        expect(retried.success, isTrue);
        expect(retried.ticketCreated, isTrue);
        expect(retried.ticketId, _kFakeTicketId);
        expect(
          gonePoster.calls.where((call) => call.action == 'AddTicket'),
          hasLength(1),
        );

        final db = await DatabaseHelper.instance.database;
        final call = await CallsRepository(db).getCallById(callId);
        expect(call!.lansweeperMainTicketId, _kFakeTicketId);
        expect(call.lansweeperState, LansweeperSyncState.sent);
        final history = await CallsLansweeperRepository(
          db,
        ).getCallExternalLinks(callId, provider: 'lansweeper');
        expect(
          history.map((row) => row['external_id']),
          containsAll(<String>[_kExistingTicketId, _kFakeTicketId]),
        );
      },
    );

    test(
      'αποτυχία στην αλλαγή κατάστασης: η πορεία σημειώνει ✗ στην κατάσταση, και η αποθήκευση δεν ξεκινά καν',
      () async {
        final callId = await _seedWorkflowCall(
          lansweeperMainTicketId: _kExistingTicketId,
        );
        final container = _workflowTestContainer(_StateStepFailsPoster());
        addTearDown(container.dispose);
        container.listen(lansweeperSyncProvider, (_, _) {});

        final result = await container
            .read(lansweeperSyncProvider.notifier)
            .submitCall(callId: callId, input: _kDefaultSubmitInput);
        expect(result.success, isFalse);

        final steps = {
          for (final step
              in container.read(lansweeperSubmitProgressProvider).steps)
            step.key: step.status,
        };
        expect(
          steps[LansweeperSubmitStepKeys.note],
          LansweeperSubmitStepStatus.done,
        );
        expect(
          steps[LansweeperSubmitStepKeys.state],
          LansweeperSubmitStepStatus.failed,
        );
        expect(
          steps[LansweeperSubmitStepKeys.save],
          LansweeperSubmitStepStatus.pending,
        );
      },
    );

    test(
      'δεύτερη αποστολή στο ίδιο αίτημα: φεύγει μόνο ο τίτλος που άλλαξε στη φόρμα',
      () async {
        final callId = await _seedWorkflowCall();
        final container = _workflowTestContainer(poster);
        addTearDown(container.dispose);
        container.listen(lansweeperSyncProvider, (_, _) {});
        final notifier = container.read(lansweeperSyncProvider.notifier);

        await notifier.submitCall(callId: callId, input: _kDefaultSubmitInput);
        poster.calls.clear();
        final result = await notifier.submitCall(
          callId: callId,
          input: const LansweeperSubmitInput(
            title: 'Αλλαγμένος τίτλος',
            notes: 'Πρόβλημα δοκιμής',
            solution: 'Λύση δοκιμής.',
            refinedSource: CallRefinedSource.ai,
            agentUsername: r'CORP\agent',
          ),
        );

        expect(result.success, isTrue);
        final details = poster.calls.first;
        expect(details.action, 'EditTicket');
        expect(details.fields['TicketID'], _kFakeTicketId);
        expect(details.fields['Subject'], 'Αλλαγμένος τίτλος');
        expect(details.fields.containsKey('Description'), isFalse);
      },
    );

    test(
      'παλιό αίτημα χωρίς καταγραφή: συγκρίνεται με τα κείμενα της κλήσης — αμετάβλητα δεν στέλνονται, αλλαγμένο πρόβλημα στέλνεται',
      () async {
        final callId = await _seedWorkflowCall(
          lansweeperMainTicketId: _kExistingTicketId,
        );
        final container = _workflowTestContainer(poster);
        addTearDown(container.dispose);
        container.listen(lansweeperSyncProvider, (_, _) {});
        final notifier = container.read(lansweeperSyncProvider.notifier);

        // Η φόρμα όπως την προσυμπληρώνει η κλήση: αυτόματος τίτλος και το
        // πρόβλημά της.
        await notifier.submitCall(
          callId: callId,
          input: const LansweeperSubmitInput(
            title: '',
            notes: _kWorkflowTestMarker,
            solution: 'Λύση δοκιμής.',
            refinedSource: CallRefinedSource.ai,
            agentUsername: r'CORP\agent',
          ),
        );
        expect(poster.calls.map((c) => c.action), ['AddNote', 'EditTicket']);
        expect(poster.calls.last.fields.containsKey('Description'), isFalse);

        poster.calls.clear();
        await notifier.submitCall(
          callId: callId,
          input: const LansweeperSubmitInput(
            title: '',
            notes: 'Νέο πρόβλημα',
            solution: 'Λύση δοκιμής.',
            refinedSource: CallRefinedSource.ai,
            agentUsername: r'CORP\agent',
          ),
        );
        final details = poster.calls.first;
        expect(details.action, 'EditTicket');
        expect(details.fields['Description'], 'Νέο πρόβλημα');
        expect(details.fields.containsKey('Subject'), isFalse);
      },
    );

    test(
      'αίτημα που δεν είναι της κλήσης (π.χ. εκκρεμότητας): τίτλος και πρόβλημα δεν στέλνονται ποτέ',
      () async {
        final callId = await _seedWorkflowCall(
          lansweeperMainTicketId: _kExistingTicketId,
        );
        final container = _workflowTestContainer(poster);
        addTearDown(container.dispose);
        container.listen(lansweeperSyncProvider, (_, _) {});

        await container
            .read(lansweeperSyncProvider.notifier)
            .submitCall(
              callId: callId,
              input: const LansweeperSubmitInput(
                title: 'Νέος τίτλος',
                notes: 'Νέο πρόβλημα',
                solution: 'Λύση δοκιμής.',
                refinedSource: CallRefinedSource.ai,
                agentUsername: r'CORP\agent',
                attachToTicketId: '777',
              ),
            );

        expect(poster.calls.map((c) => c.action), ['AddNote', 'EditTicket']);
        expect(
          poster.calls.any((c) => c.fields.containsKey('Subject')),
          isFalse,
        );
      },
    );

    test(
      'Κενός agentUsername → success=false, καμία αλλαγή κατάστασης κλήσης (παραμένει unsent)',
      () async {
        final callId = await _seedWorkflowCall();
        final container = _workflowTestContainer(poster);
        addTearDown(container.dispose);

        container.listen(lansweeperSyncProvider, (_, _) {});

        final result = await container
            .read(lansweeperSyncProvider.notifier)
            .submitCall(
              callId: callId,
              input: const LansweeperSubmitInput(
                title: 'Τίτλος',
                notes: 'Πρόβλημα',
                solution: 'Λύση',
                refinedSource: CallRefinedSource.ai,
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
