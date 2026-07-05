import 'package:call_logger/features/settings/widgets/remote_tool_form/remote_tool_form_controller.dart';
import 'package:call_logger/features/settings/widgets/remote_tool_form/remote_tool_test_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

Widget _testPanelHost({
  required RemoteToolFormController controller,
  required VoidCallback onRunTest,
}) =>
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) => RemoteToolTestPanel(
              controller: controller,
              onRunTest: onRunTest,
            ),
          ),
        ),
      ),
    );

void main() {
  group('RemoteToolTestPanel — lock πριν εξαγωγή', () {
    testWidgets(
      'RemoteToolTestPanel: χωρίς IP απενεργοποιημένο κουμπί, χωρίς τίτλο δοκιμής',
      (tester) async {
        final controller = RemoteToolFormController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          _host(
            RemoteToolTestPanel(
              controller: controller,
              onRunTest: () {},
            ),
          ),
        );

        expect(find.text('Εντολή δοκιμής'), findsNothing);
        final btn = tester.widget<OutlinedButton>(
          find.widgetWithText(OutlinedButton, 'Δοκιμή εργαλείου'),
        );
        expect(btn.onPressed, isNull);
      },
    );

    testWidgets(
      'RemoteToolTestPanel: εμφανίζει πεδίο Δοκιμαστική IP / Hostname',
      (tester) async {
        final controller = RemoteToolFormController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          _host(
            RemoteToolTestPanel(
              controller: controller,
              onRunTest: () {},
            ),
          ),
        );

        expect(
          find.text('Δοκιμαστική IP / Hostname (για δοκιμή)'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'RemoteToolTestPanel: πληκτρολόγηση IP ενεργοποιεί κουμπί δοκιμής',
      (tester) async {
        final controller = RemoteToolFormController();
        addTearDown(controller.dispose);
        controller.pathC.text = r'C:\vnc.exe';

        await tester.pumpWidget(
          _testPanelHost(controller: controller, onRunTest: () {}),
        );

        final btnBefore = tester.widget<OutlinedButton>(
          find.widgetWithText(OutlinedButton, 'Δοκιμή εργαλείου'),
        );
        expect(btnBefore.onPressed, isNull);

        await tester.enterText(
          find.byType(TextFormField),
          '192.168.1.10',
        );
        await tester.pump();

        final btnAfter = tester.widget<OutlinedButton>(
          find.widgetWithText(OutlinedButton, 'Δοκιμή εργαλείου'),
        );
        expect(btnAfter.onPressed, isNotNull);
        expect(find.text('Εντολή δοκιμής'), findsOneWidget);
      },
    );

    testWidgets(
      'RemoteToolTestPanel: με IP ενεργό κουμπί και onRunTest καλείται',
      (tester) async {
        final controller = RemoteToolFormController();
        addTearDown(controller.dispose);
        var ran = false;

        controller.pathC.text = r'C:\vnc.exe';
        controller.testIpC.text = '192.168.1.10';

        await tester.pumpWidget(
          _host(
            RemoteToolTestPanel(
              controller: controller,
              onRunTest: () => ran = true,
            ),
          ),
        );

        expect(find.text('Εντολή δοκιμής'), findsOneWidget);
        final btn = tester.widget<OutlinedButton>(
          find.widgetWithText(OutlinedButton, 'Δοκιμή εργαλείου'),
        );
        expect(btn.onPressed, isNotNull);

        await tester.tap(find.text('Δοκιμή εργαλείου'));
        await tester.pump();
        expect(ran, isTrue);
      },
    );
  });
}
