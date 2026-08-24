import 'package:intl/intl.dart';

/// Πόσο παλιά είναι τα στοιχεία που βλέπει ο χρήστης, σε μία φράση.
///
/// Σε κοινόχρηστη βάση καμία οθόνη δεν μπορεί να υποσχεθεί «πάντα φρέσκο» —
/// μπορεί όμως να πει πόσο παλιό είναι. Η ένδειξη υπάρχει ακριβώς γι' αυτό:
/// είναι η τίμια εκδοχή της υπόσχεσης που δεν μπορεί να δοθεί.
///
/// Καθαρή συνάρτηση με ρητό [now]: ο κανόνας ελέγχεται χωρίς οθόνη, και η οθόνη
/// δεν αποκτά δεύτερο ρολόι.
String tasksFreshnessLabel({required DateTime? lastRead, DateTime? now}) {
  if (lastRead == null) return 'Δεν έχουν διαβαστεί ακόμη από τη βάση';

  final moment = now ?? DateTime.now();
  final elapsed = moment.difference(lastRead);

  if (elapsed.isNegative || elapsed.inSeconds < 45) {
    return 'Ενημερώθηκαν μόλις τώρα';
  }
  if (elapsed.inMinutes < 60) {
    final minutes = elapsed.inMinutes;
    return minutes == 1
        ? 'Ενημερώθηκαν πριν από ένα λεπτό'
        : 'Ενημερώθηκαν πριν από $minutes λεπτά';
  }
  return 'Στοιχεία της ${DateFormat('HH:mm').format(lastRead)}';
}
