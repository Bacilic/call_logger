import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/master_dictionary_service.dart';
import 'greek_dictionary_provider.dart';
import 'spell_check_provider.dart';

/// Κατάσταση βαριάς διεργασίας επανελέγχου γλωσσών στο `full_dictionary`.
sealed class LexiconLanguageRecalcState {
  const LexiconLanguageRecalcState();
}

final class LexiconLanguageRecalcIdle extends LexiconLanguageRecalcState {
  const LexiconLanguageRecalcIdle();
}

final class LexiconLanguageRecalcLoading extends LexiconLanguageRecalcState {
  const LexiconLanguageRecalcLoading(this.progress);
  final double progress;
}

final class LexiconLanguageRecalcSuccess extends LexiconLanguageRecalcState {
  const LexiconLanguageRecalcSuccess();
}

final class LexiconLanguageRecalcError extends LexiconLanguageRecalcState {
  const LexiconLanguageRecalcError(this.message);
  final String message;
}

class LexiconLanguageRecalcNotifier extends Notifier<LexiconLanguageRecalcState> {
  @override
  LexiconLanguageRecalcState build() => const LexiconLanguageRecalcIdle();

  Future<void> recalculate() async {
    if (state is LexiconLanguageRecalcLoading) return;
    state = const LexiconLanguageRecalcLoading(0);
    try {
      final master = MasterDictionaryService();
      await master.recalculateAllLanguages(
        onProgress: (p) {
          state = LexiconLanguageRecalcLoading(p);
        },
      );
      state = const LexiconLanguageRecalcSuccess();
      ref.invalidate(greekDictionaryServiceProvider);
      ref.invalidate(spellCheckServiceProvider);
      ref.read(lexiconMasterDataRevisionProvider.notifier).bump();
    } catch (e) {
      state = LexiconLanguageRecalcError('$e');
    }
  }

  void acknowledge() {
    final s = state;
    if (s is LexiconLanguageRecalcSuccess || s is LexiconLanguageRecalcError) {
      state = const LexiconLanguageRecalcIdle();
    }
  }
}

final lexiconLanguageRecalcProvider =
    NotifierProvider<LexiconLanguageRecalcNotifier, LexiconLanguageRecalcState>(
  LexiconLanguageRecalcNotifier.new,
);

/// Αυξάνεται μετά από αλλαγές στο master λεξικό ώστε η οθόνη διαχείρισης να ξαναφορτώσει το grid.
class LexiconMasterDataRevisionNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final lexiconMasterDataRevisionProvider =
    NotifierProvider<LexiconMasterDataRevisionNotifier, int>(
  LexiconMasterDataRevisionNotifier.new,
);
