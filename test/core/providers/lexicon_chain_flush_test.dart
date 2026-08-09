// Μετά από αλλαγή στο λεξικό (προσθήκη λέξεων, compile, επανέλεγχος γλωσσών,
// επιστροφή από Ρυθμίσεις), η αλυσίδα πυρήνας → λεξικό → ορθογράφος ξεπλένεται
// ΕΚΤΟΣ φάσης build.
//
// Χωρίς αυτό, το invalidate του `coreLexiconProvider` αφήνει τον
// `greekDictionaryServiceProvider` και τον `spellCheckServiceProvider` (που
// τον παρακολουθούν με watch) «dirty» όσο οι συνδρομές τους είναι σε παύση —
// τα πεδία με ορθογράφο ζουν στην οθόνη Κλήσεων, που δεν είναι ορατή. Ο
// βρόμικος μεσαίος κρίκος ξεπλένεται αργότερα σύγχρονα μέσα στο build που θα
// τον διαβάσει → «setState() called during build» (ίδια οικογένεια με την
// κατάρρευση των Κανόνων Επικύρωσης 09/08/2026).
//
// Ολόκληρο αρχείο (από ρίζα έργου):
//   flutter test test/core/providers/lexicon_chain_flush_test.dart

import 'package:call_logger/core/providers/core_lexicon_provider.dart';
import 'package:call_logger/core/providers/greek_dictionary_provider.dart';
import 'package:call_logger/core/providers/spell_check_provider.dart';
import 'package:call_logger/core/services/core_lexicon_service.dart';
import 'package:call_logger/core/services/dictionary_service.dart';
import 'package:call_logger/core/services/spell_check_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ελάχιστο widget που παίζει τον ρόλο της Διαχείρισης λεξικού: ακυρώνει
/// πυρήνα + ορθογράφο όπως κάθε μετάλλαξη λεξικού και ξεπλένει την αλυσίδα.
class _DictionaryMutator extends ConsumerStatefulWidget {
  const _DictionaryMutator();

  @override
  ConsumerState<_DictionaryMutator> createState() => _DictionaryMutatorState();
}

class _DictionaryMutatorState extends ConsumerState<_DictionaryMutator> {
  void runMutation() {
    // Η μετάλλαξη αλλάζει πραγματικά το περιεχόμενο του πυρήνα (όπως μια
    // προσθήκη λέξεων/φόρτωση): μόνο τότε η ειδοποίηση διαδίδεται στην
    // αλυσίδα και οι κρίκοι με watch λερώνονται.
    CoreLexiconService.instance.state = CoreLexiconState(
      loaded: true,
      path: 'test/lexicon_updated.txt',
      wordCount: 1,
    );
    ref.invalidate(coreLexiconProvider);
    ref.invalidate(spellCheckServiceProvider);
    flushLexiconProviderChain(ref);
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void main() {
  testWidgets(
    'μετά από μετάλλαξη λεξικού η αλυσίδα ορθογράφου ξεπλένεται αμέσως',
    (tester) async {
      var dictionaryBuilds = 0;
      var spellBuilds = 0;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            // Ίδιες εξαρτήσεις watch με τους πραγματικούς providers — μόνο το
            // βαρύ σώμα (αρχείο λεξικού / βάση) αντικαθίσταται από μετρητή.
            greekDictionaryServiceProvider.overrideWith((ref) {
              ref.watch(coreLexiconProvider);
              dictionaryBuilds++;
              return DictionaryService.empty();
            }),
            spellCheckServiceProvider.overrideWith((ref) async {
              ref.watch(coreLexiconProvider);
              ref.watch(greekDictionaryServiceProvider);
              spellBuilds++;
              return LexiconSpellCheckService();
            }),
          ],
          child: const MaterialApp(home: _DictionaryMutator()),
        ),
      );
      await tester.pump();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(_DictionaryMutator)),
      );

      // Ένα πεδίο με ορθογράφο είχε χτίσει την αλυσίδα κάποια στιγμή: οι
      // συνδρομές watch υπάρχουν — αυτές είναι η «βόμβα».
      await container.read(spellCheckServiceProvider.future);
      expect(dictionaryBuilds, 1);
      expect(spellBuilds, 1);

      tester
          .state<_DictionaryMutatorState>(find.byType(_DictionaryMutator))
          .runMutation();

      // Ο έλεγχος γίνεται ΠΡΙΝ από pump: το ξέπλυμα οφείλει να είναι άμεσο.
      expect(
        dictionaryBuilds,
        2,
        reason:
            'Ο μεσαίος κρίκος (λεξικό) έμεινε «dirty»: θα ξεπλενόταν σύγχρονα '
            'μέσα στο επόμενο build πεδίου με ορθογράφο.',
      );
      expect(
        spellBuilds,
        2,
        reason: 'Ο ορθογράφος έμεινε «dirty» αντί να ξαναχτιστεί εκτός build.',
      );
      await tester.pump();
    },
    semanticsEnabled: false,
  );
}
