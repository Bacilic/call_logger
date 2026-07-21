import 'dart:convert';

import 'package:call_logger/core/services/lansweeper_sync_service.dart';
import 'package:call_logger/core/services/lansweeper_ticket_submit_config.dart';
import 'package:call_logger/core/services/settings_service.dart';
import 'package:call_logger/features/calls/models/call_model.dart';
import 'package:flutter_test/flutter_test.dart';

const _kTestApiUrl = 'http://10.10.201.22:81/api.aspx';
const _kTestApiKey = 'test-api-key';

class _RecordingFakePoster {
  _RecordingFakePoster({required this.responses});

  final List<LansweeperRawResponse> responses;
  final List<({String action, Map<String, String> fields})> calls = [];
  int _index = 0;

  Future<LansweeperRawResponse> call(
    String action,
    Map<String, String> fields,
  ) async {
    calls.add((action: action, fields: Map<String, String>.from(fields)));
    if (_index < responses.length) {
      return responses[_index++];
    }
    return const LansweeperRawResponse(200, '{"Success":true}');
  }
}

LansweeperWorkflowRequest _workflowRequest({
  String title = 'Τίτλος δοκιμής',
  String problem = 'Πρόβλημα δοκιμής',
  String solution = 'Λύση δοκιμής.',
  String agentUsername = r'CORP\agent',
  int? durationSeconds = 300,
  LansweeperTicketSubmitConfig? config,
  Map<String, String>? customFieldValues,
  String? targetState = 'Closed',
  String? existingTicketId,
}) {
  return LansweeperWorkflowRequest(
    call: CallModel(id: 42, category: 'IT'),
    title: title,
    problem: problem,
    solution: solution,
    agentUsername: agentUsername,
    durationSeconds: durationSeconds,
    config: config ?? LansweeperTicketSubmitConfig.defaults(),
    customFieldValues: customFieldValues ??
        const {
          'category': 'Yes',
          'incident_category': 'Hardware στα Endpoints (PCs, Printers κλπ.)',
        },
    targetState: targetState,
    existingTicketId: existingTicketId,
  );
}

Map<String, String>? _fieldsForAction(
  _RecordingFakePoster poster,
  String action, {
  int occurrence = 0,
}) {
  var seen = 0;
  for (final call in poster.calls) {
    if (call.action != action) continue;
    if (seen == occurrence) return call.fields;
    seen++;
  }
  return null;
}

void _registerTestLansweeperSettings() {
  final store = <String, String>{
    'lansweeper_api_url': _kTestApiUrl,
    'lansweeper_api_key': _kTestApiKey,
  };
  SettingsService.registerAppSettingsProvider(
    (key) async => store[key],
    (key, value) async {
      store[key] = value;
    },
  );
}

