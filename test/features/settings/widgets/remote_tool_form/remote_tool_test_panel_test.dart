import 'package:call_logger/core/models/remote_tool.dart';
import 'package:call_logger/core/models/remote_tool_role.dart';
import 'package:call_logger/features/settings/screens/remote_tools_management_screen.dart';
import 'package:call_logger/features/settings/widgets/remote_tool_form/remote_tool_form_controller.dart';
import 'package:call_logger/features/settings/widgets/remote_tool_form/remote_tool_test_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../test_reporter.dart';

Widget _testPanelHost({
  required RemoteToolFormController controller,
  required GlobalKey<FormState> formKey,
  VoidCallback? onSave,
}) =>
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: ListenableBuilder(
              listenable: controller,
              builder: (context, _) => Column(
                children: [
                  RemoteToolTestPanel(
                    controller: controller,
                    onRunTest: () {},
                  ),
                  FilledButton(
                    onPressed: onSave,
                    child: const Text('Αποθήκευση'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

Finder _testIpField() => find.descendant(
      of: find.byWidgetPredicate(
        (w) =>
            w is InputDecorator &&
            w.decoration.labelText ==
                'Δοκιμαστική IP / Hostname (για δοκιμή)',
      ),
      matching: find.byType(EditableText),
    );

void main() {
  group('RemoteToolTestPanel — επικύρωση και μορφοποίηση IP', () {
    testWidgets(
      'κόμμα numpad γίνεται τελεία στο πεδίο δοκιμαστικής IP',
      (tester) async {
        final controller = RemoteToolFormController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(_testPanelHost(
          controller: controller,
          formKey: GlobalKey<FormState>(),
        ));

        await tester.enterText(_testIpField(), '10,10,25,12');
        await tester.pump();

        expect(
          controller.testIpC.text,
          '10.10.25.12',
          reason: greekExpectMsg(
            'Το CommaToDotDecimalSeparatorFormatter μετατρέπει κόμμα σε τελεία',
          ),
        );
      },
    );

    testWidgets(
      '«11.0265.0656» εμφανίζει μήνυμα πλήθους ομάδων IP',
      (tester) async {
        final controller = RemoteToolFormController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(_testPanelHost(
          controller: controller,
          formKey: GlobalKey<FormState>(),
        ));

        await tester.enterText(_testIpField(), '11.0265.0656');
        await tester.pump();

        expect(
          find.textContaining(
            'Η IP θέλει 4 αριθμούς χωρισμένους με τελείες — βρέθηκαν 3.',
          ),
          findsOneWidget,
          reason: greekExpectMsg(
            'Η άκυρη IP με 3 ομάδες δείχνει στοχευμένο μήνυμα πλήθους',
          ),
        );
      },
    );

    testWidgets(
      'κενό πεδίο: κανένα μήνυμα σφάλματος και η αποθήκευση δεν μπλοκάρεται',
      (tester) async {
        final controller = RemoteToolFormController();
        addTearDown(controller.dispose);
        final formKey = GlobalKey<FormState>();
        var saved = false;

        await tester.pumpWidget(_testPanelHost(
          controller: controller,
          formKey: formKey,
          onSave: () {
            if (formKey.currentState?.validate() ?? false) {
              saved = true;
            }
          },
        ));

        await tester.tap(find.text('Αποθήκευση'));
        await tester.pump();

        expect(find.textContaining('Μη έγκυρη διεύθυνση'), findsNothing);
        expect(find.textContaining('Η IP θέλει'), findsNothing);
        expect(saved, isTrue);
      },
    );

    testWidgets(
      'άκυρη τιμή: μήνυμα σφάλματος και μπλοκάρισμα αποθήκευσης',
      (tester) async {
        final controller = RemoteToolFormController();
        addTearDown(controller.dispose);
        final formKey = GlobalKey<FormState>();
        var saved = false;

        await tester.pumpWidget(_testPanelHost(
          controller: controller,
          formKey: formKey,
          onSave: () {
            if (formKey.currentState?.validate() ?? false) {
              saved = true;
            }
          },
        ));

        await tester.enterText(_testIpField(), '!!!άκυρο!!!');
        await tester.pump();
        await tester.tap(find.text('Αποθήκευση'));
        await tester.pump();

        expect(find.textContaining('Μη έγκυρη διεύθυνση'), findsOneWidget);
        expect(saved, isFalse);
      },
    );

    testWidgets(
      'έγκυρη IP: κανένα μήνυμα σφάλματος και επιτυχής επικύρωση',
      (tester) async {
        final controller = RemoteToolFormController();
        addTearDown(controller.dispose);
        final formKey = GlobalKey<FormState>();
        var saved = false;

        await tester.pumpWidget(_testPanelHost(
          controller: controller,
          formKey: formKey,
          onSave: () {
            if (formKey.currentState?.validate() ?? false) {
              saved = true;
            }
          },
        ));

        await tester.enterText(_testIpField(), '192.168.1.10');
        await tester.pump();
        await tester.tap(find.text('Αποθήκευση'));
        await tester.pump();

        expect(find.textContaining('Μη έγκυρη διεύθυνση'), findsNothing);
        expect(saved, isTrue);
      },
    );

    testWidgets(
      'έγκυρος κωδικός 3–6 ψηφίων: κανένα μήνυμα σφάλματος',
      (tester) async {
        final controller = RemoteToolFormController();
        addTearDown(controller.dispose);
        final formKey = GlobalKey<FormState>();
        var saved = false;

        await tester.pumpWidget(_testPanelHost(
          controller: controller,
          formKey: formKey,
          onSave: () {
            if (formKey.currentState?.validate() ?? false) {
              saved = true;
            }
          },
        ));

        await tester.enterText(_testIpField(), '922');
        await tester.pump();
        await tester.tap(find.text('Αποθήκευση'));
        await tester.pump();

        expect(find.textContaining('Μη έγκυρη διεύθυνση'), findsNothing);
        expect(saved, isTrue);
      },
    );

    testWidgets(
      'έγκυρο hostname: κανένα μήνυμα σφάλματος',
      (tester) async {
        final controller = RemoteToolFormController();
        addTearDown(controller.dispose);
        final formKey = GlobalKey<FormState>();
        var saved = false;

        await tester.pumpWidget(_testPanelHost(
          controller: controller,
          formKey: formKey,
          onSave: () {
            if (formKey.currentState?.validate() ?? false) {
              saved = true;
            }
          },
        ));

        await tester.enterText(_testIpField(), 'server1');
        await tester.pump();
        await tester.tap(find.text('Αποθήκευση'));
        await tester.pump();

        expect(find.textContaining('Μη έγκυρη διεύθυνση'), findsNothing);
        expect(saved, isTrue);
      },
    );

    test(
      'η φόρμα εργαλείου δείχνει καθαρό κωδικό ενώ η σύνοψη λίστας τον κρύβει',
      () {
        const argValue = '-password=pass99';
        final tool = RemoteTool(
          id: 1,
          name: 'VNC Test',
          role: ToolRole.vnc,
          executablePath: r'C:\vnc.exe',
          sortOrder: 1,
          isActive: true,
          testTargetIp: '922',
          arguments: const [
            RemoteToolArgument(value: argValue, isActive: true),
          ],
        );

        final controller = RemoteToolFormController(initialTool: tool);
        addTearDown(controller.dispose);

        expect(controller.argRows.single.valueC.text, argValue);
        expect(remoteToolArgumentsSummary(tool), '-password=***');
        expect(
          controller.testCommandPreview,
          contains('pass99'),
          reason: 'Η εντολή δοκιμής στη φόρμα δείχνει τον κωδικό καθαρά',
        );
      },
    );
  });
}
