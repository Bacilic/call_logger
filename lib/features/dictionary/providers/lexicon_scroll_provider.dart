import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/profile_settings.dart';
import '../../../core/services/scoped_settings.dart';

/// Ρύθμιση «συνεχής κύλιση + φόρτωση ακόμα γραμμών» για τον πίνακα λεξικού.
///
/// **Προσωπική**: ο καθένας διαβάζει όπως του ταιριάζει. Όσο γραφόταν
/// κατευθείαν στην κοινή θέση — παρακάμπτοντας τη διαδρομή των προφίλ, παρότι
/// το κλειδί ήταν δηλωμένο προσωπικό — όποιος άλλαζε τελευταίος άλλαζε και
/// του συναδέλφου.
///
/// Δεν συνδέεται με τους πίνακες Καταλόγου (ξεχωριστά κλειδιά ανά καρτέλα).
/// Προεπιλογή: `true` (όπως ο Κατάλογος).
class LexiconContinuousScrollNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    return await ScopedSettings.getBool(
          ProfileSettingKeys.lexiconContinuousScroll,
        ) ??
        true;
  }

  /// Η οθόνη ενημερώνεται πρώτη· η εγγραφή αφορά την επόμενη φορά.
  Future<void> setEnabled(bool value) async {
    state = AsyncValue.data(value);
    await ScopedSettings.setBool(
      ProfileSettingKeys.lexiconContinuousScroll,
      value,
    );
  }
}

final lexiconContinuousScrollProvider =
    AsyncNotifierProvider<LexiconContinuousScrollNotifier, bool>(
      LexiconContinuousScrollNotifier.new,
    );

/// Πλήθος λεξικών εγγραφών ανά σελίδα (σελιδοποίηση λεξικού).
///
/// **Προσωπική**, όπως η συνεχής κύλιση. Προεπιλογή 40, όρια 10–500 — και τα
/// όρια ισχύουν στην **εγγραφή** κι όχι μόνο στην ανάγνωση: όσο ο καλών
/// έγραφε μόνος του, τίποτα δεν τον εμπόδιζε να αποθηκεύσει τιμή εκτός ορίων
/// και να τη βρίσκει σιωπηλά περικομμένη σε κάθε ανάγνωση.
class LexiconPageSizeNotifier extends AsyncNotifier<int> {
  static const int _defaultPageSize = 40;
  static const int _minPageSize = 10;
  static const int _maxPageSize = 500;

  @override
  Future<int> build() async {
    final raw = await ScopedSettings.getString(
      ProfileSettingKeys.lexiconPageSize,
    );
    return _clamp(int.tryParse(raw?.trim() ?? '') ?? _defaultPageSize);
  }

  Future<void> setPageSize(int value) async {
    final next = _clamp(value);
    state = AsyncValue.data(next);
    await ScopedSettings.setString(ProfileSettingKeys.lexiconPageSize, '$next');
  }

  static int _clamp(int value) => value.clamp(_minPageSize, _maxPageSize);
}

final lexiconPageSizeProvider =
    AsyncNotifierProvider<LexiconPageSizeNotifier, int>(
      LexiconPageSizeNotifier.new,
    );
