// Έλεγχοι μοντέλου παραμετροποίησης πολυβηματικής καταχώρησης Lansweeper.
//
//   flutter test test/core/services/lansweeper_ticket_submit_config_test.dart

import 'package:call_logger/core/services/lansweeper_ticket_submit_config.dart';
import 'package:flutter_test/flutter_test.dart';

void _expectConfigEquals(
  LansweeperTicketSubmitConfig a,
  LansweeperTicketSubmitConfig b,
) {
  expect(a.schemaVersion, b.schemaVersion);
  expect(a.ticketStates, b.ticketStates);
  expect(a.defaultTicketState, b.defaultTicketState);
  expect(a.noteType, b.noteType);
  expect(a.ticketType, b.ticketType);
  expect(a.ticketTypes, b.ticketTypes);
  expect(a.priority, b.priority);
  expect(a.priorities, b.priorities);
  expect(a.team, b.team);
  expect(a.teams, b.teams);
  expect(a.enableAddNoteStep, b.enableAddNoteStep);
  expect(a.enableStateUpdateStep, b.enableStateUpdateStep);
  expect(a.rememberFormSelections, b.rememberFormSelections);
  expect(a.includeNoteTime, b.includeNoteTime);
  expect(a.customFields.length, b.customFields.length);
  for (var i = 0; i < a.customFields.length; i++) {
    final fa = a.customFields[i];
    final fb = b.customFields[i];
    expect(fa.id, fb.id);
    expect(fa.apiName, fb.apiName);
    expect(fa.formLabel, fb.formLabel);
    expect(fa.widgetType, fb.widgetType);
    expect(fa.options, fb.options);
    expect(fa.defaultValue, fb.defaultValue);
    expect(fa.visible, fb.visible);
    expect(fa.required, fb.required);
    expect(fa.showInForm, fb.showInForm);
  }
}

