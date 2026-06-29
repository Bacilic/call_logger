// Widget test: επεξεργασία προτύπου προτροπής — dirty-state, αποθήκευση, προεπιλογές.
//
// Ολόκληρο αρχείο:
//   flutter test test/features/history/gemini_prompt_template_editor_dialog_test.dart

import 'package:call_logger/features/history/providers/dashboard_provider.dart';
import 'package:call_logger/features/history/widgets/lansweeper/gemini_prompt_template_editor_dialog.dart';
import 'package:call_logger/features/history/widgets/lansweeper/lansweeper_sync_form.dart';
import 'package:call_logger/core/widgets/spell_check_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/misc.dart' show Override;

const _kValidSavedTemplate = '''
Τμήμα: {Τμήμα}
Απάντησε σε JSON: {"title":"...","description":"...","solution":"..."}''';

const _kInvalidSavedTemplate = 'Κατηγορία: {Κατηγορίαα}';

String? _testUserDefaultValue;

class _MutableUserDefaultNotifier extends GeminiPromptTemplateUserDefaultNotifier {
  @override
  String? build() => _testUserDefaultValue;

  @override
  Future<void> setUserDefault(String value) async {
    _testUserDefaultValue = value.trim().isEmpty ? null : value.trim();
    state = _testUserDefaultValue;
  }
}

List<Override> _editorDialogOverrides() {
  return <Override>[
    geminiPromptTemplateUserDefaultProvider.overrideWith(
      _MutableUserDefaultNotifier.new,
    ),
  ];
}

Widget _wrapDialog({
  required String savedTemplate,
  required Future<void> Function(String text) onSave,
}) {
  return ProviderScope(
    overrides: _editorDialogOverrides(),
    child: MaterialApp(
      home: Scaffold(
        body: GeminiPromptTemplateEditorDialog(
          savedTemplate: savedTemplate,
          onSave: onSave,
        ),
      ),
    ),
  );
}

Finder get _saveButton => find.widgetWithText(FilledButton, 'Αποθήκευση');
Finder get _cancelButton => find.widgetWithText(TextButton, 'Ακύρωση');
Finder get _closeButton => find.widgetWithText(TextButton, 'Κλείσιμο');

