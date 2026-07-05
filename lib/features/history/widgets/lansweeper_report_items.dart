part of 'lansweeper_report_dialog.dart';



mixin LansweeperReportItemsMixin on LansweeperReportDialogStateHost {

  @override

  void _toggleGroup(List<ReportCallItem> items, bool? checked) {

    setState(() {

      if (checked == true) {

        for (final item in items) {

          _selectedKeys.add(item.key);

        }

      } else {

        for (final item in items) {

          _selectedKeys.remove(item.key);

        }

      }

    });

  }



  @override

  void _toggleItem(ReportCallItem item, bool? checked) {

    setState(() {

      if (checked == true) {

        _selectedKeys.add(item.key);

      } else {

        _selectedKeys.remove(item.key);

      }

    });

  }



  @override

  ReportCallItem? _primarySelectedItem(List<ReportCallItem> allItems) {

    for (final item in allItems) {

      if (_selectedKeys.contains(item.key)) return item;

    }

    return null;

  }



  bool _matchesReportFilter(String state) {

    return lansweeperReportStateMatches(_reportFilter, state);

  }



  @override

  List<ReportCallItem> _filterReportItems(List<ReportCallItem> items) {

    return items

        .where(

          (item) => _matchesReportFilter(item.call.lansweeperState ?? ''),

        )

        .toList();

  }

}


