import 'package:call_logger/features/lamp/controllers/lamp_search_controller.dart';
import 'package:call_logger/features/lamp/controllers/lamp_path_management.dart';
import 'package:call_logger/features/lamp/controllers/lamp_screen_host.dart';
import 'package:call_logger/features/lamp/widgets/lamp_search_key_autocomplete.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _ThrowingHost implements LampScreenHost {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _StubPath extends LampPathController {
  _StubPath() : super(host: _ThrowingHost());
}

void main() {
  group('LampSearchKeyAutocomplete', () {
    late LampSearchController search;

    setUp(() {
      search = LampSearchController(host: _ThrowingHost(), path: _StubPath());
    });

    tearDown(() {
      search.dispose();
    });

    testWidgets('εμφανίζει προτάσεις όταν πληκτρολογείται κλειδί χωρίς :',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LampSearchKeyAutocomplete(
              search: search,
              onSubmitted: () {},
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'κατηγ');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('κατηγορία'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('δεν εμφανίζει overlay όταν το κομμάτι περιέχει :', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LampSearchKeyAutocomplete(
              search: search,
              onSubmitted: () {},
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'κατηγορία:υπο');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('κατηγορία'), findsNothing);
      expect(find.text('ip'), findsNothing);

      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('επιλογή πρότασης εισάγει κλειδί: και κέρσορα μετά το :', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LampSearchKeyAutocomplete(
              search: search,
              onSubmitted: () {},
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'ip');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(
        find.descendant(
          of: find.byType(ListView),
          matching: find.text('ip'),
        ),
      );
      await tester.pump();

      expect(search.globalController.text, 'ip:');

      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets(
      'ΣΕΝΑΡΙΟ WINDOWS: κλικ ποντικιού σε πρόταση την εφαρμόζει '
      '(δεν τη σκοτώνει το unfocus του tap-outside)',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        try {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: LampSearchKeyAutocomplete(
                  search: search,
                  onSubmitted: () {},
                ),
              ),
            ),
          );

          await tester.enterText(find.byType(TextField), 'ip');
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));

          // Ρεαλιστικό κλικ ποντικιού: πάτημα → μεσολαβεί καρέ (όπου
          // εφαρμόζεται τυχόν unfocus/αφαίρεση overlay) → άφημα.
          final target = tester.getCenter(
            find.descendant(
              of: find.byType(ListView),
              matching: find.text('ip'),
            ),
          );
          final gesture = await tester.startGesture(
            target,
            kind: PointerDeviceKind.mouse,
          );
          await tester.pump(const Duration(milliseconds: 80));
          await gesture.up();
          await tester.pump();

          expect(
            search.globalController.text,
            'ip:',
            reason: 'Το κλικ ποντικιού στην πρόταση πρέπει να την εφαρμόζει '
                'και σε desktop (Windows), όχι μόνο σε αφή.',
          );
        } finally {
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pump();
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets(
      'ΣΕΝΑΡΙΟ WINDOWS: βελάκι κάτω + Enter επιλέγει τη δεύτερη πρόταση',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        try {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: LampSearchKeyAutocomplete(
                  search: search,
                  onSubmitted: () {},
                ),
              ),
            ),
          );

          await tester.enterText(find.byType(TextField), 'κατ');
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));

          final shown = <String>[
            for (final w in tester.widgetList<ListTile>(find.byType(ListTile)))
              ((w.title) as Text).data!,
          ];
          expect(shown.length, greaterThanOrEqualTo(2));

          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();

          expect(
            search.globalController.text,
            '${shown[1]}:',
            reason: 'Το βελάκι πρέπει να μετακινεί την επιλογή και το Enter '
                'να εφαρμόζει την ενεργή πρόταση.',
          );

          final editable = tester.state<EditableTextState>(
            find.byType(EditableText),
          );
          expect(
            editable.widget.focusNode.hasPrimaryFocus,
            isTrue,
            reason: 'Μετά την επιλογή με Enter, η εστίαση πρέπει να μένει '
                'ΜΕΣΑ στο πεδίο αναζήτησης ώστε ο χρήστης να συνεχίσει '
                'να πληκτρολογεί την τιμή.',
          );
        } finally {
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pump();
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets('πλοήγηση με Enter επιλέγει την ενεργή πρόταση', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LampSearchKeyAutocomplete(
              search: search,
              onSubmitted: () {},
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'κατηγ');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(search.globalController.text, 'κατηγορία:');

      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });
}
