import '../../models/lansweeper_sync_state.dart';

enum LansweeperReportFilter {
  unsentOnly,
  sentOnly,
  excludedOnly,
  failedOnly,
  all,
}

String _normalizeLansweeperReportState(String? state) {
  final trimmed = (state ?? '').trim();
  return trimmed.isEmpty ? LansweeperSyncState.unsent : trimmed;
}

bool lansweeperReportStateMatches(
  LansweeperReportFilter filter,
  String? state,
) {
  final normalized = _normalizeLansweeperReportState(state);
  return switch (filter) {
    LansweeperReportFilter.unsentOnly =>
      normalized == LansweeperSyncState.unsent,
    LansweeperReportFilter.sentOnly => normalized == LansweeperSyncState.sent,
    LansweeperReportFilter.excludedOnly =>
      normalized == LansweeperSyncState.excluded,
    LansweeperReportFilter.failedOnly =>
      normalized == LansweeperSyncState.failed,
    LansweeperReportFilter.all => true,
  };
}

class LansweeperReportCategoryCounts {
  const LansweeperReportCategoryCounts({
    required this.unsent,
    required this.sent,
    required this.excluded,
    required this.failed,
    required this.total,
  });

  final int unsent;
  final int sent;
  final int excluded;
  final int failed;
  final int total;

  int forFilter(LansweeperReportFilter filter) {
    return switch (filter) {
      LansweeperReportFilter.unsentOnly => unsent,
      LansweeperReportFilter.sentOnly => sent,
      LansweeperReportFilter.excludedOnly => excluded,
      LansweeperReportFilter.failedOnly => failed,
      LansweeperReportFilter.all => total,
    };
  }
}

LansweeperReportCategoryCounts lansweeperReportCategoryCounts(
  Iterable<String?> states,
) {
  var unsent = 0;
  var sent = 0;
  var excluded = 0;
  var failed = 0;
  var total = 0;

  for (final state in states) {
    total++;
    final normalized = _normalizeLansweeperReportState(state);
    switch (normalized) {
      case LansweeperSyncState.unsent:
        unsent++;
      case LansweeperSyncState.sent:
        sent++;
      case LansweeperSyncState.excluded:
        excluded++;
      case LansweeperSyncState.failed:
        failed++;
      default:
        break;
    }
  }

  return LansweeperReportCategoryCounts(
    unsent: unsent,
    sent: sent,
    excluded: excluded,
    failed: failed,
    total: total,
  );
}
