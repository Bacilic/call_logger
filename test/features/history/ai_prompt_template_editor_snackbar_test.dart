// Widget test: snackbar αποθήκευσης προτύπου εμφανίζεται στον τοπικό messenger του διαλόγου.
//
//   flutter test test/features/history/ai_prompt_template_editor_snackbar_test.dart

import 'package:call_logger/core/widgets/dialog_snackbar_scope.dart';
import 'package:call_logger/features/history/providers/gemini_settings_provider.dart';
import 'package:call_logger/features/history/widgets/lansweeper/ai_prompt_template_editor_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/misc.dart' show Override;

const _kValidSavedTemplate = '''
Τμήμα: {Τμήμα}
Απάντησε σε JSON: {"title":"...","description":"...","solution":"..."}''';

List<Override> _editorDialogOverrides() {
  return <Override>[
    geminiPromptTemplateUserDefaultProvider.overrideWith(
      GeminiPromptTemplateUserDefaultNotifier.new,
    ),
  ];
}

void main() {
  testWidgets(
    'αποθήκευση προτύπου δείχνει snackbar μέσα στον διάλογο',
    (tester) async {
      final rootMessengerKey = GlobalKey<ScaffoldMessengerState>();

      await tester.pumpWidget(
        ProviderScope(
          overrides: _editorDialogOverrides(),
          child: MaterialApp(
            home: ScaffoldMessenger(
              key: rootMessengerKey,
              child: Scaffold(
                body: Builder(
                  builder: (context) => FilledButton(
                    onPressed: () {
                      showDialog<void>(
                        context: context,
                        builder: (_) => AiPromptTemplateEditorDialog(
                          savedTemplate: _kValidSavedTemplate,
                          onSave: (_) async {},
                        ),
                      );
                    },
                    child: const Text('Άνοιγμα επεξεργαστή'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Άνοιγμα επεξεργαστή'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '$_kValidSavedTemplate\n');
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, 'Αποθήκευση'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Το πρότυπο αποθηκεύτηκε.'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(DialogSnackbarScope),
          matching: find.text('Το πρότυπο αποθηκεύτηκε.'),
        ),
        findsOneWidget,
      );
      expect(find.byType(AlertDialog), findsOneWidget);
    },
  );
}
