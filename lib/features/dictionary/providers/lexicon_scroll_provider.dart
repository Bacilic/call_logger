import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/database/directory_repository.dart';

/// Ρύθμιση «συνεχής κύλιση + φόρτωση ακόμα γραμμών» για τον πίνακα λεξικού.
/// Δεν συνδέεται με τους πίνακες Καταλόγου (ξεχωριστά κλειδιά ανά καρτέλα).
/// Default: true (όπως ο Κατάλογος).
final lexiconContinuousScrollProvider = FutureProvider.autoDispose<bool>((ref) async {
  final db = await DatabaseHelper.instance.database;
  final value = await DirectoryRepository(db).getSetting('lexicon_continuous_scroll');
  return value == null || value == 'true';
});

/// Πλήθος λεξικών εγγραφών ανά σελίδα (σελιδοποίηση λεξικού). Κλειδί: `lexicon_page_size`.
/// Προεπιλογή: 40. Όρια: 10–500.
final lexiconPageSizeProvider = FutureProvider.autoDispose<int>((ref) async {
  final db = await DatabaseHelper.instance.database;
  final raw = await DirectoryRepository(db).getSetting('lexicon_page_size');
  if (raw == null || raw.isEmpty) return 40;
  final n = int.tryParse(raw) ?? 40;
  return n.clamp(10, 500);
});
