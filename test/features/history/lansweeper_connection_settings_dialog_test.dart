// Widget test: διάλογος «Ρυθμίσεις Lansweeper» σε καρτέλες.
//
//   flutter test test/features/history/lansweeper_connection_settings_dialog_test.dart

import 'package:call_logger/features/history/providers/gemini_settings_provider.dart';
import 'package:call_logger/features/history/providers/lansweeper_connection_probe_provider.dart';
import 'package:call_logger/features/history/providers/lansweeper_ticket_submit_config_provider.dart';
import 'package:call_logger/features/history/widgets/lansweeper/lansweeper_connection_settings_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_setup.dart';
import 'lansweeper_report_test_doubles.dart';

class _GeminiFallbackEnabledOnNotifier extends GeminiFallbackEnabledNotifier {
  @override
  bool build() => true;
}

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  group('LansweeperConnectionSettingsDialog (καρτέλες)', () {
    late List<TextEditingController> controllers;

    TextEditingController ctrl([String text = '']) {
      final controller = TextEditingController(text: text);
      controllers.add(controller);
      return controller;
    }

    setUp(() {
      controllers = <TextEditingController>[];
    });

    tearDown(() {
      for (final controller in controllers) {
        controller.dispose();
      }
    });

    Future<ProviderContainer> pumpDialog(
      WidgetTester tester, {
      String primaryModel = '',
      String fallbackModel = '',
      bool fallbackEnabled = false,
    }) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final container = ProviderContainer(
        overrides: [
          ...callLoggerTestProviderOverrides(),
          lansweeperConnectionProbeProvider.overrideWith(
            AlwaysAvailableLansweeperConnectionProbe.new,
          ),
          lansweeperTicketSubmitConfigProvider.overrideWith(
            FixedLansweeperTicketSubmitConfigNotifier.new,
          ),
          geminiFallbackEnabledProvider.overrideWith(
            fallbackEnabled
                ? _GeminiFallbackEnabledOnNotifier.new
                : FixedGeminiFallbackEnabledNotifier.new,
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: LansweeperConnectionSettingsDialog(
                apiUrlController: ctrl('http://test/api.aspx'),
                ticketFormUrlController: ctrl('http://test/NewTicket.aspx'),
                ticketViewUrlController: ctrl('http://test/ticket.aspx?tid={tid}'),
                apiKeyController: ctrl('test-key'),
                agentUsernameController: ctrl('gnk\\v.drosos'),
                loginUrlController: ctrl('http://test/login.aspx'),
                helpdeskUsernameController: ctrl('v.drosos'),
                helpdeskPasswordController: ctrl('secret'),
                geminiApiKeyController: ctrl(),
                geminiEndpointController: ctrl(),
                geminiPrimaryModelController: ctrl(primaryModel),
                geminiFallbackModelController: ctrl(fallbackModel),
                onSettingsChanged: () {},
                onLansweeperUrlChanged: () {},
                onApiHelpLink: () {},
                onTicketFormHelpLink: () {},
                onTicketViewHelpLink: () {},
                onLoginHelpLink: () {},
                onAiHelpLink: () {},
              ),
            ),
          ),
        ),
      );
      await pumpUntilSettled(tester);
      return container;
    }

    testWidgets(
      'ανοίγει με 4 καρτέλες, δείχνει τη «Σύνδεση API» και η κατάσταση σύνδεσης είναι ορατή',
      (tester) async {
        await pumpDialog(tester);

        expect(find.text('Σύνδεση API'), findsOneWidget);
        expect(find.text('Help Desk / Browser'), findsOneWidget);
        expect(find.text('Τεχνητή Νοημοσύνη'), findsOneWidget);
        expect(find.text('Καταχώρηση εισιτηρίου'), findsOneWidget);

        expect(find.text('URL API (api.aspx)'), findsOneWidget);
        expect(
          find.text('Η σύνδεση με το Lansweeper είναι διαθέσιμη.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'πάτημα «Help Desk / Browser» εμφανίζει τα πεδία browser και η κατάσταση παραμένει ορατή',
      (tester) async {
        await pumpDialog(tester);

        await tester.tap(find.text('Help Desk / Browser'));
        await pumpUntilSettled(tester);

        expect(find.text('Όνομα χρήστη Help Desk'), findsOneWidget);
        expect(find.text('Κωδικός Help Desk'), findsOneWidget);
        expect(
          find.text('Η σύνδεση με το Lansweeper είναι διαθέσιμη.'),
          findsOneWidget,
        );

        // Οι ρυθμίσεις browser/Help Desk υδατώνονται από τη βάση —
        // ξεπερνάμε τυχόν pending sqflite lock timers πριν το dispose.
        await flushCallLoggerSqfliteLockTimers(tester);
      },
    );

    testWidgets(
      'πάτημα «Καταχώρηση εισιτηρίου» εμφανίζει πεδία, λίστες και επαναφορά προεπιλογών',
      (tester) async {
        await pumpDialog(tester);

        await tester.tap(find.text('Καταχώρηση εισιτηρίου'));
        await pumpUntilSettled(tester);

        expect(find.text('Πεδία εισιτηρίου (custom fields)'), findsOneWidget);
        expect(find.text('Καταστάσεις ticket (τιμές με κόμμα)'), findsOneWidget);
        expect(find.text('Επαναφορά προεπιλογών'), findsOneWidget);
      },
    );

    testWidgets(
      'το κλείσιμο μπλοκάρεται όταν κύριο και εφεδρικό μοντέλο συμπίπτουν',
      (tester) async {
        await pumpDialog(
          tester,
          primaryModel: 'gemini-2.5-flash',
          fallbackModel: 'gemini-2.5-flash',
          fallbackEnabled: true,
        );

        await tester.tap(find.text('Κλείσιμο'));
        await pumpUntilSettled(tester);

        expect(find.text('Ίδιο μοντέλο'), findsOneWidget);
        expect(
          find.textContaining('δεν μπορεί να είναι το ίδιο'),
          findsOneWidget,
        );
      },
    );
  });
}
