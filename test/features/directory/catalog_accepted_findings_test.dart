// Αποδοχή ευρημάτων του «Ελέγχου δεδομένων»: ποια κάρτα κρύβεται, και πότε
// ξαναβγαίνει επειδή άλλαξαν οι εγγραφές της.
//
//   flutter test test/features/directory/catalog_accepted_findings_test.dart

import 'package:call_logger/features/directory/models/catalog_accepted_findings.dart';
import 'package:call_logger/features/directory/models/catalog_validation_finding.dart';
import 'package:flutter_test/flutter_test.dart';

CatalogFindingRecord _record(CatalogEntityKind kind, int id) =>
    CatalogFindingRecord(
      kind: kind,
      entityId: id,
      label: '$id',
      focusedField: 'phone',
    );

CatalogValidationFinding _phoneEquals({
  String code = '2589',
  int userId = 46,
  int equipmentId = 12,
}) => CatalogValidationFinding(
  type: CatalogFindingType.phoneEquipmentCode,
  message: 'Το $code είναι καταχωρημένος κωδικός εξοπλισμού',
  subject: code,
  records: [
    _record(CatalogEntityKind.user, userId),
    _record(CatalogEntityKind.equipment, equipmentId),
  ],
);

CatalogValidationFinding _sameName(List<int> userIds) =>
    CatalogValidationFinding(
      type: CatalogFindingType.nameConflict,
      message: 'Ίδιο ονοματεπώνυμο',
      records: [for (final id in userIds) _record(CatalogEntityKind.user, id)],
    );

void main() {
  group('αποτύπωμα αποδοχής', () {
    test('ίδιες εγγραφές με άλλη σειρά → ίδιο αποτύπωμα', () {
      expect(_sameName([3, 9]).acceptKey, _sameName([9, 3]).acceptKey);
    });

    test('ο ίδιος αριθμός σε άλλον υπάλληλο → νέο αποτύπωμα', () {
      expect(
        _phoneEquals(userId: 46).acceptKey,
        isNot(_phoneEquals(userId: 78).acceptKey),
      );
    });

    test('τρίτη συνώνυμη εγγραφή → νέο αποτύπωμα', () {
      expect(
        _sameName([3, 9]).acceptKey,
        isNot(_sameName([3, 9, 15]).acceptKey),
      );
    });

    test('«ίδιο τηλέφωνο σε διαφορετικά τμήματα» δεν δέχεται αποδοχή', () {
      final finding = CatalogValidationFinding(
        type: CatalogFindingType.crossDepartmentPhone,
        message: 'Το 2519 σε 2 τμήματα',
        records: [
          _record(CatalogEntityKind.user, 1),
          _record(CatalogEntityKind.user, 2),
        ],
      );
      expect(finding.acceptKey, isNull);
    });
  });

  group('χωρισμός σε ανοιχτά και αποδεκτά', () {
    test('η αποδεκτή κάρτα φεύγει από τα ανοιχτά, οι άλλες μένουν', () {
      final accepted = _phoneEquals(code: '2589');
      final open = _phoneEquals(code: '2832', userId: 5, equipmentId: 7);
      final split = CatalogAcceptedFindings.none
          .withKey(accepted.acceptKey!)
          .partition([accepted, open]);
      expect(split.open, [open]);
      expect(split.accepted, [accepted]);
    });

    test('αποδοχή που ξαναγίνεται ανοιχτή με «Επαναφορά»', () {
      final finding = _sameName([3, 9]);
      final restored = CatalogAcceptedFindings.none
          .withKey(finding.acceptKey!)
          .withoutKey(finding.acceptKey!);
      expect(restored.partition([finding]).open, [finding]);
    });

    test('η αποθηκευμένη μορφή διαβάζεται πίσω ίδια', () {
      final stored = CatalogAcceptedFindings.none
          .withKey(_sameName([3, 9]).acceptKey!)
          .toRawJson();
      expect(
        CatalogAcceptedFindings.fromRawJson(
          stored,
        ).isAccepted(_sameName([9, 3])),
        isTrue,
      );
    });

    test('αλλοιωμένη αποθηκευμένη τιμή δεν κρύβει τίποτα', () {
      final split = CatalogAcceptedFindings.fromRawJson('{χαλασμένο').partition(
        [
          _sameName([3, 9]),
        ],
      );
      expect(split.accepted, isEmpty);
    });
  });
}
