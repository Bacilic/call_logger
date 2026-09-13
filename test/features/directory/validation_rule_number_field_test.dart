// Τα αριθμητικά πεδία των κανόνων επικύρωσης: ΠΟΤΕ αποθηκεύεται η τιμή.
//
// Η αποθήκευση γίνεται με Enter ή όταν φύγει η εστίαση — όχι σε κάθε πλήκτρο,
// γιατί τότε το ενδιάμεσο «1» του «12» γράφεται στη βάση ως αληθινός κανόνας.
//
//   flutter test test/features/directory/validation_rule_number_field_test.dart

import 'package:call_logger/features/directory/screens/widgets/validation_rules/validation_rule_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<int> saved;
  late TextEditingController controller;
  late FocusNode node;

  setUp(() {
    saved = <int>[];
    controller = TextEditingController(text: '4');
    node = FocusNode();
  });

  tearDown(() {
    controller.dispose();
    node.dispose();
  });

  Future<void> pumpField(WidgetTester tester, {int current = 4}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              InlineNumberField(
                label: 'Ψηφία εσωτερικών τηλεφώνων:',
                controller: controller,
                focusNode: node,
                maxLength: 2,
                min: 1,
                max: 15,
                currentValue: current,
                onCommitted: saved.add,
              ),
              // Κάτι άλλο να πάρει την εστίαση, όπως στην πραγματική οθόνη.
              const TextField(key: Key('αλλού')),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('η πληκτρολόγηση δεν αποθηκεύει τίποτα', (tester) async {
    await pumpField(tester);
    await tester.enterText(find.byType(TextField).first, '12');
    await tester.pump();

    // Το ενδιάμεσο «1» δεν έγινε ποτέ κανόνας.
    expect(saved, isEmpty);
  });

  testWidgets('το Enter αποθηκεύει την τιμή', (tester) async {
    await pumpField(tester);
    await tester.enterText(find.byType(TextField).first, '12');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(saved, [12]);
  });

  testWidgets('το χάσιμο εστίασης αποθηκεύει την τιμή', (tester) async {
    await pumpField(tester);
    await tester.enterText(find.byType(TextField).first, '12');
    await tester.tap(find.byKey(const Key('αλλού')));
    await tester.pump();

    expect(saved, [12]);
  });

  testWidgets('τιμή πάνω από το όριο προσαρμόζεται και φαίνεται', (
    tester,
  ) async {
    await pumpField(tester);
    await tester.enterText(find.byType(TextField).first, '99');
    await tester.tap(find.byKey(const Key('αλλού')));
    await tester.pump();

    expect(saved, [15]);
    expect(controller.text, '15');
  });

  testWidgets('άδειο πεδίο επαναφέρει ό,τι ισχύει, χωρίς αποθήκευση', (
    tester,
  ) async {
    await pumpField(tester, current: 4);
    await tester.enterText(find.byType(TextField).first, '');
    await tester.tap(find.byKey(const Key('αλλού')));
    await tester.pump();

    expect(saved, isEmpty);
    expect(controller.text, '4');
  });

  testWidgets('όσο η τιμή είναι εκτός ορίων, το πεδίο το λέει', (tester) async {
    await pumpField(tester);
    await tester.enterText(find.byType(TextField).first, '99');
    await tester.pump();

    expect(find.text('Μέγιστο: 15'), findsOneWidget);
  });

  group('εύρος «από — έως»', () {
    late TextEditingController from;
    late TextEditingController to;
    late FocusNode fromNode;
    late FocusNode toNode;
    late List<List<int>> savedPairs;

    setUp(() {
      from = TextEditingController(text: '4');
      to = TextEditingController(text: '6');
      fromNode = FocusNode();
      toNode = FocusNode();
      savedPairs = <List<int>>[];
    });

    tearDown(() {
      from.dispose();
      to.dispose();
      fromNode.dispose();
      toNode.dispose();
    });

    Future<void> pumpRange(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                InlineRangeFields(
                  label: 'Ψηφία κωδικού: από',
                  fromController: from,
                  toController: to,
                  fromFocusNode: fromNode,
                  toFocusNode: toNode,
                  min: 1,
                  max: 15,
                  currentFrom: 4,
                  currentTo: 6,
                  onCommitted: (f, t) => savedPairs.add([f, t]),
                ),
                const TextField(key: Key('αλλού')),
              ],
            ),
          ),
        ),
      );
    }

    testWidgets('η πληκτρολόγηση δεν αποθηκεύει· το Enter ναι', (tester) async {
      await pumpRange(tester);
      await tester.enterText(find.byType(TextField).at(1), '9');
      await tester.pump();
      expect(savedPairs, isEmpty);

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(savedPairs, [
        [4, 9],
      ]);
    });

    testWidgets('«από» μεγαλύτερο από «έως»: δεν αποθηκεύεται και το λέει', (
      tester,
    ) async {
      await pumpRange(tester);
      await tester.enterText(find.byType(TextField).first, '9');
      await tester.tap(find.byKey(const Key('αλλού')));
      await tester.pump();

      expect(savedPairs, isEmpty);
      expect(
        find.text('Το «από» δεν μπορεί να ξεπερνά το «έως»'),
        findsOneWidget,
      );
      // Ό,τι πληκτρολόγησε μένει: ανεβάζοντας και τα δύο άκρα περνά
      // αναγκαστικά από αυτή τη στιγμή, και μια επαναφορά θα το έσβηνε.
      expect(from.text, '9');
    });

    testWidgets('μόλις διορθωθεί το άλλο άκρο, το ζεύγος αποθηκεύεται', (
      tester,
    ) async {
      await pumpRange(tester);
      await tester.enterText(find.byType(TextField).first, '9');
      await tester.tap(find.byKey(const Key('αλλού')));
      await tester.pump();
      expect(savedPairs, isEmpty);

      await tester.enterText(find.byType(TextField).at(1), '12');
      await tester.tap(find.byKey(const Key('αλλού')));
      await tester.pump();

      expect(savedPairs, [
        [9, 12],
      ]);
      expect(
        find.text('Το «από» δεν μπορεί να ξεπερνά το «έως»'),
        findsNothing,
      );
    });

    testWidgets('άδειο άκρο επιστρέφει μόνο του, χωρίς να σβήσει το διπλανό', (
      tester,
    ) async {
      await pumpRange(tester);
      await tester.enterText(find.byType(TextField).first, '');
      await tester.tap(find.byKey(const Key('αλλού')));
      await tester.pump();

      expect(savedPairs, isEmpty);
      expect(from.text, '4');
      expect(to.text, '6');
    });
  });

  group('πεδίο κειμένου ρύθμισης', () {
    late TextEditingController text;
    late FocusNode textNode;
    late List<String> savedText;

    setUp(() {
      text = TextEditingController(text: '(, -');
      textNode = FocusNode();
      savedText = <String>[];
    });

    tearDown(() {
      text.dispose();
      textNode.dispose();
    });

    testWidgets('αποθηκεύει στην έξοδο, όχι σε κάθε γράμμα', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                CommitTextField(
                  controller: text,
                  focusNode: textNode,
                  width: 140,
                  onCommitted: savedText.add,
                ),
                const TextField(key: Key('αλλού')),
              ],
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField).first, '(, -, .');
      await tester.pump();
      expect(savedText, isEmpty);

      await tester.tap(find.byKey(const Key('αλλού')));
      await tester.pump();
      expect(savedText, ['(, -, .']);
    });
  });
}
