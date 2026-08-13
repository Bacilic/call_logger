// Τα σφάλματα διάταξης δεν φέρνουν στοίβα κλήσεων — φέρνουν την αλυσίδα των
// widget. Αν χαθεί αυτή, το ημερολόγιο κρατά έναν αριθμό pixel που δεν οδηγεί
// σε κανένα αρχείο.
//
//   flutter test test/core/errors/layout_error_diagnostics_test.dart

import 'package:call_logger/core/errors/layout_error_diagnostics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('αναγνώριση σφάλματος διάταξης', () {
    test('τα μηνύματα overflow αναγνωρίζονται', () {
      expect(
        isLayoutErrorMessage('A RenderFlex overflowed by 25 pixels on the '
            'bottom.'),
        isTrue,
      );
    });

    test('άσχετο σφάλμα δεν περνά για διάταξη', () {
      expect(isLayoutErrorMessage('DatabaseException: no such table'), isFalse);
    });
  });

  group('συνοδευτικά σφάλματος διάταξης', () {
    FlutterErrorDetails detailsWith(List<String> information) {
      return FlutterErrorDetails(
        exception: FlutterError('A RenderFlex overflowed by 25 pixels.'),
        library: 'rendering library',
        context: ErrorDescription('during layout'),
        informationCollector: () sync* {
          for (final line in information) {
            yield DiagnosticsNode.message(line);
          }
        },
      );
    }

    test('κρατά την αλυσίδα των widget', () {
      final result = detailsWith([
        'debugCreator: Column ← Padding ← CallsScreen ← Scaffold',
      ]);

      expect(
        layoutErrorDiagnostics(result),
        contains('debugCreator: Column ← Padding ← CallsScreen ← Scaffold'),
      );
    });

    test('κρατά τη φάση στην οποία συνέβη', () {
      expect(layoutErrorDiagnostics(detailsWith([])), contains('during layout'));
    });

    test('πετά τις γενικές συμβουλές του framework', () {
      final result = layoutErrorDiagnostics(
        detailsWith([
          'debugCreator: Column ← CallsScreen',
          'Consider applying a flex factor (e.g. using an Expanded widget)',
          'This is considered an error condition because it indicates that',
        ]),
      );

      expect(result, isNot(contains('Consider applying')));
      expect(result, isNot(contains('error condition')));
    });

    test('από το ένοχο RenderFlex κρατά μόνο την ταυτότητά του', () {
      final result = layoutErrorDiagnostics(
        detailsWith([
          'The specific RenderFlex in question is: RenderFlex#8e0d2 '
              'OVERFLOWING:\n◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤',
        ]),
      );

      expect(result, contains('RenderFlex#8e0d2'));
      expect(result, isNot(contains('◢◤')));
    });
  });

  // Το φιλτράρισμα παραπάνω δουλεύει σε κείμενο που γράψαμε εμείς. Αυτό εδώ
  // φυλάει το συμβόλαιο με το ίδιο το Flutter: ότι ένα πραγματικό overflow
  // όντως δεν φέρνει στοίβα, και ότι ο debugCreator είναι όντως εκεί.
  testWidgets('πραγματικό overflow δίνει την αλυσίδα, όχι στοίβα', (
    tester,
  ) async {
    FlutterErrorDetails? captured;
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      if (isLayoutErrorMessage(details.exceptionAsString())) {
        captured = details;
      } else {
        previous?.call(details);
      }
    };
    addTearDown(() => FlutterError.onError = previous);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 100,
            child: Column(
              children: [
                SizedBox(height: 80, child: Text('πάνω')),
                SizedBox(height: 45, child: Text('κάτω')),
              ],
            ),
          ),
        ),
      ),
    );

    final details = captured;
    expect(details, isNotNull, reason: 'το overflow δεν έφτασε στον χειριστή');
    expect(
      details!.stack,
      isNull,
      reason: 'αν αποκτήσει στοίβα, η καταγραφή πρέπει να ξαναδεί τη λογική της',
    );
    expect(layoutErrorDiagnostics(details), contains('debugCreator:'));
  });
}
