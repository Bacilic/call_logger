import 'package:call_logger/core/services/lansweeper_ticket_submit_config.dart';
import 'package:call_logger/core/widgets/lexicon_spell_text_form_field.dart';
import 'package:call_logger/core/widgets/spell_check_controller.dart';
import 'package:call_logger/features/history/widgets/lansweeper/lansweeper_sync_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LansweeperSyncForm — δυναμικά πεδία από config', () {
    late SpellCheckController titleController;
    late SpellCheckController notesController;
    late SpellCheckController solutionController;
    final config = LansweeperTicketSubmitConfig.defaults();

    setUp(() {
      titleController = SpellCheckController();
      notesController = SpellCheckController();
      solutionController = SpellCheckController();
    });

    tearDown(() {
      titleController.dispose();
      notesController.dispose();
      solutionController.dispose();
    });

    Widget buildForm({
      LansweeperTicketSubmitConfig? formConfig,
      Map<String, String> customFieldValues = const <String, String>{},
      void Function(String fieldId, String value)? onCustomFieldChanged,
      String? ticketState,
      ValueChanged<String>? onTicketStateChanged,
    }) {
      return ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: LansweeperSyncForm(
              titleController: titleController,
              notesController: notesController,
              solutionController: solutionController,
              config: formConfig,
              customFieldValues: customFieldValues,
              onCustomFieldChanged: onCustomFieldChanged,
              ticketState: ticketState,
              onTicketStateChanged: onTicketStateChanged,
            ),
          ),
        ),
      );
    }

    Future<void> pumpForm(
      WidgetTester tester, {
      LansweeperTicketSubmitConfig? formConfig,
      Map<String, String> customFieldValues = const <String, String>{},
      void Function(String fieldId, String value)? onCustomFieldChanged,
      String? ticketState,
      ValueChanged<String>? onTicketStateChanged,
    }) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        buildForm(
          formConfig: formConfig,
          customFieldValues: customFieldValues,
          onCustomFieldChanged: onCustomFieldChanged,
          ticketState: ticketState,
          onTicketStateChanged: onTicketStateChanged,
        ),
      );
      await tester.pumpAndSettle();
    }

    Finder dropdownByLabel(String label) {
      return find.byWidgetPredicate(
        (widget) =>
            widget is DropdownButtonFormField<String> &&
            widget.decoration.labelText == label,
      );
    }

    Finder dropdownSelectedText(String label, String value) {
      return find.descendant(
        of: dropdownByLabel(label),
        matching: find.text(value),
      );
    }

    testWidgets(
      'Αποδίδεται dropdown «Κατηγορία αιτήματος» με επιλογές Yes/No και προεπιλογή Yes',
      (tester) async {
        await pumpForm(tester, formConfig: config);

        final categoryField = config.customFields.firstWhere(
          (field) => field.id == 'category',
        );
        expect(categoryField.options, ['Yes', 'No']);
        expect(dropdownByLabel('Κατηγορία αιτήματος'), findsOneWidget);
        expect(dropdownSelectedText('Κατηγορία αιτήματος', 'Yes'), findsOneWidget);
      },
    );

    testWidgets(
      'Αποδίδεται dropdown «Τί αφορά;» με 7 επιλογές και προεπιλογή Software γενικού σκοπού στα Endpoints',
      (tester) async {
        await pumpForm(tester, formConfig: config);

        final incidentField = config.customFields.firstWhere(
          (field) => field.id == 'incident_category',
        );
        expect(incidentField.options, hasLength(7));
        expect(dropdownByLabel('Τί αφορά;'), findsOneWidget);
        expect(
          dropdownSelectedText(
            'Τί αφορά;',
            'Software γενικού σκοπού στα Endpoints',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Αποδίδεται dropdown «Κατάσταση ticket» με Open/Closed/In Progress και προεπιλογή Closed',
      (tester) async {
        await pumpForm(tester, formConfig: config);

        expect(config.ticketStates, ['Open', 'Closed', 'In Progress']);
        expect(dropdownByLabel('Κατάσταση ticket'), findsOneWidget);
        expect(dropdownSelectedText('Κατάσταση ticket', 'Closed'), findsOneWidget);
      },
    );

    testWidgets(
      'Αλλαγή επιλογής σε custom field καλεί onCustomFieldChanged με σωστό fieldId και τιμή',
      (tester) async {
        String? changedId;
        String? changedValue;

        await pumpForm(
          tester,
          formConfig: config,
          onCustomFieldChanged: (id, value) {
            changedId = id;
            changedValue = value;
          },
        );

        await tester.tap(dropdownByLabel('Κατηγορία αιτήματος'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('No').last);
        await tester.pumpAndSettle();

        expect(changedId, 'category');
        expect(changedValue, 'No');
      },
    );

    testWidgets(
      'Το hint της Λύσης αναφέρει «σημείωση (Note)» και ΟΧΙ «περιγραφή»',
      (tester) async {
        await pumpForm(tester, formConfig: config);

        final solutionField = find.byWidgetPredicate(
          (widget) =>
              widget is LexiconSpellTextFormField &&
              widget.controller == solutionController,
        );
        expect(solutionField, findsOneWidget);
        final field = tester.widget<LexiconSpellTextFormField>(solutionField);
        final hint = field.decoration.hintText ?? '';
        expect(hint, contains('σημείωση (Note)'));
        expect(hint, isNot(contains('Ενσωματώνεται στην περιγραφή')));
      },
    );
  });
}
