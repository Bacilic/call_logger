import 'package:call_logger/core/widgets/spell_check_controller.dart';
import 'package:call_logger/features/history/widgets/lansweeper/lansweeper_sync_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';


void main() {
  group('LansweeperSyncForm cooldown UI', () {
    late SpellCheckController titleController;
    late SpellCheckController notesController;
    late SpellCheckController solutionController;

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
      int? cooldownRemainingSeconds,
      String? cooldownModelLabel,
    }) {
      return ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: LansweeperSyncForm(
              titleController: titleController,
              notesController: notesController,
              solutionController: solutionController,
              isSuggesting: false,
              cooldownRemainingSeconds: cooldownRemainingSeconds,
              cooldownModelLabel: cooldownModelLabel,
              onCancelAutoResubmit: () {},
            ),
          ),
        ),
      );
    }

    testWidgets('απενεργοποιημένο κουμπί με όνομα αναμενόμενου μοντέλου', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildForm(
          cooldownRemainingSeconds: 25,
          cooldownModelLabel: 'gemini-flash-latest',
        ),
      );

      final button = tester.widget<FilledButton>(
        find.byType(FilledButton),
      );
      expect(button.onPressed, isNull);
      expect(find.text('gemini-flash-latest'), findsOneWidget);
    });

    testWidgets('ετικέτα αντίστροφης μέτρησης με tabular figures', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildForm(
          cooldownRemainingSeconds: 42,
          cooldownModelLabel: 'model-x',
        ),
      );

      expect(find.text('42 δλ'), findsOneWidget);
      final countdown = tester.widget<Text>(find.text('42 δλ'));
      expect(
        countdown.style?.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
    });

    testWidgets('χρώματα στα όρια 30/10 δευτερολέπτων', (tester) async {
      Future<Color?> colorFor(int seconds) async {
        await tester.pumpWidget(
          buildForm(
            cooldownRemainingSeconds: seconds,
            cooldownModelLabel: 'm',
          ),
        );
        final text = tester.widget<Text>(find.text('$seconds δλ'));
        return text.style?.color;
      }

      final red = await colorFor(31);
      final orange = await colorFor(20);
      final green = await colorFor(9);

      expect(red, Colors.red);
      expect(orange, Colors.orange);
      expect(green, Colors.green);
    });
  });
}
