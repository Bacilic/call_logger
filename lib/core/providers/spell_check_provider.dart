import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/spell_check_service.dart';
import 'greek_dictionary_provider.dart';

/// Ορθογραφικό λεξικό: asset ([greekDictionaryServiceProvider]) + `user_dictionary` στη βάση.
final spellCheckServiceProvider = FutureProvider<LexiconSpellCheckService>((ref) async {
  final dict = await ref.watch(greekDictionaryServiceProvider.future);
  final svc = LexiconSpellCheckService();
  await svc.init(lexiconMap: dict.stripKeyToDisplayMap);
  return svc;
});
