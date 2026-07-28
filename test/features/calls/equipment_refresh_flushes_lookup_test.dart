import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:call_logger/features/calls/provider/smart_entity_selector_provider.dart';
import 'package:call_logger/core/services/lookup_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Οι φόρμες εξοπλισμού (απλή και μαζική) κάνουν invalidate το lookup και μετά
/// καλούν το [refreshSelectedEquipmentInAllSelectors]. Όταν ΚΑΝΕΝΑΣ selector
/// δεν έχει επιλεγμένο εξοπλισμό, τα επιμέρους refresh επιστρέφουν νωρίς —
/// αν ο κοινός βοηθός δεν ξεπλύνει ο ίδιος το lookup, αυτό μένει «βρόμικο»
/// και ξεπλένεται σύγχρονα μέσα στο επόμενο build της οθόνης κλήσεων
/// (γνωστή οικογένεια «setState during build»).
void main() {
  testWidgets(
    'refreshSelectedEquipmentInAllSelectors ξεπλένει το lookup και χωρίς επιλεγμένο εξοπλισμό',
    (tester) async {
      var lookupBuilds = 0;
      late WidgetRef capturedRef;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            lookupServiceProvider.overrideWith((ref) async {
              lookupBuilds++;
              return LookupLoadResult(service: LookupService.instance);
            }),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              capturedRef = ref;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      // Κανείς δεν παρακολουθεί το lookup ακόμη — δεν έχει χτιστεί.
      expect(lookupBuilds, 0);

      // Το σενάριο των φορμών: invalidate και αμέσως μετά ο κοινός βοηθός.
      capturedRef.invalidate(lookupServiceProvider);
      await refreshSelectedEquipmentInAllSelectors(capturedRef);
      await tester.pump();

      // Ο βοηθός οφείλει να έχει ξεπλύνει (ξαναχτίσει) το lookup ο ίδιος.
      expect(
        lookupBuilds,
        1,
        reason:
            'Το lookup έμεινε «βρόμικο»: κανένα eager flush μετά το invalidate '
            'όταν δεν υπάρχει επιλεγμένος εξοπλισμός σε κανέναν selector.',
      );
    },
  );
}
