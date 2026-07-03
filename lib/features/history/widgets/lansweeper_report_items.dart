part of 'lansweeper_report_dialog.dart';

mixin LansweeperReportItemsMixin on LansweeperReportDialogStateHost {
  @override
  String _callerLabel(CallModel call) {
    final value = (call.callerText ?? '').trim();
    return value.isEmpty ? '-' : value;
  }

  @override
  String _notes(CallModel call) {
    final issue = (call.issue ?? '').trim();
    if (issue.isNotEmpty) return issue;
    return '-';
  }

  @override
  String _selectedKeysSignature(List<_ReportCallItem> selected) {
    final keys = selected.map((e) => e.key).toList()..sort();
    return keys.join('|');
  }

  @override
  String _combinedSelectedNotes(List<_ReportCallItem> selected) {
    if (selected.isEmpty) return '';
    if (selected.length == 1) return selected.first.notes;
    return selected
        .map((e) {
          final date = DateFormat(
            'dd/MM/yyyy HH:mm',
          ).format(_callDateTime(e.call));
          final details = e.details.isNotEmpty ? ' • ${e.details}' : '';
          return '[$date] ${e.caller}: ${e.notes}$details';
        })
        .join('\n');
  }

  @override
  String _combinedGeminiIssue(List<_ReportCallItem> selected) {
    if (selected.isEmpty) return '';
    if (selected.length == 1) {
      return (selected.first.call.issue ?? '').trim();
    }
    final parts = <String>[];
    for (final item in selected) {
      final issue = (item.call.issue ?? '').trim();
      if (issue.isEmpty) continue;
      final date = DateFormat('dd/MM/yyyy HH:mm').format(_callDateTime(item.call));
      parts.add('[$date] ${item.caller}: $issue');
    }
    return parts.join('\n');
  }

  @override
  String _combinedUniqueCallField(
    List<_ReportCallItem> selected,
    String? Function(CallModel call) read,
  ) {
    final values = <String>{};
    for (final item in selected) {
      final value = (read(item.call) ?? '').trim();
      if (value.isNotEmpty) values.add(value);
    }
    return values.join(', ');
  }

  @override
  String _details(CallModel call) {
    final parts = <String>[];
    final equipmentCode = (call.equipmentText ?? '').trim();
    final department = (call.departmentText ?? '').trim();
    final problemCategory = (call.category ?? '').trim();

    if (equipmentCode.isNotEmpty) {
      parts.add('Κωδικός εξοπλισμού: $equipmentCode');
    }
    if (department.isNotEmpty) {
      parts.add('Τμήμα: $department');
    }
    if (problemCategory.isNotEmpty) {
      parts.add('Κατηγορία προβλήματος: $problemCategory');
    }

    return parts.join(' • ');
  }

  @override
  String _durationLabel(int seconds) {
    final safe = seconds < 0 ? 0 : seconds;
    final h = safe ~/ 3600;
    final m = (safe % 3600) ~/ 60;
    final s = safe % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  String _totalDurationLabel(int totalSeconds) {
    final safe = totalSeconds < 0 ? 0 : totalSeconds;
    final totalMinutes = (safe / 60).ceil();
    if (totalMinutes >= 60) {
      final hours = totalMinutes ~/ 60;
      final mins = totalMinutes % 60;
      return '$hours ώρ ${mins.toString().padLeft(2, '0')} λ';
    }
    return '$totalMinutes λ';
  }

  DateTime _callDateTime(CallModel call) {
    final dateRaw = (call.date ?? '').trim();
    final timeRaw = (call.time ?? '').trim();
    final parsed = DateTime.tryParse('$dateRaw $timeRaw');
    return parsed ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  @override
  List<_ReportCallItem> _toItems(List<CallModel> calls) {
    return calls.indexed.map((entry) {
      final i = entry.$1;
      final call = entry.$2;
      final id = call.id;
      final key = id != null ? 'id_$id' : 'idx_$i';
      return _ReportCallItem(
        key: key,
        call: call,
        caller: _callerLabel(call),
        notes: _notes(call),
        details: _details(call),
        durationSeconds: call.duration ?? 0,
      );
    }).toList();
  }

  Map<String, List<_ReportCallItem>> _groupByCaller(
    List<_ReportCallItem> items,
  ) {
    final grouped = <String, List<_ReportCallItem>>{};
    for (final item in items) {
      grouped.putIfAbsent(item.caller, () => <_ReportCallItem>[]).add(item);
    }
    return grouped;
  }

  LansweeperReportCallRowData _toRowData(_ReportCallItem item) {
    final state = (item.call.lansweeperState ?? LansweeperSyncState.unsent)
        .trim();
    return LansweeperReportCallRowData(
      key: item.key,
      call: item.call,
      dateLabel: DateFormat(
        'dd/MM/yyyy HH:mm',
      ).format(_callDateTime(item.call)),
      durationLabel: _durationLabel(item.durationSeconds),
      lansweeperState: state,
      ticketId: item.call.lansweeperMainTicketId,
      notes: item.notes,
      details: item.details,
      durationSeconds: item.durationSeconds,
    );
  }

  Map<String, List<LansweeperReportCallRowData>> _groupedRowData(
    Map<String, List<_ReportCallItem>> grouped,
  ) {
    return grouped.map(
      (caller, callerItems) =>
          MapEntry(caller, callerItems.map(_toRowData).toList()),
    );
  }

  @override
  void _toggleGroup(List<_ReportCallItem> items, bool? checked) {
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
  void _toggleItem(_ReportCallItem item, bool? checked) {
    setState(() {
      if (checked == true) {
        _selectedKeys.add(item.key);
      } else {
        _selectedKeys.remove(item.key);
      }
    });
  }

  @override
  _ReportCallItem? _primarySelectedItem(List<_ReportCallItem> allItems) {
    for (final item in allItems) {
      if (_selectedKeys.contains(item.key)) return item;
    }
    return null;
  }

  @override
  String _normalizedLansweeperState(_ReportCallItem item) {
    final state = (item.call.lansweeperState ?? LansweeperSyncState.unsent)
        .trim();
    return state.isEmpty ? LansweeperSyncState.unsent : state;
  }

  @override
  bool _isRegisteredCall(_ReportCallItem item) =>
      _normalizedLansweeperState(item) == LansweeperSyncState.sent;

  @override
  bool _isFailedCall(_ReportCallItem item) =>
      _normalizedLansweeperState(item) == LansweeperSyncState.failed;

  bool _matchesReportFilter(String state) {
    final normalized = state.trim().isEmpty
        ? LansweeperSyncState.unsent
        : state.trim();
    return switch (_reportFilter) {
      _LansweeperReportFilter.unsentOnly =>
        normalized == LansweeperSyncState.unsent,
      _LansweeperReportFilter.sentOnly => normalized == LansweeperSyncState.sent,
      _LansweeperReportFilter.excludedOnly =>
        normalized == LansweeperSyncState.excluded,
      _LansweeperReportFilter.failedOnly =>
        normalized == LansweeperSyncState.failed,
      _LansweeperReportFilter.all => true,
    };
  }

  @override
  List<_ReportCallItem> _filterReportItems(List<_ReportCallItem> items) {
    return items
        .where(
          (item) => _matchesReportFilter(item.call.lansweeperState ?? ''),
        )
        .toList();
  }
}

enum _LansweeperReportFilter {
  unsentOnly,
  sentOnly,
  excludedOnly,
  failedOnly,
  all,
}

enum _UnsentTicketChoice { clear, retain, cancel }

enum _DuplicateTicketAction { proceed, changeId, cancel }

class _ReportCallItem {
  const _ReportCallItem({
    required this.key,
    required this.call,
    required this.caller,
    required this.notes,
    required this.details,
    required this.durationSeconds,
  });

  final String key;
  final CallModel call;
  final String caller;
  final String notes;
  final String details;
  final int durationSeconds;
}
