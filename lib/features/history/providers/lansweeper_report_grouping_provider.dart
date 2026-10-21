import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/profile_settings.dart';
import '../../../core/services/scoped_settings.dart';
import '../models/lansweeper_report_grouping.dart';

/// Η ομαδοποίηση της Αναφοράς Lansweeper, **προσωπική**: ο καθένας ξαναβρίσκει
/// την αναφορά όπως την άφησε.
///
/// Η ανάγνωση και η εγγραφή ζουν εδώ, όχι στο κουμπί.
class LansweeperReportGroupingNotifier
    extends AsyncNotifier<LansweeperReportGrouping> {
  @override
  Future<LansweeperReportGrouping> build() async {
    return LansweeperReportGrouping.fromStorage(
      await ScopedSettings.getString(
        ProfileSettingKeys.lansweeperReportGrouping,
      ),
    );
  }

  /// Η οθόνη ενημερώνεται πρώτη· η εγγραφή αφορά την επόμενη φορά.
  Future<void> select(LansweeperReportGrouping grouping) async {
    state = AsyncValue.data(grouping);
    await ScopedSettings.setString(
      ProfileSettingKeys.lansweeperReportGrouping,
      grouping.storageValue,
    );
  }
}

final lansweeperReportGroupingProvider =
    AsyncNotifierProvider<
      LansweeperReportGroupingNotifier,
      LansweeperReportGrouping
    >(LansweeperReportGroupingNotifier.new);
