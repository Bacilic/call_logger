import 'dart:convert';

import '../../../core/services/profile_settings.dart';
import '../../../core/services/scoped_settings.dart';

/// Οι επιλογές που κρατά η φόρμα αποστολής ticket για την επόμενη φορά:
/// τα προσαρμοσμένα πεδία και η κατάσταση ticket.
///
/// **Ανήκουν στον χρήστη που τις έκανε.** Όσο γράφονταν στην κοινή θέση —
/// παρακάμπτοντας τη διαδρομή των προφίλ, παρότι το κλειδί ήταν δηλωμένο
/// προσωπικό — δύο συνάδελφοι έβλεπαν ο ένας τα πεδία του άλλου.
///
/// Η κωδικοποίηση και η επιμονή ζουν εδώ και όχι μέσα στην οθόνη: η φόρμα
/// δηλώνει διεπαφή, δεν χειρίζεται αποθήκευση.
class LansweeperTicketFormPrefs {
  const LansweeperTicketFormPrefs({
    required this.customFieldValues,
    required this.ticketState,
  });

  final Map<String, String> customFieldValues;

  /// `null` = καμία αποθηκευμένη επιλογή· ισχύει η προεπιλογή των ρυθμίσεων.
  final String? ticketState;

  String encode() {
    return jsonEncode(<String, dynamic>{
      'customFieldValues': Map<String, String>.from(customFieldValues),
      'ticketState': ticketState,
    });
  }

  /// Ανεκτική ανάγνωση: ό,τι δεν βγάζει νόημα δίνει `null` αντί να ρίξει τη
  /// φόρμα. Παλιά ή χαλασμένη εγγραφή σημαίνει «καμία προτίμηση», όχι σφάλμα.
  static LansweeperTicketFormPrefs? decode(String? raw) {
    final text = (raw ?? '').trim();
    if (text.isEmpty) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;

    final values = <String, String>{};
    final rawValues = decoded['customFieldValues'];
    if (rawValues is Map) {
      rawValues.forEach((key, value) {
        if (key == null) return;
        values[key.toString()] = value?.toString() ?? '';
      });
    }
    final state = decoded['ticketState']?.toString().trim() ?? '';
    return LansweeperTicketFormPrefs(
      customFieldValues: values,
      ticketState: state.isEmpty ? null : state,
    );
  }

  /// Οι επιλογές του **συνδεδεμένου** χρήστη· `null` όταν δεν έχει αποθηκεύσει.
  static Future<LansweeperTicketFormPrefs?> load() async {
    return decode(
      await ScopedSettings.getString(
        ProfileSettingKeys.lansweeperTicketSubmitFormPrefs,
      ),
    );
  }

  Future<void> save() {
    return ScopedSettings.setString(
      ProfileSettingKeys.lansweeperTicketSubmitFormPrefs,
      encode(),
    );
  }
}
