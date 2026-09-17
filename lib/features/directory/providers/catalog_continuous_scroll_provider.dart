import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/profile_settings.dart';
import '../../../core/services/scoped_settings.dart';

/// Η ρύθμιση «συνεχής κύλιση πίνακα» των καρτελών του Καταλόγου.
///
/// **Προσωπική**: ο καθένας διαβάζει τον πίνακα όπως του ταιριάζει. Όσο η
/// τιμή γραφόταν κατευθείαν στην κοινή θέση — παρακάμπτοντας τη διαδρομή των
/// προφίλ, παρότι το κλειδί ήταν δηλωμένο προσωπικό — όποιος άλλαζε τον
/// διακόπτη τελευταίος άλλαζε και τον πίνακα του συναδέλφου.
///
/// **Η εγγραφή ζει εδώ, όχι στον διακόπτη:** τρεις καρτέλες άνοιγαν η καθεμία
/// τη δική της σύνδεση στη βάση μέσα από το κουμπί, οπότε κάθε αλλαγή στη
/// διαδρομή της ρύθμισης έπρεπε να θυμηθεί και τα τρία σημεία.
///
/// Προεπιλογή: `true`. Αν λείπει η τιμή της καρτέλας, διαβάζεται το παλιό ενιαίο
/// κλειδί του Καταλόγου, ώστε να μη χαθεί ρύθμιση που ορίστηκε πριν χωριστούν
/// οι καρτέλες.
abstract class _CatalogContinuousScrollNotifier extends AsyncNotifier<bool> {
  /// Το κλειδί της συγκεκριμένης καρτέλας.
  ProfileSettingKey get settingKey;

  @override
  Future<bool> build() async {
    final own = await ScopedSettings.getBool(settingKey);
    if (own != null) return own;
    return await ScopedSettings.getBool(
          ProfileSettingKeys.catalogContinuousScroll,
        ) ??
        true;
  }

  /// Η οθόνη ενημερώνεται πρώτη· η εγγραφή αφορά την επόμενη φορά.
  Future<void> setEnabled(bool value) async {
    state = AsyncValue.data(value);
    await ScopedSettings.setBool(settingKey, value);
  }
}

class CatalogUsersContinuousScrollNotifier
    extends _CatalogContinuousScrollNotifier {
  @override
  ProfileSettingKey get settingKey =>
      ProfileSettingKeys.catalogContinuousScrollUsers;
}

class CatalogDepartmentsContinuousScrollNotifier
    extends _CatalogContinuousScrollNotifier {
  @override
  ProfileSettingKey get settingKey =>
      ProfileSettingKeys.catalogContinuousScrollDepartments;
}

class CatalogEquipmentContinuousScrollNotifier
    extends _CatalogContinuousScrollNotifier {
  @override
  ProfileSettingKey get settingKey =>
      ProfileSettingKeys.catalogContinuousScrollEquipment;
}

/// Συνεχής κύλιση πινάκων υπαλλήλων (προσωπικά / κοινόχρηστα).
final catalogUsersContinuousScrollProvider =
    AsyncNotifierProvider<CatalogUsersContinuousScrollNotifier, bool>(
      CatalogUsersContinuousScrollNotifier.new,
    );

/// Συνεχής κύλιση πίνακα τμημάτων.
final catalogDepartmentsContinuousScrollProvider =
    AsyncNotifierProvider<CatalogDepartmentsContinuousScrollNotifier, bool>(
      CatalogDepartmentsContinuousScrollNotifier.new,
    );

/// Συνεχής κύλιση πίνακα εξοπλισμού.
final catalogEquipmentContinuousScrollProvider =
    AsyncNotifierProvider<CatalogEquipmentContinuousScrollNotifier, bool>(
      CatalogEquipmentContinuousScrollNotifier.new,
    );
