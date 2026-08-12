import 'package:call_logger/features/calls/models/call_refined_source.dart';
import 'package:call_logger/features/history/widgets/call_provenance_icon.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CallProvenanceIcon.iconFor', () {
    test('οι τρεις προελεύσεις δίνουν τρία ανά δύο διακριτά σχήματα', () {
      // Το ζητούμενο δεν είναι ποιο σχήμα παίρνει η κάθε προέλευση αλλά ότι
      // ξεχωρίζουν μεταξύ τους: πριν τη διάκριση όλες έδειχναν αστεράκια και
      // η στήλη «Περιγραφή» έμοιαζε ολόκληρη παραγωγή μηχανής.
      final shapes = <Object>{
        CallProvenanceIcon.iconFor(CallRefinedSource.manual),
        CallProvenanceIcon.iconFor(CallRefinedSource.aiEdited),
        CallProvenanceIcon.iconFor(CallRefinedSource.ai),
      };

      expect(shapes, hasLength(3));
    });

    test('άγνωστη προέλευση κρατά το σχήμα της ΤΝ, δεν περνά για χειρόγραφη', () {
      final manual = CallProvenanceIcon.iconFor(CallRefinedSource.manual);

      for (final unknown in <String?>[null, '', '   ', 'κάτι άλλο']) {
        expect(
          CallProvenanceIcon.iconFor(unknown),
          isNot(manual),
          reason: 'το «$unknown» δεν αποδεικνύει ότι έγραψε ο χρήστης',
        );
        expect(
          CallProvenanceIcon.iconFor(unknown),
          CallProvenanceIcon.iconFor(CallRefinedSource.ai),
        );
      }
    });
  });
}
