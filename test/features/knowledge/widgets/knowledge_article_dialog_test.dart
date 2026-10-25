// Η φόρμα άρθρου με τη «Βελτίωση με ΤΝ»: η ΤΝ γεμίζει τα πεδία, η
// «Επαναφορά» φέρνει πίσω το κείμενο του χρήστη. Η ΤΝ εδώ είναι ψεύτικη —
// κανένα δίκτυο.
//
//   flutter test test/features/knowledge/widgets/knowledge_article_dialog_test.dart

import 'package:call_logger/features/history/providers/history_provider.dart';
import 'package:call_logger/features/knowledge/models/knowledge_article.dart';
import 'package:call_logger/features/knowledge/providers/knowledge_provider.dart';
import 'package:call_logger/features/knowledge/services/knowledge_improve_runner.dart';
import 'package:call_logger/features/knowledge/widgets/knowledge_article_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _article = KnowledgeArticle(
  id: 6,
  title: 'Docutrak',
  symptom: 'δεν φαινοντε τα αιτηματα',
  solution: 'αλλαγη σε γνωστοποιηση',
);

void main() {
  late List<KnowledgeImproveInput> sent;

  Future<void> open(
    WidgetTester tester,
    KnowledgeImproveOutcome Function(KnowledgeImproveInput) answer,
  ) async {
    sent = [];
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          historyCategoryEntriesProvider.overrideWith((ref) async => const []),
          knowledgeImproveRunnerProvider.overrideWithValue((input) async {
            sent.add(input);
            return answer(input);
          }),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    showKnowledgeArticleDialog(context, article: _article),
                child: const Text('άνοιγμα'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('άνοιγμα'));
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.byWidgetPredicate(
    (w) => w is InputDecorator && w.decoration.labelText == label,
  );

  String textOf(WidgetTester tester, String label) {
    final editable = tester.widget<EditableText>(
      find.descendant(of: field(label), matching: find.byType(EditableText)),
    );
    return editable.controller.text;
  }

  testWidgets('η ΤΝ γεμίζει τα πεδία με όσα πρότεινε', (tester) async {
    await open(
      tester,
      (_) => const KnowledgeImproved((
        title: 'Αδυναμία προβολής αιτημάτων στο Docutrak',
        symptom: 'Δεν φαίνονται τα αιτήματα',
        solution: null,
        tags: 'Docutrak, αιτήματα',
      )),
    );

    await tester.tap(find.text('Βελτίωση με ΤΝ'));
    await tester.pumpAndSettle();

    expect(sent.single.symptom, 'δεν φαινοντε τα αιτηματα');
    expect(
      textOf(tester, 'Τίτλος'),
      'Αδυναμία προβολής αιτημάτων στο Docutrak',
    );
    expect(textOf(tester, 'Λέξεις-κλειδιά'), 'Docutrak, αιτήματα');
    expect(
      textOf(tester, 'Λύση'),
      'αλλαγη σε γνωστοποιηση',
      reason: 'Πεδίο που η ΤΝ δεν έστειλε μένει όπως ήταν.',
    );
  });

  testWidgets('η «Επαναφορά» φέρνει πίσω το κείμενο του χρήστη', (
    tester,
  ) async {
    await open(
      tester,
      (_) => const KnowledgeImproved((
        title: 'Νέος τίτλος',
        symptom: 'Νέο σύμπτωμα',
        solution: 'Νέα λύση',
        tags: 'νέα',
      )),
    );
    expect(find.text('Επαναφορά'), findsNothing);

    await tester.tap(find.text('Βελτίωση με ΤΝ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Επαναφορά'));
    await tester.pumpAndSettle();

    expect(textOf(tester, 'Τίτλος'), 'Docutrak');
    expect(textOf(tester, 'Λύση'), 'αλλαγη σε γνωστοποιηση');
    expect(find.text('Επαναφορά'), findsNothing);
  });

  testWidgets('χωρίς κλειδί ΤΝ η φόρμα λέει ότι το άρθρο αντιγράφηκε', (
    tester,
  ) async {
    await open(tester, (_) => const KnowledgeImproveCopied());

    await tester.tap(find.text('Βελτίωση με ΤΝ'));
    await tester.pumpAndSettle();

    expect(find.textContaining('αντιγράφηκε'), findsOneWidget);
    expect(textOf(tester, 'Τίτλος'), 'Docutrak');
  });
}