void main() {
  group('LansweeperTicketSubmitConfig', () {
    test('encode → decode round-trip διατηρεί όλα τα πεδία', () {
      final original = LansweeperTicketSubmitConfig.defaults();
      final encoded =
          LansweeperTicketSubmitConfig.encodeForStorage(original);
      final decoded =
          LansweeperTicketSubmitConfig.decodeFromStorage(encoded);
      _expectConfigEquals(decoded, original);
    });

    test('decodeFromStorage σε null, σε \'\' και σε άκυρο JSON επιστρέφει τα defaults χωρίς exception', () {
      final defaults = LansweeperTicketSubmitConfig.defaults();

      expect(
        () => LansweeperTicketSubmitConfig.decodeFromStorage(null),
        returnsNormally,
      );
      _expectConfigEquals(
        LansweeperTicketSubmitConfig.decodeFromStorage(null),
        defaults,
      );

      expect(
        () => LansweeperTicketSubmitConfig.decodeFromStorage(''),
        returnsNormally,
      );
      _expectConfigEquals(
        LansweeperTicketSubmitConfig.decodeFromStorage(''),
        defaults,
      );

      expect(
        () => LansweeperTicketSubmitConfig.decodeFromStorage('{invalid'),
        returnsNormally,
      );
      _expectConfigEquals(
        LansweeperTicketSubmitConfig.decodeFromStorage('{invalid'),
        defaults,
      );
    });

    test(
      'τα defaults έχουν ticketStates [Open, Closed, In Progress], defaultTicketState Closed, noteType Internal, ticketType/priority/team = IT Support/Low/IT Support',
      () {
        final config = LansweeperTicketSubmitConfig.defaults();

        expect(config.ticketStates, ['Open', 'Closed', 'In Progress']);
        expect(config.defaultTicketState, 'Closed');
        expect(config.noteType, 'Internal');
        expect(config.ticketType, 'IT Support');
        expect(config.priority, 'Low');
        expect(config.team, 'IT Support');
        expect(config.enableAddNoteStep, isTrue);
        expect(config.enableStateUpdateStep, isTrue);
        expect(config.rememberFormSelections, isTrue);
        expect(config.schemaVersion, 2);
      },
    );

    test(
      'defaults έχουν priorities [Low,Medium,High] (default Low), ticketTypes/teams [IT Support]',
      () {
        final config = LansweeperTicketSubmitConfig.defaults();

        expect(config.priorities, ['Low', 'Medium', 'High']);
        expect(config.priority, 'Low');
        expect(config.ticketTypes, ['IT Support']);
        expect(config.ticketType, 'IT Support');
        expect(config.teams, ['IT Support']);
        expect(config.team, 'IT Support');
      },
    );

    test(
      'decode παλιού JSON χωρίς τις λίστες → migration με τις προεπιλογές, χωρίς exception',
      () {
        const legacyJson = '''
{
  "schema_version": 1,
  "custom_fields": [],
  "ticket_states": ["Open", "Closed"],
  "default_ticket_state": "Closed",
  "note_type": "Internal",
  "ticket_type": "IT Support",
  "priority": "Low",
  "team": "IT Support",
  "enable_add_note_step": true,
  "enable_state_update_step": true,
  "remember_form_selections": true
}''';

        expect(
          () => LansweeperTicketSubmitConfig.decodeFromStorage(legacyJson),
          returnsNormally,
        );
        final migrated =
            LansweeperTicketSubmitConfig.decodeFromStorage(legacyJson);
        expect(migrated.priorities, ['Low', 'Medium', 'High']);
        expect(migrated.priority, 'Low');
        expect(migrated.ticketTypes, ['IT Support']);
        expect(migrated.ticketType, 'IT Support');
        expect(migrated.teams, ['IT Support']);
        expect(migrated.team, 'IT Support');
        expect(migrated.schemaVersion, 2);
      },
    );

    test(
      'τα defaults έχουν 2 custom fields: Κατηγορία αιτήματος (radio, options Yes/No, default Yes, required) και Τί αφορά; (dropdown, 7 options, default Software γενικού σκοπού στα Endpoints, required)',
      () {
        final config = LansweeperTicketSubmitConfig.defaults();

        expect(config.customFields, hasLength(2));

        final category = config.customFields[0];
        expect(category.id, 'category');
        expect(category.apiName, 'Κατηγορία αιτήματος');
        expect(category.formLabel, 'Κατηγορία αιτήματος');
        expect(category.widgetType, LansweeperFieldWidgetType.radio);
        expect(category.options, ['Yes', 'No']);
        expect(category.defaultValue, 'Yes');
        expect(category.required, isTrue);
        expect(category.visible, isTrue);
        expect(category.showInForm, isTrue);

        final incident = config.customFields[1];
        expect(incident.id, 'incident_category');
        expect(incident.apiName, 'Τί αφορά;');
        expect(incident.formLabel, 'Τί αφορά;');
        expect(incident.widgetType, LansweeperFieldWidgetType.dropdown);
        expect(incident.options, hasLength(7));
        expect(
          incident.defaultValue,
          'Software γενικού σκοπού στα Endpoints',
        );
        expect(incident.required, isTrue);
        expect(incident.visible, isTrue);
        expect(incident.showInForm, isTrue);
      },
    );

    test(
      'missingRequiredFields εντοπίζει required πεδίο με κενή τιμή, και επιστρέφει άδεια λίστα όταν όλα τα required είναι συμπληρωμένα',
      () {
        final config = LansweeperTicketSubmitConfig.defaults();

        expect(
          config.missingRequiredFields({}),
          containsAll(['category', 'incident_category']),
        );
        expect(
          config.missingRequiredFields({'category': ''}),
          contains('category'),
        );
        expect(
          config.missingRequiredFields({
            'category': 'Yes',
            'incident_category': '',
          }),
          ['incident_category'],
        );
        expect(
          config.missingRequiredFields({
            'category': 'Yes',
            'incident_category': 'Software γενικού σκοπού στα Endpoints',
          }),
          isEmpty,
        );
      },
    );

    test('defaults().includeNoteTime είναι true', () {
      expect(LansweeperTicketSubmitConfig.defaults().includeNoteTime, isTrue);
    });

    test('encode→decode διατηρεί το includeNoteTime', () {
      final withFalse = LansweeperTicketSubmitConfig.defaults().copyWith(
        includeNoteTime: false,
      );
      final decoded = LansweeperTicketSubmitConfig.decodeFromStorage(
        LansweeperTicketSubmitConfig.encodeForStorage(withFalse),
      );
      expect(decoded.includeNoteTime, isFalse);

      final withTrue = LansweeperTicketSubmitConfig.defaults().copyWith(
        includeNoteTime: true,
      );
      final decodedTrue = LansweeperTicketSubmitConfig.decodeFromStorage(
        LansweeperTicketSubmitConfig.encodeForStorage(withTrue),
      );
      expect(decodedTrue.includeNoteTime, isTrue);
    });

    test('decode παλιού JSON χωρίς το κλειδί → true', () {
      const legacyJson = '''
{
  "schema_version": 2,
  "custom_fields": [],
  "ticket_states": ["Open", "Closed"],
  "default_ticket_state": "Closed",
  "note_type": "Internal",
  "ticket_type": "IT Support",
  "priority": "Low",
  "team": "IT Support",
  "enable_add_note_step": true,
  "enable_state_update_step": true,
  "remember_form_selections": true
}''';
      final decoded =
          LansweeperTicketSubmitConfig.decodeFromStorage(legacyJson);
      expect(decoded.includeNoteTime, isTrue);
    });

    test(
      'decodeFromStorage σε JSON schemaVersion 2 ΧΩΡΙΣ το κλειδί includeNoteTime → ΔΕΝ πετάει, και includeNoteTime == true',
      () {
        // Χειροκίνητο JSON (χωρίς include_note_time / includeNoteTime).
        const jsonWithoutKey = '''
{
  "schema_version": 2,
  "custom_fields": [
    {
      "id": "category",
      "api_name": "Κατηγορία αιτήματος",
      "form_label": "Κατηγορία αιτήματος",
      "widget_type": "radio",
      "options": ["Yes", "No"],
      "default_value": "Yes",
      "visible": true,
      "required": true,
      "show_in_form": true
    }
  ],
  "ticket_states": ["Open", "Closed", "In Progress"],
  "default_ticket_state": "Closed",
  "note_type": "Internal",
  "ticket_type": "IT Support",
  "ticket_types": ["IT Support"],
  "priority": "Low",
  "priorities": ["Low", "Medium", "High"],
  "team": "IT Support",
  "teams": ["IT Support"],
  "enable_add_note_step": true,
  "enable_state_update_step": true,
  "remember_form_selections": true
}''';

        expect(
          () => LansweeperTicketSubmitConfig.decodeFromStorage(jsonWithoutKey),
          returnsNormally,
        );
        final decoded =
            LansweeperTicketSubmitConfig.decodeFromStorage(jsonWithoutKey);
        expect(decoded.includeNoteTime, isTrue);
        expect(decoded.schemaVersion, 2);
        expect(decoded.enableAddNoteStep, isTrue);
        expect(decoded.enableStateUpdateStep, isTrue);
        expect(decoded.rememberFormSelections, isTrue);
        expect(decoded.ticketTypes, ['IT Support']);
        expect(decoded.priorities, ['Low', 'Medium', 'High']);
        expect(decoded.teams, ['IT Support']);
      },
    );
  });

  group('LansweeperFieldWidgetType', () {
    test('fromStorage άγνωστη τιμή → text', () {
      expect(
        LansweeperFieldWidgetType.fromStorage('unknown'),
        LansweeperFieldWidgetType.text,
      );
    });

    test('toStorage/fromStorage round-trip', () {
      for (final type in LansweeperFieldWidgetType.values) {
        expect(
          LansweeperFieldWidgetType.fromStorage(type.toStorage()),
          type,
        );
      }
    });
  });
}
