import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/calls_repository.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/models/owner_filter.dart';
import '../../../core/services/current_operator.dart';
import '../../../core/services/owner_filter_preference.dart';
import '../../../core/services/profile_settings.dart';
import '../../operators/providers/operator_directory_providers.dart';
import '../../operators/utils/owner_filter_options.dart';

/// Οι επιλογές του φίλτρου «χρήστης» για τις κλήσεις — Ιστορικό και αναφορά
/// Lansweeper μοιράζονται την ίδια λίστα, γιατί μιλούν για τα ίδια δεδομένα.
///
/// «Όλοι» πρώτο, μετά τα ονόματα όσων έχουν καταγράψει κλήσεις (αλφαβητικά),
/// και «Χωρίς χρήστη» τελευταίο — μόνο όταν υπάρχουν όντως τέτοιες. Ο τρέχων
/// χρήστης μπαίνει πάντα, ακόμη κι αν δεν έχει καταγράψει καμία.
final callOwnerOptionsProvider =
    FutureProvider.autoDispose<List<OwnerFilterOption>>((ref) async {
      final db = await DatabaseHelper.instance.database;
      final calls = CallsRepository(db);

      final ownerIds = (await calls.getDistinctCallOwnerIds()).toSet();
      final active = CurrentOperator.active;
      if (active?.id != null) ownerIds.add(active!.id!);

      return buildOwnerFilterOptions(
        ownerIds: ownerIds,
        names: await ref.watch(operatorNamesProvider.future),
        hasUnassigned: await calls.hasUnassignedCalls(),
      );
    });

/// Κοινός κορμός των δύο φίλτρων «χρήστης» των κλήσεων: προεπιλογή «Όλοι»,
/// μνήμη στις προσωπικές ρυθμίσεις του κλειδιού που δηλώνει η υποκλάση.
///
/// Η προεπιλογή διαφέρει σκόπιμα από τις Εκκρεμότητες: το Ιστορικό είναι κοινό
/// αρχείο και η ουρά Lansweeper κοινή δουλειά — και όλες οι υπάρχουσες κλήσεις
/// γράφτηκαν πριν υπάρξουν χρήστες, οπότε άλλη προεπιλογή θα έδειχνε κενή
/// οθόνη σε όλους για καιρό. Απόφαση χρήστη, 22/08/2026.
abstract class CallOwnerFilterNotifier extends AsyncNotifier<OwnerFilter> {
  ProfileSettingKey get settingKey;

  @override
  Future<OwnerFilter> build() async {
    final db = await DatabaseHelper.instance.database;
    final stored = await OwnerFilterPreference.read(db, settingKey);
    return stored ?? OwnerFilter.everyone;
  }

  /// Αλλάζει την επιλογή και τη θυμάται — η οθόνη ενημερώνεται πρώτη, η
  /// εγγραφή αφορά την επόμενη φορά.
  Future<void> select(OwnerFilter owner) async {
    state = AsyncValue.data(owner);
    final db = await DatabaseHelper.instance.database;
    await OwnerFilterPreference.write(db, settingKey, owner);
  }
}

/// Το φίλτρο «χρήστης» του Ιστορικού Κλήσεων.
class HistoryOwnerFilterNotifier extends CallOwnerFilterNotifier {
  @override
  ProfileSettingKey get settingKey => ProfileSettingKeys.historyOwnerFilter;
}

final historyOwnerFilterProvider =
    AsyncNotifierProvider<HistoryOwnerFilterNotifier, OwnerFilter>(
      HistoryOwnerFilterNotifier.new,
    );

/// Το φίλτρο «χρήστης» της αναφοράς Lansweeper — ανεξάρτητο από του
/// Ιστορικού, όπως και τα κουμπιά διαστήματος της αναφοράς.
class LansweeperReportOwnerFilterNotifier extends CallOwnerFilterNotifier {
  @override
  ProfileSettingKey get settingKey =>
      ProfileSettingKeys.lansweeperReportOwnerFilter;
}

final lansweeperReportOwnerFilterProvider =
    AsyncNotifierProvider<LansweeperReportOwnerFilterNotifier, OwnerFilter>(
      LansweeperReportOwnerFilterNotifier.new,
    );

/// Αν η [owner] επιλογή αφήνει την κλήση να φανεί.
///
/// Μία συνάρτηση και για την αναφορά (φιλτράρει στη μνήμη) και για όποιον
/// άλλον χρειαστεί τον ίδιο κανόνα — δύο υλοποιήσεις του ίδιου «ανήκει;»
/// κάποια μέρα θα διαφωνήσουν σιωπηλά.
bool callMatchesOwner(OwnerFilter owner, int? createdByOperatorId) {
  if (owner.unassignedOnly) return createdByOperatorId == null;
  final id = owner.operatorId;
  if (id == null) return true;
  return createdByOperatorId == id;
}
