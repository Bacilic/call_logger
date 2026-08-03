// Λογική της δομημένης αναφοράς επαναφοράς: κάθε στοιχείο παίρνει τη σωστή
// κατάσταση (επιτυχία / δεν βρέθηκε / αποτυχία) από τα μετρήσιμα αποτελέσματα.
//
//   flutter test test/features/database/services/restore_report_test.dart

import 'package:call_logger/features/database/services/restore_report.dart';
import 'package:flutter_test/flutter_test.dart';

List<RestoreReportItem> _build({
  int mapImagesCopied = 0,
  int mapImagesFailed = 0,
  int toolImagesCopied = 0,
  int toolImagesFailed = 0,
  int dictionaryFilesCopied = 0,
  int dictionaryFilesFailed = 0,
  bool lampDbRestored = false,
  bool lampDbFailed = false,
  int imagesRelinked = 0,
}) => buildRestoreReportItems(
  mapImagesCopied: mapImagesCopied,
  mapImagesFailed: mapImagesFailed,
  toolImagesCopied: toolImagesCopied,
  toolImagesFailed: toolImagesFailed,
  dictionaryFilesCopied: dictionaryFilesCopied,
  dictionaryFilesFailed: dictionaryFilesFailed,
  lampDbRestored: lampDbRestored,
  lampDbFailed: lampDbFailed,
  imagesRelinked: imagesRelinked,
);

RestoreReportItem _item(List<RestoreReportItem> items, String label) =>
    items.singleWhere((i) => i.label == label);

void main() {
  test('η βάση είναι πάντα πρώτη και επιτυχής — η αναφορά χτίζεται μόνο μετά από επιτυχία', () {
    final items = _build();
    expect(items.first.label, 'Βάση');
    expect(items.first.status, RestoreReportStatus.success);
  });

  test('στοιχείο που δεν υπήρχε στο αντίγραφο = προειδοποίηση, όχι σφάλμα', () {
    final items = _build();
    for (final label in ['Κατόψεις', 'Εικονίδια εργαλείων', 'Λεξικό', 'Βάση Λάμπας']) {
      final item = _item(items, label);
      expect(item.status, RestoreReportStatus.warning, reason: label);
      expect(item.detail, contains('στο συμπιεσμένο αρχείο'), reason: label);
    }
  });

  test('στοιχείο που επαναφέρθηκε = επιτυχία με το πλήθος του', () {
    final items = _build(
      mapImagesCopied: 5,
      toolImagesCopied: 3,
      dictionaryFilesCopied: 2,
      lampDbRestored: true,
    );
    expect(_item(items, 'Κατόψεις').status, RestoreReportStatus.success);
    expect(_item(items, 'Κατόψεις').detail, contains('5'));
    expect(_item(items, 'Εικονίδια εργαλείων').detail, contains('3'));
    expect(_item(items, 'Λεξικό').detail, contains('2 αρχεία'));
    expect(_item(items, 'Βάση Λάμπας').status, RestoreReportStatus.success);
  });

  test('έστω μία αποτυχία αντιγραφής σημαίνει το στοιχείο κόκκινο, με τα δύο πλήθη', () {
    final items = _build(mapImagesCopied: 4, mapImagesFailed: 1, lampDbFailed: true);
    final maps = _item(items, 'Κατόψεις');
    expect(maps.status, RestoreReportStatus.failure);
    expect(maps.detail, contains('4'));
    expect(maps.detail, contains('1'));
    expect(_item(items, 'Βάση Λάμπας').status, RestoreReportStatus.failure);
  });

  test('η σύνδεση κατόψεων εμφανίζεται μόνο όταν έγινε', () {
    expect(
      _build().any((i) => i.label == 'Σύνδεση κατόψεων'),
      isFalse,
      reason: 'Χωρίς επανασυνδέσεις, η γραμμή θα ήταν θόρυβος',
    );
    final withRelink = _build(imagesRelinked: 2);
    expect(_item(withRelink, 'Σύνδεση κατόψεων').status, RestoreReportStatus.success);
    expect(_item(withRelink, 'Σύνδεση κατόψεων').detail, contains('2'));
  });

  test('το απλό κείμενο έχει μία γραμμή ανά στοιχείο — όχι «σούπα» σε μία σειρά', () {
    final text = restoreReportPlainText(_build(mapImagesCopied: 5));
    expect(text.split('\n').length, 5);
    expect(text, contains('Βάση: Επαναφέρθηκε'));
    expect(text, isNot(contains(' · ')));
  });
}
