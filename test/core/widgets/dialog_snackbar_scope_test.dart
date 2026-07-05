import 'package:call_logger/core/widgets/dialog_snackbar_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _TestDialog extends StatefulWidget {
  const _TestDialog({required this.onReady});

  final void Function(_TestDialogState state) onReady;

  @override
  State<_TestDialog> createState() => _TestDialogState();
}

class _TestDialogState extends State<_TestDialog> with DialogSnackbarHost {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onReady(this);
    });
  }

  @override
  Widget build(BuildContext context) {
    return DialogSnackbarScope(
      messengerKey: dialogMessengerKey,
      child: Center(
        child: AlertDialog(
          title: const Text('Δοκιμαστικός διάλογος'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Κλείσιμο'),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _openTestDialog(WidgetTester tester) async {
  await tester.tap(find.text('Άνοιγμα'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final copyCalls = <String>[];

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      switch (call.method) {
        case 'Clipboard.setData':
          final args = call.arguments as Map<Object?, Object?>;
          copyCalls.add(args['text'] as String);
          return null;
        default:
          return null;
      }
    });
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  setUp(() => copyCalls.clear());

  group('DialogSnackbarHost / DialogSnackbarScope', () {
    testWidgets(
      'showDialogSnackBar εμφανίζει snackbar στο subtree του διαλόγου',
      (tester) async {
        _TestDialogState? dialogState;
        final rootMessengerKey = GlobalKey<ScaffoldMessengerState>();

        await tester.pumpWidget(
          MaterialApp(
            home: ScaffoldMessenger(
              key: rootMessengerKey,
              child: Scaffold(
                body: Builder(
                  builder: (context) => FilledButton(
                    onPressed: () {
                      showDialog<void>(
                        context: context,
                        builder: (_) => _TestDialog(
                          onReady: (state) => dialogState = state,
                        ),
                      );
                    },
                    child: const Text('Άνοιγμα'),
                  ),
                ),
              ),
            ),
          ),
        );

        await _openTestDialog(tester);

        expect(dialogState, isNotNull);
        dialogState!.showDialogSnackBar(
          const SnackBar(content: Text('Μήνυμα διαλόγου')),
        );
        await tester.pump();

        expect(find.text('Μήνυμα διαλόγου'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(DialogSnackbarScope),
            matching: find.text('Μήνυμα διαλόγου'),
          ),
          findsOneWidget,
        );
        expect(
          dialogState!.dialogMessengerKey.currentState,
          isNot(rootMessengerKey.currentState),
        );

        await tester.tap(find.text('Κλείσιμο'));
        await tester.pumpAndSettle();
      },
    );

    testWidgets('copyText αντιγράφει και εμφανίζει επιβεβαίωση', (tester) async {
      _TestDialogState? dialogState;

      await tester.binding.setSurfaceSize(const Size(1024, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () {
                  showDialog<void>(
                    context: context,
                    builder: (_) => _TestDialog(
                      onReady: (state) => dialogState = state,
                    ),
                  );
                },
                child: const Text('Άνοιγμα'),
              ),
            ),
          ),
        ),
      );

      await _openTestDialog(tester);

      dialogState!.showDialogSnackBar(
        const SnackBar(
          content: Text('Σφάλμα API'),
          behavior: SnackBarBehavior.floating,
        ),
        copyText: 'λεπτομέρειες σφάλματος',
      );
      await tester.pump();

      final copyIconButton = find.descendant(
        of: find.byType(SnackBar),
        matching: find.byType(IconButton),
      );
      expect(copyIconButton, findsOneWidget);
      final iconButton = tester.widget<IconButton>(copyIconButton);
      iconButton.onPressed?.call();
      await tester.pumpAndSettle();

      expect(copyCalls, ['λεπτομέρειες σφάλματος']);
      expect(find.text('Αντιγραφή στο πρόχειρο.'), findsOneWidget);

      await tester.tap(find.text('Κλείσιμο'));
      await tester.pumpAndSettle();
    });
  });
}
