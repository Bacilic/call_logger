import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'ai_model_cooldown_registry.dart';

/// Η υγεία των μοντέλων ΤΝ, φυλαγμένη σε **αυτόν** τον υπολογιστή.
///
/// **Γιατί τοπικά και όχι στην κοινή βάση:** το κλειδί API μπορεί να είναι
/// προσωπικό — η εφαρμογή προτιμά το δικό σου αν το έχεις δηλώσει, αλλιώς το
/// κοινό της ομάδας. Άρα «η ποσόστωση του μοντέλου εξαντλήθηκε» ισχύει για
/// όποιον χτύπησε το όριο, όχι για όλους. Μοιρασμένη, η γνώση θα έλεγε ψέματα
/// στον συνάδελφο με το δικό του κλειδί — και θα γέμιζε την κοινή βάση με
/// εγγραφές σε κάθε αποτυχία.
///
/// Η αποθήκευση κρατά **μόνο τα ενεργά**: ό,τι έληξε πετιέται στο διάβασμα και
/// στο γράψιμο, οπότε το κλειδί δεν μεγαλώνει ποτέ.
abstract final class AiModelHealthStore {
  static const String storageKey = 'ai_model_downtimes_v1';

  /// Ό,τι ίσχυε όταν έκλεισε η εφαρμογή και ισχύει ακόμη.
  ///
  /// Η γνώση είναι ευκολία, όχι προϋπόθεση: αν οι τοπικές ρυθμίσεις δεν
  /// διαβάζονται, η εφαρμογή ξεκινά χωρίς μνήμη αντί να σταματήσει.
  static Future<List<AiModelDowntime>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return decodeAiModelDowntimes(prefs.getString(storageKey) ?? '');
    } catch (_) {
      return const <AiModelDowntime>[];
    }
  }

  static Future<void> save(List<AiModelDowntime> entries) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (entries.isEmpty) {
        await prefs.remove(storageKey);
        return;
      }
      await prefs.setString(storageKey, encodeAiModelDowntimes(entries));
    } catch (_) {
      // Η αδυναμία εγγραφής δεν χαλάει τη λειτουργία — χάνεται μόνο η μνήμη
      // μετά την επανεκκίνηση.
    }
  }
}

/// Σε κείμενο για αποθήκευση. Τα ονόματα των πεδίων μένουν σύντομα επίτηδες:
/// το κλειδί γράφεται σε κάθε αποτυχία.
String encodeAiModelDowntimes(List<AiModelDowntime> entries) {
  return jsonEncode([
    for (final entry in entries)
      <String, dynamic>{
        'm': entry.model,
        'u': entry.until.toIso8601String(),
        'r': entry.reason.name,
        'b': entry.blocking,
      },
  ]);
}

/// Από κείμενο σε εγγραφές. Ό,τι δεν διαβάζεται αγνοείται σιωπηλά — μια
/// χαλασμένη ή παλαιότερη εγγραφή δεν αξίζει να εμποδίσει την εκκίνηση.
List<AiModelDowntime> decodeAiModelDowntimes(String raw) {
  if (raw.trim().isEmpty) return const <AiModelDowntime>[];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const <AiModelDowntime>[];
    final entries = <AiModelDowntime>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      final model = item['m']?.toString().trim() ?? '';
      final until = DateTime.tryParse(item['u']?.toString() ?? '');
      if (model.isEmpty || until == null) continue;
      entries.add(
        AiModelDowntime(
          model: model,
          until: until,
          reason: _reasonFromName(item['r']?.toString()),
          blocking: item['b'] == true,
        ),
      );
    }
    return entries;
  } catch (_) {
    return const <AiModelDowntime>[];
  }
}

AiModelDownReason _reasonFromName(String? name) {
  for (final reason in AiModelDownReason.values) {
    if (reason.name == name) return reason;
  }
  return AiModelDownReason.unavailable;
}
