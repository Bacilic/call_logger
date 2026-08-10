import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/calls_dashboard_repository.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/database/settings_repository.dart';
import '../../calls/models/call_model.dart';
import '../models/lansweeper_report_scope.dart';

/// Το πλαίσιο που δείχνει αυτή τη στιγμή η Αναφορά Lansweeper.
///
/// Το ορίζει όποιος ανοίγει την αναφορά και το αλλάζει ο χρήστης από τα chips
/// της κεφαλίδας της. Δεν κληρονομείται από άλλη οθόνη.
class LansweeperReportScopeNotifier extends Notifier<LansweeperReportScope> {
  @override
  LansweeperReportScope build() => LansweeperReportScope.today;

  /// Ορίζει το πλαίσιο και θυμάται την επιλογή για την επόμενη φορά.
  ///
  /// Τα φίλτρα των Στατιστικών δεν αποθηκεύονται: είναι το πλαίσιο μιας
  /// συγκεκριμένης εισόδου, όχι επιλογή του χρήστη μέσα στην αναφορά.
  void set(LansweeperReportScope scope) {
    state = scope;
    if (LansweeperReportScope.presets.contains(scope.range)) {
      unawaited(_persistRange(scope.range));
    }
  }

  /// Επαναφέρει το διάστημα που είχε διαλέξει τελευταία ο χρήστης.
  ///
  /// Χωρίς αποθηκευμένη τιμή πέφτει στο «Σήμερα» — η καθημερινή δουλειά.
  Future<void> restoreRememberedRange() async {
    final db = await DatabaseHelper.instance.database;
    final raw = await SettingsRepository(
      db,
    ).getSetting(kLansweeperReportRangeSettingKey);
    if (!ref.mounted) return;
    final range =
        LansweeperReportRangeSetting.decode(raw) ?? LansweeperReportRange.today;
    state = LansweeperReportScope.range(range);
  }

  Future<void> _persistRange(LansweeperReportRange range) async {
    final db = await DatabaseHelper.instance.database;
    await SettingsRepository(db).saveSetting(
      kLansweeperReportRangeSettingKey,
      LansweeperReportRangeSetting.encode(range),
    );
  }
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
