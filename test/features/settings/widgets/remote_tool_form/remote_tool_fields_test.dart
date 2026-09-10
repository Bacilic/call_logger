import 'package:call_logger/core/models/remote_tool.dart';
import 'package:call_logger/core/models/remote_tool_role.dart';
import 'package:call_logger/features/settings/widgets/remote_tool_form/remote_tool_basic_fields.dart';
import 'package:call_logger/features/settings/widgets/remote_tool_form/remote_tool_behavior_fields.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../test_reporter.dart';

RemoteTool _tool({required int id, required String name}) => RemoteTool(
  id: id,
  name: name,
  role: ToolRole.generic,
  executablePath: 'x.exe',
  sortOrder: id,
  isActive: true,
);

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  group('Εξαγμένα παρουσιαστικά πεδία φόρμας εργαλείου', () {
    testWidgets(
      'NameAutocompleteField: * σε δημιουργία και σφάλμα σε διπλότυπο',
      (tester) async {
        final controller = TextEditingController(text: 'Foo');
        final focus = FocusNode();
        final formKey = GlobalKey<FormState>();
        addTearDown(controller.dispose);
        addTearDown(focus.dispose);

        await tester.pumpWidget(
          _host(
            Form(
              key: formKey,
              child: NameAutocompleteField(
                controller: controller,
                focusNode: focus,
                suggestions: const [],
                nonDeleted: [_tool(id: 1, name: 'Foo')],
                excludeId: null,
                isCreate: true,
              ),
            ),
          ),
        );

        expect(find.text('Όνομα εργαλείου *'), findsOneWidget);
        formKey.currentState!.validate();
        await tester.pump();
        expect(
          find.text('Υπάρχει ήδη εργαλείο με αυτό το όνομα.'),
          findsOneWidget,
        );
      },
    );

    testWidgets('ExecutablePathField: μήνυμα όταν η διαδρομή δεν υπάρχει', (
      tester,
    ) async {
      final controller = TextEditingController(
        text: r'Z:\__does_not_exist__\tool.exe',
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _host(
          ExecutablePathField(
            controller: controller,
            onPick: () {},
            enabled: true,
            isCreate: false,
            checkExists: (_) async => false,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Το αρχείο δεν βρέθηκε στη διαδρομή.'), findsOneWidget);
    });

    testWidgets(
      'ExecutablePathField: η ένδειξη ακολουθεί ΤΟ ΙΔΙΟ το πεδίο, χωρίς να '
      'ρωτά τον δίσκο σε κάθε πλήκτρο',
      (tester) async {
        final controller = TextEditingController();
        addTearDown(controller.dispose);

        // Ο «δίσκος» ξέρει ένα μόνο αρχείο — και μετράει πόσες φορές ρωτήθηκε.
        const known = r'C:\tools\anydesk.exe';
        final probedPaths = <String>[];

        await tester.pumpWidget(
          _host(
            ExecutablePathField(
              controller: controller,
              onPick: () {},
              enabled: true,
              isCreate: false,
              checkExists: (path) async {
                probedPaths.add(path);
                return path == known;
              },
            ),
          ),
        );

        // Λάθος διαδρομή, γράφτηκε γράμμα-γράμμα.
        for (final text in [r'C:\t', r'C:\to', r'C:\tool.exe']) {
          controller.text = text;
          await tester.pump();
        }
        expect(
          probedPaths,
          isEmpty,
          reason: greekExpectMsg(
            'Όσο πληκτρολογείς, ο δίσκος δεν ρωτιέται καθόλου',
          ),
        );

        await tester.pump(ExecutablePathField.probeDelay);
        await tester.pump();
        expect(
          probedPaths,
          [r'C:\tool.exe'],
          reason: greekExpectMsg('Ρωτιέται μία φορά, για την τελική διαδρομή'),
        );
        expect(
          find.text('Το αρχείο δεν βρέθηκε στη διαδρομή.'),
          findsOneWidget,
        );

        // Ο χρήστης τη διορθώνει — χωρίς να αγγίξει άλλο πεδίο.
        controller.text = known;
        await tester.pump();
        await tester.pump(ExecutablePathField.probeDelay);
        await tester.pump();

        expect(
          find.text('Το αρχείο δεν βρέθηκε στη διαδρομή.'),
          findsNothing,
          reason: greekExpectMsg(
            'Η προειδοποίηση φεύγει μόλις διορθωθεί η διαδρομή, χωρίς να '
            'χρειαστεί άγγιγμα άλλου πεδίου',
          ),
        );
        expect(probedPaths, [r'C:\tool.exe', known]);
      },
    );

    testWidgets('RoleDropdown: εμφανίζει ετικέτα ρόλου και τρέχουσα επιλογή', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(RoleDropdown(value: ToolRole.rdp, onChanged: (_) {})),
      );

      expect(find.text('Ρόλος'), findsOneWidget);
      expect(find.text('RDP Hostname/IP'), findsOneWidget);
    });
  });
}
