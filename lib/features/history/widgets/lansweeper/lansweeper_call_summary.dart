import 'package:intl/intl.dart';

import '../../../calls/models/call_model.dart';

/// Πού ανήκει κάθε πληροφορία της αναφοράς Lansweeper: στην κεφαλίδα της ομάδας
/// ή στην κάρτα της κλήσης.
///
/// Ο κανόνας είναι ένας: **η πληροφορία εμφανίζεται στο ψηλότερο σημείο όπου
/// είναι αληθής**. Ο καλών, το τηλέφωνο και το τμήμα είναι ιδιότητες του
/// ανθρώπου και όχι της κάθε κλήσης, οπότε λέγονται μία φορά στην κεφαλίδα·
/// ο εξοπλισμός αλλάζει από κλήση σε κλήση και μένει στην κάρτα.
///
/// Ζει σε δικό του αρχείο ώστε να το βλέπουν και η λίστα και ο mapper χωρίς να
/// εξαρτηθεί ο ένας από τον άλλο.
abstract final class LansweeperCallSummary {
  LansweeperCallSummary._();

  /// Η τιμή που μοιράζονται **όλες** οι κλήσεις μιας ομάδας, αλλιώς `null`.
  ///
  /// Η ομάδα «Άγνωστος» δεν είναι άνθρωπος: μαζεύει κάθε κλήση χωρίς
  /// συνδεδεμένο καλούντα, με διαφορετικό τμήμα και τηλέφωνο η καθεμιά. Εκεί
  /// δεν υπάρχει κοινή τιμή και η απάντηση είναι `null`, ώστε η πληροφορία να
  /// μείνει στην κάρτα — όπου είναι αληθής. Το ίδιο ισχύει όταν έστω μία κλήση
  /// έχει το πεδίο κενό: μια τιμή που ισχύει για τις μισές δεν είναι κοινή.
  static String? sharedValue(
    Iterable<CallModel> calls,
    String? Function(CallModel call) read,
  ) {
    String? shared;
    for (final call in calls) {
      final value = (read(call) ?? '').trim();
      if (value.isEmpty) return null;
      if (shared == null) {
        shared = value;
        continue;
      }
      if (shared != value) return null;
    }
    return shared;
  }

  /// Ημερομηνία χωρίς έτος — το φίλτρο διαστήματος το λέει ήδη, και η πλήρης
  /// μορφή μένει στην υπόδειξη.
  static String shortDateLabel(CallModel call) =>
      DateFormat('dd/MM HH:mm').format(_callDateTime(call));

  static String fullDateLabel(CallModel call) =>
      DateFormat('dd/MM/yyyy HH:mm').format(_callDateTime(call));

  /// Ό,τι δεν χωρά στη στενή κάρτα, ολόκληρο.
  ///
  /// Δείχνει και όσα ήδη φαίνονται στην κεφαλίδα: όποιος ζητά την υπόδειξη
  /// θέλει τη συγκεντρωτική εικόνα, όχι ένα κυνήγι ανάμεσα σε δύο σημεία.
  static String callTooltip(CallModel call) {
    final lines = <String>[fullDateLabel(call)];
    void add(String label, String? value) {
      final trimmed = (value ?? '').trim();
      if (trimmed.isNotEmpty) lines.add('$label: $trimmed');
    }

    add('Καλών', call.callerText);
    add('Τηλέφωνο', call.phoneText);
    add('Τμήμα', call.departmentText);
    add('Εξοπλισμός', call.equipmentText);
    add('Κατηγορία', call.category);
    return lines.join('\n');
  }

  static DateTime _callDateTime(CallModel call) {
    final dateRaw = (call.date ?? '').trim();
    final timeRaw = (call.time ?? '').trim();
    return DateTime.tryParse('$dateRaw $timeRaw') ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }
}
