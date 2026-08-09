// Μετά από αποθήκευση κανόνα επικύρωσης, η αλυσίδα rules → service ξεπλένεται
// ΕΚΤΟΣ φάσης build.
//
// Χωρίς αυτό, το invalidate των κανόνων αφήνει τον
// `catalogValidationServiceProvider` (που τους παρακολουθεί με watch) «dirty
// χωρίς listeners» — καμία φόρμα καταλόγου δεν είναι ανοιχτή όσο ο χρήστης
// βρίσκεται στην οθόνη κανόνων. Η αλυσίδα ξεπλένεται αργότερα σύγχρονα μέσα σε
// build (initState της οθόνης κανόνων ή build φόρμας καταλόγου) και η εφαρμογή
// πέφτει με «setState() called during build» (κατάρρευση 09/08/2026 μετά από
// αλλαγή βάσης).
//
// Ολόκληρο αρχείο (από ρίζα έργου):
//   flutter test test/features/directory/catalog_validation_chain_flush_test.dart

import 'package:call_logger/features/directory/models/catalog_validation_rules.dart';
import 'package:call_logger/features/directory/providers/catalog_validation_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ελάχιστο widget που παίζει τον ρόλο της οθόνης κανόνων: ακυρώνει τους
/// κανόνες όπως η `_apply` και μετά ξεπλένει την αλυσίδα.
class _RulesEditor extends ConsumerStatefulWidget {
  const _RulesEditor();

  @override
  ConsumerState<_RulesEditor> createState() => _RulesEditorState();
}

class _RulesEditorState extends ConsumerState<_RulesEditor> {
  void applyMutation() {
    ref.invalidate(catalogValidationRulesProvider);
    flushCatalogValidationProviderChain(ref);
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void main() {
  testWidgets(
    'η αποθήκευση κανόνα ξαναχτίζει την αλυσίδα αμέσως, εκτός build',
    (tester) async {
      var rulesBuilds = 0;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            catalogValidationRulesProvider.overrideWith((ref) async {
              rulesBuilds++;
              return const CatalogValidationRules();
            }),
          ],
          child: const MaterialApp(home: _RulesEditor()),
        ),
      );
      await tester.pump();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(_RulesEditor)),
      );

      // Μια φόρμα καταλόγου είχε ανοίξει κάποια στιγμή: ο service υπάρχει και
      // παρακολουθεί τους κανόνες με watch — αυτή η συνδρομή είναι η «βόμβα».
      await container.read(catalogValidationServiceProvider.future);
      expect(rulesBuilds, 1);

      tester.state<_RulesEditorState>(find.byType(_RulesEditor)).applyMutation();

      // Ο έλεγχος γίνεται ΠΡΙΝ από pump: το ξέπλυμα οφείλει να είναι άμεσο
      // (eager), όχι προγραμματισμένο για επόμενο frame.
      expect(
        rulesBuilds,
        2,
        reason:
            'Οι κανόνες έμειναν «dirty»: κανένα eager flush μετά το invalidate '
            '— θα ξεπλένονταν σύγχρονα μέσα στο επόμενο build.',
      );
      await tester.pump();
    },
    semanticsEnabled: false,
  );

  testWidgets(
    'χωρίς προηγούμενη χρήση, το ξέπλυμα αρχικοποιεί την αλυσίδα εκτός build',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            catalogValidationRulesProvider.overrideWith(
              (ref) async => const CatalogValidationRules(),
            ),
          ],
          child: const MaterialApp(home: _RulesEditor()),
        ),
      );
      await tester.pump();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(_RulesEditor)),
      );

      // Καμία φόρμα ή οθόνη κανόνων δεν έχει ανοίξει: η αλυσίδα δεν υπάρχει.
      expect(container.exists(catalogValidationRulesProvider), isFalse);
      expect(container.exists(catalogValidationServiceProvider), isFalse);

      tester.state<_RulesEditorState>(find.byType(_RulesEditor)).applyMutation();

      // Η αλυσίδα υπολογίστηκε τώρα — δεν θα υπολογιστεί μέσα σε build.
      expect(container.exists(catalogValidationRulesProvider), isTrue);
      expect(container.exists(catalogValidationServiceProvider), isTrue);
      await tester.pump();
    },
    semanticsEnabled: false,
  );
}