void main() {
  group('LansweeperSyncService.buildTicketDescription', () {
    test('προσθέτει διάρκεια στο τέλος', () {
      final description = LansweeperSyncService.buildTicketDescription(
        notes: 'Πρόβλημα με εκτυπωτή',
        solution: 'Επανεκκίνηση',
        durationSeconds: 125,
      );

      expect(description, contains('Πρόβλημα με εκτυπωτή'));
      expect(description, contains('Λύση:\nΕπανεκκίνηση'));
      expect(description, endsWith('Χρόνος: 02:05'));
    });

    test('χωρίς διάρκεια δεν προσθέτει γραμμή Χρόνος', () {
      final description = LansweeperSyncService.buildTicketDescription(
        notes: 'Σημειώσεις',
        solution: '',
      );

      expect(description, 'Σημειώσεις');
      expect(description, isNot(contains('Χρόνος:')));
    });

    test('formatCallDurationLabel ώρες ως HH:MM', () {
      expect(
        LansweeperSyncService.formatCallDurationLabel(3725),
        '01:02',
      );
    });
  });

  group('LansweeperSyncService.submitTicketWorkflow — golden API σχήμα', () {
    late _RecordingFakePoster fakePoster;
    late LansweeperSyncService service;

    const successWithTicketId = LansweeperRawResponse(
      200,
      '{"Success":true,"TicketID":"17476"}',
    );
    const successOnly = LansweeperRawResponse(200, '{"Success":true}');
    const failure = LansweeperRawResponse(
      200,
      '{"Success":false,"Message":"αποτυχία"}',
    );

    setUp(() {
      _registerTestLansweeperSettings();
      fakePoster = _RecordingFakePoster(
        responses: const [
          successWithTicketId,
          successOnly,
          successOnly,
        ],
      );
      service = LansweeperSyncService(poster: fakePoster.call);
    });

    test(
      'AddTicket: το Description περιέχει ΜΟΝΟ το πρόβλημα (όχι τη λύση) και υπάρχουν Type/Priority/Team από το config',
      () async {
        await service.submitTicketWorkflow(_workflowRequest());

        final fields = _fieldsForAction(fakePoster, 'AddTicket');
        expect(fields, isNotNull);
        expect(fields!['Description'], 'Πρόβλημα δοκιμής');
        expect(fields['Description'], isNot(contains('Λύση')));
        expect(fields['Type'], 'IT Support');
        expect(fields['Priority'], 'Low');
        expect(fields['Team'], 'IT Support');
      },
    );

    test(
      'AddTicket: το CustomFields, μετά από jsonDecode, ισούται με {"customFields":[{"name":"Κατηγορία αιτήματος","value":"Yes"},{"name":"Τί αφορά;","value":"Hardware στα Endpoints (PCs, Printers κλπ.)"}]}',
      () async {
        await service.submitTicketWorkflow(_workflowRequest());

        final fields = _fieldsForAction(fakePoster, 'AddTicket');
        expect(fields, isNotNull);
        final decoded = jsonDecode(fields!['CustomFields']!);
        expect(decoded, {
          'customFields': [
            {'name': 'Κατηγορία αιτήματος', 'value': 'Yes'},
            {
              'name': 'Τί αφορά;',
              'value': 'Hardware στα Endpoints (PCs, Printers κλπ.)',
            },
          ],
        });
        expect(
          (decoded['customFields'][1]['value'] as String).contains(','),
          isTrue,
        );
      },
    );

    test(
      'Πεδία αιτούντος υπάρχουν και στα τρία actions: για agent email → Email+AgentEmail· για agent domain\\username → Username+AgentUsername',
      () async {
        fakePoster = _RecordingFakePoster(
          responses: const [
            successWithTicketId,
            successOnly,
            successOnly,
          ],
        );
        service = LansweeperSyncService(poster: fakePoster.call);

        await service.submitTicketWorkflow(
          _workflowRequest(agentUsername: 'v.drosos@hospkorinthos.gr'),
        );

        for (final action in ['AddTicket', 'AddNote', 'EditTicket']) {
          final fields = _fieldsForAction(fakePoster, action);
          expect(fields, isNotNull, reason: 'λείπει action $action');
          expect(fields!['Email'], 'v.drosos@hospkorinthos.gr');
          expect(fields['AgentEmail'], 'v.drosos@hospkorinthos.gr');
          expect(fields.containsKey('Username'), isFalse);
          expect(fields.containsKey('AgentUsername'), isFalse);
        }

        fakePoster = _RecordingFakePoster(
          responses: const [
            successWithTicketId,
            successOnly,
            successOnly,
          ],
        );
        service = LansweeperSyncService(poster: fakePoster.call);

        await service.submitTicketWorkflow(
          _workflowRequest(agentUsername: r'CORP\agent'),
        );

        for (final action in ['AddTicket', 'AddNote', 'EditTicket']) {
          final fields = _fieldsForAction(fakePoster, action);
          expect(fields, isNotNull, reason: 'λείπει action $action');
          expect(fields!['Username'], r'CORP\agent');
          expect(fields['AgentUsername'], r'CORP\agent');
          expect(fields.containsKey('Email'), isFalse);
          expect(fields.containsKey('AgentEmail'), isFalse);
        }
      },
    );

    test(
      'AddNote: Text == "Λύση δοκιμής.\\n\\nΧρόνος: 05:00" και Type == config.noteType (Internal)',
      () async {
        await service.submitTicketWorkflow(_workflowRequest());

        final fields = _fieldsForAction(fakePoster, 'AddNote');
        expect(fields, isNotNull);
        expect(fields!['Text'], 'Λύση δοκιμής.\n\nΧρόνος: 05:00');
        expect(fields['Type'], 'Internal');
        expect(fields['TicketID'], '17476');
      },
    );

    test('EditTicket: State == "Closed" (όνομα, όχι αριθμός)', () async {
      await service.submitTicketWorkflow(_workflowRequest());

      final fields = _fieldsForAction(fakePoster, 'EditTicket');
      expect(fields, isNotNull);
      expect(fields!['State'], 'Closed');
      expect(fields['TicketID'], '17476');
      expect(fields.containsKey('Description'), isFalse);
    });

    test(
      'Retry με existingTicketId: το πρώτο καταγεγραμμένο action ΔΕΝ είναι AddTicket — ξεκινά από AddNote στο υπάρχον ticketId',
      () async {
        fakePoster = _RecordingFakePoster(
          responses: const [successOnly, successOnly],
        );
        service = LansweeperSyncService(poster: fakePoster.call);

        await service.submitTicketWorkflow(
          _workflowRequest(existingTicketId: '17476'),
        );

        expect(fakePoster.calls, isNotEmpty);
        expect(fakePoster.calls.first.action, 'AddNote');
        expect(fakePoster.calls.first.fields['TicketID'], '17476');
        expect(
          fakePoster.calls.any((call) => call.action == 'AddTicket'),
          isFalse,
        );
      },
    );

    test(
      'Fallback: όταν το AddNote επιστρέφει αποτυχία, στέλνεται EditTicket με Description=buildTicketDescription(...) και το αποτέλεσμα είναι success=true με warning',
      () async {
        fakePoster = _RecordingFakePoster(
          responses: const [
            successWithTicketId,
            failure,
            successOnly,
          ],
        );
        service = LansweeperSyncService(poster: fakePoster.call);

        final result = await service.submitTicketWorkflow(_workflowRequest());

        final fallbackFields = _fieldsForAction(fakePoster, 'EditTicket');
        expect(fallbackFields, isNotNull);
        expect(
          fallbackFields!['Description'],
          LansweeperSyncService.buildTicketDescription(
            notes: 'Πρόβλημα δοκιμής',
            solution: 'Λύση δοκιμής.',
            durationSeconds: 300,
          ),
        );
        expect(result.success, isTrue);
        expect(result.ticketId, '17476');
        expect(result.completedSteps, contains('EditTicket(fallback)'));
        expect(
          result.warnings,
          contains(
            'Η σημείωση απέτυχε· η λύση καταχωρήθηκε στην περιγραφή του ticket.',
          ),
        );
      },
    );

    test(
      'Ολική αποτυχία: όταν αποτυγχάνει και το AddNote και το fallback EditTicket → success=false, failedStep="AddNote", ticketId διατηρείται',
      () async {
        fakePoster = _RecordingFakePoster(
          responses: const [
            successWithTicketId,
            failure,
            failure,
          ],
        );
        service = LansweeperSyncService(poster: fakePoster.call);

        final result = await service.submitTicketWorkflow(_workflowRequest());

        expect(result.success, isFalse);
        expect(result.failedStep, 'AddNote');
        expect(result.ticketId, '17476');
      },
    );

    test(
      'όταν includeNoteTime=false, το Text του AddNote ΔΕΝ περιέχει «Χρόνος:»',
      () async {
        await service.submitTicketWorkflow(
          _workflowRequest(
            config: LansweeperTicketSubmitConfig.defaults().copyWith(
              includeNoteTime: false,
            ),
          ),
        );

        final fields = _fieldsForAction(fakePoster, 'AddNote');
        expect(fields, isNotNull);
        expect(fields!['Text'], 'Λύση δοκιμής.');
        expect(fields['Text'], isNot(contains('Χρόνος:')));
      },
    );

    test(
      'όταν includeNoteTime=true (και υπάρχει διάρκεια), το Text περιέχει «Χρόνος: MM:SS»',
      () async {
        await service.submitTicketWorkflow(
          _workflowRequest(
            config: LansweeperTicketSubmitConfig.defaults().copyWith(
              includeNoteTime: true,
            ),
            durationSeconds: 300,
          ),
        );

        final fields = _fieldsForAction(fakePoster, 'AddNote');
        expect(fields, isNotNull);
        expect(fields!['Text'], contains('Χρόνος: 05:00'));
      },
    );
  });
}
