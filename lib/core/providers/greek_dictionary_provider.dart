import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/core_lexicon_service.dart';
import '../services/dictionary_service.dart';
import 'core_lexicon_provider.dart';

/// Λεξικό-πυρήνας στη μνήμη (κενό αν δεν έχει φορτωθεί).
final greekDictionaryServiceProvider = Provider<DictionaryService>((ref) {
  ref.watch(coreLexiconProvider);
  final loaded = CoreLexiconService.instance.dictionaryService;
  if (loaded != null && loaded.isLoaded) {
    return loaded;
  }
  return DictionaryService.empty();
});
