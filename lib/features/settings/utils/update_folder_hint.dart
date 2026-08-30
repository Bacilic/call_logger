/// Τι λέει η γραμμή κάτω από τον «Φάκελο ελέγχου ενημερώσεων».
///
/// Το πεδίο δείχνει την **ενεργή** διαδρομή, όχι τη ρύθμιση: όταν η κοινή
/// ρύθμιση είναι κενή, γεμίζει με ό,τι κατέγραψε η εγκατάσταση αυτού του
/// υπολογιστή. Οι δύο περιπτώσεις μοιάζουν ίδιες στην οθόνη και δεν είναι —
/// η μία αφορά όλους, η άλλη μόνο αυτό το μηχάνημα. Γι' αυτό η γραμμή δεν
/// κοιτά μόνο αν το πεδίο έχει κείμενο, αλλά **από πού ήρθε**.
///
/// Το παλιό μήνυμα ανέφερε το `update_source.json` με το όνομά του και τίποτα
/// άλλο, οπότε διαβαζόταν σαν να ήταν εκείνο η πηγή της τιμής που φαίνεται.
class UpdateFolderHint {
  const UpdateFolderHint._();

  /// Υπάρχει αποθηκευμένη κοινή ρύθμιση, και το πεδίο τη δείχνει.
  static const String sharedAcrossMachines =
      'Η διαδρομή ισχύει για όλους τους υπολογιστές που χρησιμοποιούν αυτή τη '
      'βάση. Αν το αδειάσετε, κάθε υπολογιστής θα ψάχνει στον φάκελο από τον '
      'οποίο εγκαταστάθηκε.';

  /// Το πεδίο δείχνει τιμή, αλλά κανείς δεν την έχει ορίσει ως κοινή.
  static const String fromInstallerNotSaved =
      'Δεν υπάρχει κοινή ρύθμιση: η διαδρομή έρχεται από την εγκατάσταση '
      'αυτού του υπολογιστή. Αποθηκεύστε την για να ισχύσει και για τους '
      'υπόλοιπους.';

  /// Ούτε ρύθμιση, ούτε εγκατάσταση — καμία πηγή ενημερώσεων.
  static const String noSourceAtAll =
      'Δεν θα γίνεται έλεγχος για νέα έκδοση: ούτε διαδρομή έχει οριστεί εδώ, '
      'ούτε φάκελος εγκατάστασης έχει καταγραφεί.';

  /// Το πεδίο αδειάστηκε, αλλά η εγκατάσταση έχει καταγράψει φάκελο.
  static String fallsBackToInstaller(String folder) =>
      'Χρησιμοποιείται ο φάκελος από τον οποίο εγκαταστάθηκε αυτός ο '
      'υπολογιστής:\n$folder';

  /// Το κείμενο για την τρέχουσα κατάσταση του πεδίου.
  ///
  /// [hasSavedSetting] δηλώνει αν η **κοινή** ρύθμιση έχει τιμή — όχι αν το
  /// πεδίο δείχνει κάτι. [installerFolder] είναι ό,τι κατέγραψε το πρόγραμμα
  /// εγκατάστασης, ή `null` όταν δεν υπάρχει.
  static String forState({
    required String fieldValue,
    required String? installerFolder,
    required bool hasSavedSetting,
  }) {
    final folder = installerFolder?.trim();
    final hasInstaller = folder != null && folder.isNotEmpty;

    if (fieldValue.trim().isEmpty) {
      return hasInstaller ? fallsBackToInstaller(folder) : noSourceAtAll;
    }
    return hasSavedSetting ? sharedAcrossMachines : fromInstallerNotSaved;
  }

  /// Δηλώνει η τρέχουσα κατάσταση ότι **δεν** θα γίνει κανένας έλεγχος;
  ///
  /// Το χρησιμοποιεί το πεδίο για να τονίσει τη γραμμή: δεν είναι σφάλμα
  /// ρύθμισης, είναι όμως απώλεια λειτουργίας και αξίζει να ξεχωρίζει.
  static bool isNoSourceState({
    required String fieldValue,
    required String? installerFolder,
  }) =>
      fieldValue.trim().isEmpty &&
      (installerFolder == null || installerFolder.trim().isEmpty);
}
