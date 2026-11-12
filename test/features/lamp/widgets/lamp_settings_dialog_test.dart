import 'package:call_logger/features/lamp/controllers/lamp_integrity_controller.dart';
import 'package:call_logger/features/lamp/controllers/lamp_path_management.dart';
import 'package:call_logger/features/lamp/controllers/lamp_screen_host.dart';
import 'package:call_logger/features/lamp/controllers/lamp_search_controller.dart';
import 'package:call_logger/features/lamp/widgets/lamp_settings_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubPath extends LampPathController {
  _StubPath() : super(host: _ThrowingHost());

  @override
  String? readPathFormatWarning() => null;
}

class _ThrowingHost implements LampScreenHost {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _StubSearch extends LampSearchController {
  _StubSearch(LampPathController path)
    : super(host: _ThrowingHost(), path: path);
}

class _StubIntegrity extends LampIntegrityController {
  _StubIntegrity(LampPathController path)
    : super(host: _ThrowingHost(), path: path);
}

/// Στήνει τον host, ανοίγει τον διάλογο και τον αφήνει σταθερό.
Future<void> _openLampSettingsDialog(
  WidgetTester tester,
  LampSettingsDialogController controller,
) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () {
                    openLampSettingsDialog(
                      context: context,
                      controller: controller,
                      registerDialogSetState: (_) {},
                      onDialogClosed: () {},
                    );
                  },
                  child: const Text('Άνοιγμα'),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.tap(find.text('Άνοιγμα'));
  await tester.pumpAndSettle();
}

void main() {
  group('Ρυθμίσεις Λάμπας', () {
    late _StubPath path;
    late _StubSearch search;
    late LampSettingsDialogController controller;

    setUp(() {
      path = _StubPath();
      search = _StubSearch(path);
      controller = LampSettingsDialogController(
        path: path,
        search: search,
        integrityController: _StubIntegrity(path),
        getReadPathCheck: () => null,
        getDialogFeedback: () => null,
        getDialogFeedbackIsError: () => false,
        onClearDialogFeedback: () {},
        onCopyDialogFeedback: (_) async {},
        onPickReadDatabase: () async {},
        onRunIntegrityCheck: () async {},
        onClose: (_) async {},
        isIntegrityChecking: () => false,
      );
    });

    tearDown(() {
      search.dispose();
      path.dispose();
    });

    testWidgets(
      'δείχνει μόνο τη βάση της Λάμπας — καμία δημιουργία από Excel',
      (tester) async {
        await _openLampSettingsDialog(tester, controller);

        expect(
          find.text('Βάση Δεδομένων που χρησιμοποιεί η Λάμπα'),
          findsOneWidget,
        );
        expect(find.text('Έλεγχος Προβλημάτων'), findsOneWidget);
        expect(find.text('Αρχείο Excel (πηγή δεδομένων)'), findsNothing);
        expect(
          find.text('Βάση δεδομένων που δημιουργεί το Excel'),
          findsNothing,
        );
        expect(find.text('Δημιουργία βάσης από Excel'), findsNothing);
      },
    );

    testWidgets('χωρίς έλεγχο ακόμη, λέει ότι γίνεται αυτόματα', (
      tester,
    ) async {
      await _openLampSettingsDialog(tester, controller);

      expect(find.textContaining('γίνεται αυτόματα'), findsWidgets);
    });
  });
}