void main() {
  setUp(() {
    _testUserDefaultValue = null;
  });

  group('LansweeperSyncForm · επεξεργασία προτύπου', () {
    testWidgets('εικονίδιο ανοίγει τον διάλογο επεξεργασίας', (tester) async {
      var dialogOpened = false;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: LansweeperSyncForm(
                titleController: SpellCheckController(),
                notesController: SpellCheckController(),
                solutionController: SpellCheckController(),
                onEditPromptTemplate: () {
                  dialogOpened = true;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Επεξεργασία προτύπου προτροπής'));
      await tester.pumpAndSettle();

      expect(dialogOpened, isTrue);
    });
  });

  group('GeminiPromptTemplateEditorDialog · dirty-state', () {
    testWidgets('Αποθήκευση ανενεργή χωρίς αλλαγές', (tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        _wrapDialog(
          savedTemplate: _kValidSavedTemplate,
          onSave: (_) async {},
        ),
      );
      await tester.pumpAndSettle();

      final save = tester.widget<FilledButton>(_saveButton);
      expect(save.onPressed, isNull);
    });

    testWidgets('Αποθήκευση ενεργή και γράφει μέσω onSave', (tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      String? persisted;
      await tester.pumpWidget(
        _wrapDialog(
          savedTemplate: _kValidSavedTemplate,
          onSave: (text) async {
            persisted = text;
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Αλλαγμένο $_kValidSavedTemplate');
      await tester.pumpAndSettle();

      expect(tester.widget<FilledButton>(_saveButton).onPressed, isNotNull);

      await tester.tap(_saveButton);
      await tester.pumpAndSettle();

      expect(persisted, contains('Αλλαγμένο'));
      expect(tester.widget<FilledButton>(_saveButton).onPressed, isNull);
    });

    testWidgets('Ακύρωση επαναφέρει το αποθηκευμένο στιγμιότυπο', (tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        _wrapDialog(
          savedTemplate: _kValidSavedTemplate,
          onSave: (_) async {},
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Προσωρινή αλλαγή');
      await tester.pumpAndSettle();

      await tester.tap(_cancelButton);
      await tester.pumpAndSettle();

      expect(find.textContaining('Προσωρινή αλλαγή'), findsNothing);
      expect(find.textContaining('Τμήμα: {Τμήμα}'), findsOneWidget);
    });

    testWidgets('κλείσιμο με αλλαγές εμφανίζει προειδοποίηση', (tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        _wrapDialog(
          savedTemplate: _kValidSavedTemplate,
          onSave: (_) async {},
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Αλλαγή χωρίς αποθήκευση');
      await tester.pumpAndSettle();

      await tester.tap(_closeButton);
      await tester.pumpAndSettle();

      expect(find.text('Μη αποθηκευμένες αλλαγές'), findsOneWidget);
    });

    testWidgets('κλείσιμο χωρίς αλλαγές κλείνει αμέσως', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: FilledButton(
                  onPressed: () {
                    showDialog<void>(
                      context: context,
                      builder: (ctx) => ProviderScope(
                        overrides: _editorDialogOverrides(),
                        child: GeminiPromptTemplateEditorDialog(
                          savedTemplate: _kValidSavedTemplate,
                          onSave: (_) async {},
                        ),
                      ),
                    );
                  },
                  child: const Text('Άνοιγμα'),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Άνοιγμα'));
      await tester.pumpAndSettle();
      expect(find.text('Πρότυπο προτροπής Gemini'), findsOneWidget);

      await tester.tap(_closeButton);
      await tester.pumpAndSettle();

      expect(find.text('Πρότυπο προτροπής Gemini'), findsNothing);
    });

    testWidgets('μπλοκάρει αποθήκευση μη έγκυρου προτύπου', (tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      var saveCalls = 0;
      await tester.pumpWidget(
        _wrapDialog(
          savedTemplate: _kValidSavedTemplate,
          onSave: (_) async {
            saveCalls++;
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), _kInvalidSavedTemplate);
      await tester.pumpAndSettle();
      await tester.tap(_saveButton);
      await tester.pumpAndSettle();

      expect(find.text('Μη έγκυρο πρότυπο'), findsOneWidget);
      expect(saveCalls, 0);
    });
  });

  group('GeminiPromptTemplateEditorDialog · προεπιλογές', () {
    testWidgets(
      'Επαναφορά χωρίς προσωπική προεπιλογή φορτώνει εργοστασιακό πρότυπο',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          _wrapDialog(
            savedTemplate: _kValidSavedTemplate,
            onSave: (_) async {},
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Επαναφορά Προεπιλογής'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Επαναφορά'));
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Δημιούργησε τίτλο'),
          findsOneWidget,
          reason: 'Φορτώθηκε το kDefaultGeminiPromptTemplate',
        );
      },
    );

    testWidgets(
      'Επαναφορά με προσωπική προεπιλογή — επιλογή προσωπικής',
      (tester) async {
        _testUserDefaultValue = 'Προσωπικό πρότυπο με "title" και "description" και "solution"';

        tester.view.physicalSize = const Size(1200, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          _wrapDialog(
            savedTemplate: _kValidSavedTemplate,
            onSave: (_) async {},
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Επαναφορά Προεπιλογής'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Προσωπική'));
        await tester.pumpAndSettle();

        expect(find.textContaining('Προσωπικό πρότυπο'), findsOneWidget);
      },
    );

    testWidgets('Ορισμός Προεπιλογής αποθηκεύει την τρέχουσα τιμή πεδίου',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        _wrapDialog(
          savedTemplate: _kValidSavedTemplate,
          onSave: (_) async {},
        ),
      );
      await tester.pumpAndSettle();

      const personal = 'Προσωπικό για αποθήκευση με "title" "description" "solution"';
      await tester.enterText(find.byType(TextField), personal);
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Ορισμός ως Προεπιλογή'));
      await tester.tap(find.text('Ορισμός ως Προεπιλογή'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Ορισμός'));
      await tester.pumpAndSettle();

      expect(_testUserDefaultValue, personal);
    });
  });
}
