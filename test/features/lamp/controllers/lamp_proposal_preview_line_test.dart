import 'package:call_logger/core/database/old_database/lamp_issue_resolution_models.dart';
import 'package:call_logger/features/lamp/controllers/lamp_issue_resolution_controller.dart';
import 'package:flutter_test/flutter_test.dart';

LampIssueResolutionProposal _minimalProposal({
  int? row = 2350,
  String? column = 'model',
  String? proposedMatch = 'μοντέλο=410',
  String? sheet,
}) {
  return LampIssueResolutionProposal(
    issueType: LampIssueType.duplicateAssetNo,
    issueIds: const <int>[1],
    sheet: sheet,
    row: row,
    column: column,
    originalValue: '410',
    proposedAction: LampIssueResolutionAction.autoFix,
    proposedMatch: proposedMatch,
    confidence: 90,
    notes: '',
  );
}

String _modelColumnLabel(String? column) {
  if (column == 'model') return 'μοντέλο';
  return column ?? '-';
}

void main() {
  group('lampProposalPreviewLine', () {
    test(
      'χρησιμοποιεί «Κωδικός εξοπλισμού» και «πεδίο» αντί «γραμμή»/«στήλη»',
      () {
        final line = lampProposalPreviewLine(
          _minimalProposal(),
          _modelColumnLabel,
        );

        expect(line, startsWith('- Κωδικός εξοπλισμού=2350 πεδίο='));
        expect(line, isNot(contains('γραμμή=')));
        expect(line, isNot(contains('στήλη=')));
      },
    );

    test('row=null εμφανίζει «Κωδικός εξοπλισμού=-»', () {
      final line = lampProposalPreviewLine(
        _minimalProposal(row: null),
        _modelColumnLabel,
      );

      expect(line, startsWith('- Κωδικός εξοπλισμού=-'));
    });
  });

  group('η ονομασία του κλειδιού ακολουθεί τον πίνακα', () {
    test('χωρίς πίνακα μένει ο εξοπλισμός', () {
      expect(
        lampProposalPreviewLine(_minimalProposal(), _modelColumnLabel),
        startsWith('- Κωδικός εξοπλισμού=2350'),
      );
    });

    test('γραφείο, υπάλληλος, μοντέλο και σύμβαση λέγονται με το όνομά τους', () {
      const expected = <String, String>{
        'offices': 'Κωδικός γραφείου',
        'owners': 'Κωδικός υπαλλήλου',
        'model': 'Κωδικός μοντέλου',
        'contracts': 'Κωδικός σύμβασης',
        'equipment': 'Κωδικός εξοπλισμού',
      };
      expected.forEach((sheet, label) {
        expect(
          lampProposalPreviewLine(
            _minimalProposal(sheet: sheet),
            _modelColumnLabel,
          ),
          startsWith('- $label=2350'),
          reason: 'ο πίνακας «$sheet» πρέπει να λέγεται «$label»',
        );
      });
    });
  });
}
