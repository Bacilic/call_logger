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
  bool databaseRestored = true,
  bool mapsSkipped = false,
  bool toolImagesSkipped = false,
  bool lexiconSkipped = false,
  bool lampDbSkipped = false,
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
  databaseRestored: databaseRestored,
  mapsSkipped: mapsSkipped,
  toolImagesSkipped: toolImagesSkipped,
  lexiconSkipped: lexiconSkipped,
  lampDbSkipped: lampDbSkipped,
);

RestoreReportItem _item(List<RestoreReportItem> items, String label) =>
    items.singleWhere((i) => i.label == label);

void main() {
  test('η βάση είναι πάντα πρώτη, και επιτυχής όταν επαναφέρθηκε', () {
    final items = _build();
    expect(items.first.label, 'Βάση');
    expect(items.first.status, RestoreReportStatus.success);
  });

  test('βάση που δεν επιλέχθηκε δεν είναι ούτε σφάλμα ούτε έλλειψη', () {
    final items = _build(databaseRestored: false);
    expect(items.first.label, 'Βάση');
    expect(items.first.status, RestoreReportStatus.skipped);
    expect(items.first.detail, 'Δεν επιλέχθηκε για επαναφορά');
  });

  test(
    'στοιχείο που ξετσεκάρισε ο χρήστης λέει ΓΙΑΤΙ λείπει — δεν το περνά για έλλειψη',
    () {
      final items = _build(
        mapsSkipped: true,
        toolImagesSkipped: true,
        lexiconSkipped: true,
        lampDbSkipped: true,
      );
      for (final label in [
        'Κατόψεις',
        'Εικονίδια εργαλείων',
        'Λεξικό',
        'Βάση Λάμπας',
      ]) {
        final item = _item(items, label);
        expect(item.status, RestoreReportStatus.skipped, reason: label);
        expect(item.detail, 'Δεν επιλέχθηκε για επαναφορά', reason: label);
      }
    },
  );

  test(
    'η παράλειψη νικά την αποτυχία στην αναφορά της Λάμπας — δεν αντιγράφηκε καν',
    () {
      final items = _build(lampDbSkipped: true, lampDbFailed: true);
      expect(_item(items, 'Βάση Λάμπας').status, RestoreReportStatus.skipped);
    },
  );

  test('στοιχείο που δεν υπήρχε στο αντίγραφο = προειδοποίηση, όχι σφάλμα', () {
    final items = _build();
    for (final label in [
      'Κατόψεις',
      'Εικονίδια εργαλείων',
      'Λεξικό',
      'Βάση Λάμπας',
    ]) {
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

  test(
    'έστω μία αποτυχία αντιγραφής σημαίνει το στοιχείο κόκκινο, με τα δύο πλήθη',
    () {
      final items = _build(
        mapImagesCopied: 4,
        mapImagesFailed: 1,
        lampDbFailed: true,
      );
      final maps = _item(items, 'Κατόψεις');
      expect(maps.status, RestoreReportStatus.failure);
      expect(maps.detail, contains('4'));
      expect(maps.detail, contains('1'));
      expect(_item(items, 'Βάση Λάμπας').status, RestoreReportStatus.failure);
    },
  );

  test('η σύνδεση κατόψεων εμφανίζεται μόνο όταν έγινε', () {
    expect(
      _build().any((i) => i.label == 'Σύνδεση κατόψεων'),
      isFalse,
      reason: 'Χωρίς επανασυνδέσεις, η γραμμή θα ήταν θόρυβος',
    );
    final withRelink = _build(imagesRelinked: 2);
    expect(
      _item(withRelink, 'Σύνδεση κατόψεων').status,
      RestoreReportStatus.success,
    );
    expect(_item(withRelink, 'Σύνδεση κατόψεων').detail, contains('2'));
  });

  test(
    'το απλό κείμενο έχει μία γραμμή ανά στοιχείο — όχι «σούπα» σε μία σειρά',
    () {
      final text = restoreReportPlainText(_build(mapImagesCopied: 5));
      expect(text.split('\n').length, 5);
      expect(text, contains('Βάση: Επαναφέρθηκε'));
      expect(text, isNot(contains(' · ')));
    },
  );
}
