/// Πώς ομαδοποιεί τις κλήσεις η Αναφορά Lansweeper.
enum LansweeperReportGrouping {
  /// Μία ομάδα ανά υπάλληλο — για να ενώνονται οι κλήσεις του ίδιου ανθρώπου.
  byCaller('caller'),

  /// Μία ομάδα ανά ημέρα, η πιο πρόσφατη πρώτη.
  byDay('day');

  const LansweeperReportGrouping(this.storageValue);

  /// Η τιμή που αποθηκεύεται στη ρύθμιση.
  final String storageValue;

  /// Άγνωστη ή κενή τιμή = ανά υπάλληλο, όπως ήταν πάντα.
  static LansweeperReportGrouping fromStorage(String? value) {
    for (final grouping in values) {
      if (grouping.storageValue == value) return grouping;
    }
    return byCaller;
  }
}
