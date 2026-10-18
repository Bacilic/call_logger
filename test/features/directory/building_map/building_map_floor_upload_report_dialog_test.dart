// Η αναφορά του «Ανέβασμα κατόψεων στη βάση»: λέει και τι ΔΕΝ ανέβηκε.
//
//   flutter test test/features/directory/building_map/building_map_floor_upload_report_dialog_test.dart

import 'package:call_logger/features/directory/building_map/widgets/building_map_floor_upload_report_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ονομάζει όσα ανέβηκαν και όσα έμειναν πίσω, με την αιτία', () {
    final text = floorPlanUploadReportText(
      uploaded: ['2ος', 'Υπόγειο'],
      notFound: ['3ος'],
      unreadable: ['4ος'],
    );
    expect(text, contains('Ανέβηκαν (2)'));
    expect(text, contains('• Υπόγειο'));
    expect(text, contains('Δεν βρέθηκε εικόνα σε αυτόν τον υπολογιστή (1)'));
    expect(text, contains('• 3ος'));
    expect(text, contains('Η εικόνα δεν διαβάστηκε (1)'));
    expect(text, contains('• 4ος'));
  });

  test('τίποτα να ανέβει: το λέει ρητά', () {
    expect(
      floorPlanUploadReportText(uploaded: [], notFound: [], unreadable: []),
      'Όλες οι κατόψεις έχουν ήδη ανέβει στη βάση.',
    );
  });
}
