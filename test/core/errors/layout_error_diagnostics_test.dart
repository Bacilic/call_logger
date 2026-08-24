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
        isLayoutErrorMessage(
          'A RenderFlex overflowed by 25 pixels on the '
          'bottom.',
        ),
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
      expect(
        layoutErrorDiagnostics(detailsWith([])),
        contains('during layout'),
      );
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
      reason:
          'αν αποκτήσει στοίβα, η καταγραφή πρέπει να ξαναδεί τη λογική της',
    );
    expect(layoutErrorDiagnostics(details), contains('debugCreator:'));
  });

  // Το Flutter τυπώνει μόνο 12 επίπεδα αλυσίδας και τα δώδεκα πρώτα είναι
  // σχεδόν πάντα δικά του ενδιάμεσα (Material, SafeArea, MediaQuery…). Στην
  // πράξη η αλυσίδα κοβόταν με «⋯» ακριβώς εκεί όπου θα άρχιζαν τα δικά μας
  // ονόματα — δηλαδή η εγγραφή έλεγε «ξεχείλισε κατά 9 pixel» και δεν οδηγούσε
  // σε κανένα αρχείο. Εύρημα 24/08/2026, σε πραγματικό σφάλμα του χρήστη.
  testWidgets('η αλυσίδα φτάνει στα ΔΙΚΑ ΜΑΣ widget, όχι μόνο στα ενδιάμεσα', (
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
      const MaterialApp(home: Scaffold(body: _DeepNest())),
    );

    final details = captured;
    expect(details, isNotNull, reason: 'το overflow δεν έφτασε στον χειριστή');

    final diagnostics = layoutErrorDiagnostics(details!);
    expect(
      diagnostics,
      contains('_DeepNest'),
      reason:
          'Το όνομα που εξηγεί πού ξεχείλισε βρίσκεται πάνω από δώδεκα επίπεδα '
          'μακριά. Χωρίς αυτό, η εγγραφή στο ημερολόγιο δεν οδηγεί πουθενά.',
    );
  });
}

/// Ξεχειλίζει επίτηδες, με πολλά δικά μας επίπεδα ανάμεσα στο σημείο του
/// σφάλματος και στο όνομα που το εξηγεί.
class _DeepNest extends StatelessWidget {
  const _DeepNest();

  @override
  Widget build(BuildContext context) =>
      const _NestLevel(remaining: 14, child: _TightBox());
}

class _NestLevel extends StatelessWidget {
  const _NestLevel({required this.remaining, required this.child});

  final int remaining;
  final Widget child;

  @override
  Widget build(BuildContext context) => remaining <= 0
      ? child
      : _NestLevel(remaining: remaining - 1, child: child);
}

class _TightBox extends StatelessWidget {
  const _TightBox();

  @override
  Widget build(BuildContext context) => const SizedBox(
    height: 100,
    child: Column(
      children: [
        SizedBox(height: 80, child: Text('πάνω')),
        SizedBox(height: 45, child: Text('κάτω')),
      ],
    ),
  );
}
