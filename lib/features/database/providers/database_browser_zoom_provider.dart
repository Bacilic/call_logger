import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/crash_log_service.dart';
import '../../../core/services/profile_settings.dart';
import '../../../core/services/scoped_settings.dart';

/// Αποθηκευμένο επίπεδο μεγέθυνσης ανά πίνακα προεπισκόπησης (0.5–2.0· προεπιλογή 1.0).
///
/// **Προσωπικό**: πόσο μεγάλα διαβάζει κανείς είναι δικό του θέμα. Όσο γραφόταν
/// κατευθείαν στα κοινά — παρά το ότι το κλειδί ήταν δηλωμένο προσωπικό —
/// ρυθμίζοντας το ζουμ το άλλαζες και για τον συνάδελφο.
///
/// **Ζει όσο η εφαρμογή, όχι όσο η οθόνη.** Η φόρτωση ξεκινά από το `initState`,
/// πριν προλάβει το πρώτο build να αρχίσει να παρακολουθεί, και η εναλλαγή
/// βάσης μπορεί να ξηλώσει την οθόνη ενόσω τρέχει: με `autoDispose` ο
/// αποθηκευτής πέθαινε στο πρώτο await και η εγγραφή της τιμής έσκαγε, οπότε
/// το ζουμ του χρήστη γύριζε σιωπηλά στο 100%.
final databaseBrowserZoomByTableProvider =
    NotifierProvider<DatabaseBrowserZoomByTableNotifier, Map<String, double>>(
      DatabaseBrowserZoomByTableNotifier.new,
    );

class DatabaseBrowserZoomByTableNotifier extends Notifier<Map<String, double>> {
  @override
  Map<String, double> build() => {};

  /// Φόρτωση του ζουμ του τρέχοντος χρήστη (καλείται κατά το άνοιγμα της οθόνης).
  Future<void> load() async {
    try {
      final raw = await ScopedSettings.getString(
        ProfileSettingKeys.databaseBrowserPreviewZoomByTable,
      );
      if (!ref.mounted) return;
      if (raw == null || raw.trim().isEmpty) {
        state = {};
        return;
      }
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final out = <String, double>{};
      for (final e in decoded.entries) {
        final z = (e.value as num?)?.toDouble();
        if (z == null) continue;
        final clamped = z.clamp(0.5, 2.0);
        if ((clamped - 1.0).abs() >= 0.001) {
          out[e.key] = clamped;
        }
      }
      state = out;
    } catch (e, stack) {
      // Το zoom είναι προαιρετική άνεση — η οθόνη συνεχίζει με 100%,
      // αλλά το σφάλμα (π.χ. χαλασμένο JSON) αφήνει ίχνος στο ημερολόγιο.
      CrashLogService.instanceOrNull?.logError(e, stack, fatal: false);
      if (ref.mounted) state = {};
    }
  }

  double zoomFor(String tableName) => state[tableName] ?? 1.0;

  Future<void> _persist(Map<String, double> snapshot) async {
    await ScopedSettings.setString(
      ProfileSettingKeys.databaseBrowserPreviewZoomByTable,
      jsonEncode(snapshot),
    );
  }

  Future<void> setZoomForTable(String tableName, double zoom) async {
    final z = zoom.clamp(0.5, 2.0);
    final next = Map<String, double>.from(state);
    if ((z - 1.0).abs() < 0.001) {
      next.remove(tableName);
    } else {
      next[tableName] = z;
    }
    state = next;
    try {
      await _persist(next);
    } catch (e, stack) {
      // Η προβολή έχει ήδη το νέο zoom — μόνο η αποθήκευση απέτυχε.
      CrashLogService.instanceOrNull?.logError(e, stack, fatal: false);
    }
  }

  Future<void> zoomOutFor(String tableName) {
    return setZoomForTable(tableName, zoomFor(tableName) - 0.1);
  }

  Future<void> zoomInFor(String tableName) {
    return setZoomForTable(tableName, zoomFor(tableName) + 0.1);
  }

  Future<void> resetFor(String tableName) {
    return setZoomForTable(tableName, 1.0);
  }
}
