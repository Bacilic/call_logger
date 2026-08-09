import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/calls_dashboard_repository.dart';
import '../../../core/database/database_helper.dart';
import '../../calls/models/call_model.dart';
import '../models/lansweeper_report_scope.dart';

/// Το πλαίσιο που δείχνει αυτή τη στιγμή η Αναφορά Lansweeper.
///
/// Το ορίζει όποιος ανοίγει την αναφορά και το αλλάζει ο χρήστης από τα chips
/// της κεφαλίδας της. Δεν κληρονομείται από άλλη οθόνη.
class LansweeperReportScopeNotifier extends Notifier<LansweeperReportScope> {
  @override
  LansweeperReportScope build() => LansweeperReportScope.today;

  void set(LansweeperReportScope scope) => state = scope;
}

final lansweeperReportScopeProvider =
    NotifierProvider<LansweeperReportScopeNotifier, LansweeperReportScope>(
      LansweeperReportScopeNotifier.new,
    );

/// Οι κλήσεις της αναφοράς, με βάση το ενεργό πλαίσιο.
final lansweeperReportCallsProvider = FutureProvider.autoDispose<List<CallModel>>((
  ref,
) async {
  final scope = ref.watch(lansweeperReportScopeProvider);
  final filter = scope.resolveFilter(DateTime.now());
  final db = await DatabaseHelper.instance.database;
  return CallsDashboardRepository(db).getDashboardCalls(filter);
});
