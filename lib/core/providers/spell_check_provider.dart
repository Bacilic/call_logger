import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/spell_check_service.dart';
import 'core_lexicon_provider.dart';
import 'greek_dictionary_provider.dart';

/// Ορθογραφικό λεξικό: πυρήνας (αν φορτωμένος) + `user_dictionary` στη βάση.
final spellCheckServiceProvider =
    FutureProvider<LexiconSpellCheckService>((ref) async {
  ref.watch(coreLexiconProvider);
  final dict = ref.watch(greekDictionaryServiceProvider);
  final svc = LexiconSpellCheckService();
  await svc.init(lexiconVariants: dict.stripKeyToVariantsMap);
  return svc;
});
