import '../models/lansweeper_sync_state.dart';
import 'lansweeper/lansweeper_report_item_mapper.dart';
import 'lansweeper_report_dialog.dart';

/// Επιλογή και φιλτράρισμα στοιχείων της αναφοράς (κλήσεις ανά καλούντα).
///
/// Συνεργάτης του [LansweeperReportDialogState] (Σύνθεση).
class LansweeperReportSelection {
  LansweeperReportSelection(this.host);

  final LansweeperReportDialogState host;

  void toggleGroup(List<ReportCallItem> items, bool? checked) {
    if (checked == true) {
      for (final item in items) {
        host.selectedKeys.add(item.key);
      }
    } else {
      for (final item in items) {
        host.selectedKeys.remove(item.key);
      }
    }
    // Αλλαγή επιλογής = πιθανή αλλαγή τμημάτων· μια επιλογή αιτούντα από την
    // προηγούμενη ομάδα κλήσεων δεν ισχύει πια.
    host.selectedRequesterUsername = null;
    host.notifyReportChanged();
  }

  void toggleItem(ReportCallItem item, bool? checked) {
    if (checked == true) {
      host.selectedKeys.add(item.key);
    } else {
      host.selectedKeys.remove(item.key);
    }
    // Αλλαγή επιλογής = πιθανή αλλαγή τμημάτων· μια επιλογή αιτούντα από την
    // προηγούμενη ομάδα κλήσεων δεν ισχύει πια.
    host.selectedRequesterUsername = null;
    host.notifyReportChanged();
  }

  ReportCallItem? primarySelectedItem(List<ReportCallItem> allItems) {
    for (final item in allItems) {
      if (host.selectedKeys.contains(item.key)) return item;
    }

    return null;
  }

  /// Η αναφορά είναι ουρά εργασίας: δείχνει ό,τι μένει να καταχωρηθεί.
  ///
  /// Το «τι έγινε με τις υπόλοιπες» απαντιέται στο Ιστορικό Κλήσεων, που έχει
  /// αναζήτηση, ταξινόμηση και στήλες. Ως τώρα η αναφορά προσπαθούσε να κάνει
  /// και τις δύο δουλειές με δεύτερη μπάρα φίλτρων, σε μισό πλάτος.
  List<ReportCallItem> filterReportItems(List<ReportCallItem> items) {
    return items
        .where(
          (item) => LansweeperSyncState.isQueued(item.call.lansweeperState),
        )
        .toList();
  }
}
