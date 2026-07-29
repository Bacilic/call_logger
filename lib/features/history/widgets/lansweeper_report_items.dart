import 'lansweeper/lansweeper_report_filter.dart';
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
    host.notifyReportChanged();
  }

  void toggleItem(ReportCallItem item, bool? checked) {
    if (checked == true) {
      host.selectedKeys.add(item.key);
    } else {
      host.selectedKeys.remove(item.key);
    }
    host.notifyReportChanged();
  }

  ReportCallItem? primarySelectedItem(List<ReportCallItem> allItems) {
    for (final item in allItems) {
      if (host.selectedKeys.contains(item.key)) return item;
    }

    return null;
  }

  bool _matchesReportFilter(String state) {
    return lansweeperReportStateMatches(host.reportFilter, state);
  }

  List<ReportCallItem> filterReportItems(List<ReportCallItem> items) {
    return items
        .where((item) => _matchesReportFilter(item.call.lansweeperState ?? ''))
        .toList();
  }
}
