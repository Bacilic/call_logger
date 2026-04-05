import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_helper.dart';

/// Ρύθμιση «συνεχής κύλιση + φόρτωση ακόμα γραμμών» για τον πίνακα λεξικού.
/// Δεν συνδέεται με τον Κατάλογο (`catalog_continuous_scroll`).
/// Default: true (όπως ο Κατάλογος).
final lexiconContinuousScrollProvider = FutureProvider.autoDispose<bool>((ref) async {
  final value = await DatabaseHelper.instance.getSetting('lexicon_continuous_scroll');
  return value == null || value == 'true';
});

/// Πλήθος λεξικών εγγραφών ανά σελίδα (σελιδοποίηση λεξικού). Κλειδί: `lexicon_page_size`.
/// Προεπιλογή: 40. Όρια: 10–500.
final lexiconPageSizeProvider = FutureProvider.autoDispose<int>((ref) async {
  final raw = await DatabaseHelper.instance.getSetting('lexicon_page_size');
  if (raw == null || raw.isEmpty) return 40;
  final n = int.tryParse(raw) ?? 40;
  return n.clamp(10, 500);
});
