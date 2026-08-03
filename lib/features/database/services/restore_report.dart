/// Δομημένη αναφορά αποτελέσματος επαναφοράς — μία γραμμή ανά στοιχείο.
///
/// Αντικαθιστά το παλιό μήνυμα-«σούπα» («βάση: επαναφέρθηκε · κατόψεις: …»):
/// κάθε στοιχείο έχει ετικέτα, περιγραφή και κατάσταση, ώστε η διεπαφή να το
/// αποδίδει ως λίστα με εικονίδιο και χρώμα.
library;

/// Κατάσταση στοιχείου: καθορίζει εικονίδιο και χρώμα στη διεπαφή.
enum RestoreReportStatus {
  /// Το στοιχείο επαναφέρθηκε (πράσινο).
  success,

  /// Το στοιχείο δεν υπήρχε στο αντίγραφο — δεν είναι σφάλμα (πορτοκαλί).
  warning,

  /// Η επαναφορά του στοιχείου απέτυχε (κόκκινο).
  failure,
}

/// Μία γραμμή της αναφοράς: «Ετικέτα: Τι έγινε».
class RestoreReportItem {
  const RestoreReportItem({
    required this.label,
    required this.detail,
    required this.status,
  });

  final String label;
  final String detail;
  final RestoreReportStatus status;
}

const String _notFoundPlural = 'Δεν βρέθηκαν στο συμπιεσμένο αρχείο';
const String _notFoundSingular = 'Δεν βρέθηκε στο συμπιεσμένο αρχείο';

/// Χτίζει τις γραμμές της αναφοράς από τα μετρήσιμα αποτελέσματα.
///
/// Καλείται μόνο μετά από επιτυχή επαναφορά της βάσης — γι' αυτό η πρώτη
/// γραμμή είναι πάντα «Βάση: Επαναφέρθηκε». Στοιχείο με έστω μία αποτυχία
/// σημαίνεται κόκκινο· στοιχείο που απλώς δεν υπήρχε στο αντίγραφο, πορτοκαλί.
List<RestoreReportItem> buildRestoreReportItems({
  required int mapImagesCopied,
  required int mapImagesFailed,
  required int toolImagesCopied,
  required int toolImagesFailed,
  required int dictionaryFilesCopied,
  required int dictionaryFilesFailed,
  required bool lampDbRestored,
  required bool lampDbFailed,
  required int imagesRelinked,
}) {
  return [
    const RestoreReportItem(
      label: 'Βάση',
      detail: 'Επαναφέρθηκε',
      status: RestoreReportStatus.success,
    ),
    _countedItem(
      label: 'Κατόψεις',
      copied: mapImagesCopied,
      failed: mapImagesFailed,
      notFoundDetail: _notFoundPlural,
    ),
    _countedItem(
      label: 'Εικονίδια εργαλείων',
      copied: toolImagesCopied,
      failed: toolImagesFailed,
      notFoundDetail: _notFoundPlural,
    ),
    _countedItem(
      label: 'Λεξικό',
      copied: dictionaryFilesCopied,
      failed: dictionaryFilesFailed,
      notFoundDetail: _notFoundSingular,
      unit: 'αρχεία',
    ),
    if (lampDbFailed)
      const RestoreReportItem(
        label: 'Βάση Λάμπας',
        detail: 'Αποτυχία επαναφοράς',
        status: RestoreReportStatus.failure,
      )
    else if (lampDbRestored)
      const RestoreReportItem(
        label: 'Βάση Λάμπας',
        detail: 'Επαναφέρθηκε',
        status: RestoreReportStatus.success,
      )
    else
      const RestoreReportItem(
        label: 'Βάση Λάμπας',
        detail: _notFoundSingular,
        status: RestoreReportStatus.warning,
      ),
    if (imagesRelinked > 0)
      RestoreReportItem(
        label: 'Σύνδεση κατόψεων',
        detail: 'Επανασυνδέθηκαν ($imagesRelinked)',
        status: RestoreReportStatus.success,
      ),
  ];
}

RestoreReportItem _countedItem({
  required String label,
  required int copied,
  required int failed,
  required String notFoundDetail,
  String? unit,
}) {
  String withUnit(int n) => unit == null ? '$n' : '$n $unit';

  if (failed > 0) {
    return RestoreReportItem(
      label: label,
      detail: copied > 0
          ? 'Επαναφέρθηκαν ${withUnit(copied)}, απέτυχαν ${withUnit(failed)}'
          : 'Αποτυχία επαναφοράς (${withUnit(failed)})',
      status: RestoreReportStatus.failure,
    );
  }
  if (copied > 0) {
    return RestoreReportItem(
      label: label,
      detail: 'Επαναφέρθηκαν (${withUnit(copied)})',
      status: RestoreReportStatus.success,
    );
  }
  return RestoreReportItem(
    label: label,
    detail: notFoundDetail,
    status: RestoreReportStatus.warning,
  );
}

/// Απλό κείμενο της αναφοράς — για καταγραφή/μεταφορά εκτός διεπαφής.
String restoreReportPlainText(List<RestoreReportItem> items) =>
    items.map((i) => '${i.label}: ${i.detail}').join('\n');
