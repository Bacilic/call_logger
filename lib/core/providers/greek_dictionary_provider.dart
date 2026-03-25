import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/dictionary_service.dart';

/// Φόρτωση ελληνικού core λεξικού (/asset) μία φορά ανά διεργασία.
final greekDictionaryServiceProvider = FutureProvider<DictionaryService>((
  ref,
) async {
  final service = DictionaryService();
  await service.load();
  return service;
});
