// Το συμβόλαιο: ενέργεια που αγγίζει κατάσταση widget ΠΟΤΕ δεν εκτελείται μέσα
// σε φάση χτισίματος. Μέσα σε build αναβάλλεται στο επόμενο frame· εκτός build
// τρέχει αμέσως, χωρίς να χαθεί frame.
//
// Το πραγματικό περιστατικό (10/08/2026): προσυμπλήρωση φόρμας που γράφει σε
// TextEditingController μέσα στο build ειδοποιούσε listener, ο listener καλούσε
// setState, και η εφαρμογή έπεφτε με «setState() called during build».
//
//   flutter test test/core/utils/run_now_or_after_frame_test.dart

import 'package:call_logger/core/utils/run_after_next_frame.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('εκτός build εκτελείται αμέσως', (tester) async {
    var ran = false;
    await tester.pumpWidget(const SizedBox());

    runNowOrAfterFrame(() => ran = true);

    expect(ran, isTrue, reason: 'σε idle δεν υπάρχει λόγος αναβολής');
  });

  testWidgets('μέσα σε build αναβάλλεται αντί να σκάσει', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _RebuildFromBuild()));
    // Το πρώτο frame προγραμμάτισε την αναβολή· το δεύτερο την εκτελεί.
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('ξαναχτίστηκε'), findsOneWidget);
  });
}

/// Widget που ζητά ανανέωση της κατάστασής του **μέσα** στο δικό του build —
/// ακριβώς η κίνηση που πετούσε «setState() called during build».
class _RebuildFromBuild extends StatefulWidget {
  const _RebuildFromBuild();

  @override
  State<_RebuildFromBuild> createState() => _RebuildFromBuildState();
}

class _RebuildFromBuildState extends State<_RebuildFromBuild> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    if (!_done) {
      runNowOrAfterFrame(() {
        if (!mounted) return;
        setState(() => _done = true);
      });
    }
    return Text(_done ? 'ξαναχτίστηκε' : 'αρχικό');
  }
}
