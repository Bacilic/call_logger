import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/core_lexicon_service.dart';

/// Διαχείριση κατάστασης λεξικού-πυρήνα (συγχρονισμένη με [CoreLexiconService]).
class CoreLexiconNotifier extends Notifier<CoreLexiconState> {
  CoreLexiconService get _svc => CoreLexiconService.instance;

  @override
  CoreLexiconState build() => _svc.state;

  void _sync() => state = _svc.state;

  Future<bool> bootstrapFromSavedPath() async {
    final ok = await _svc.bootstrapFromSavedPath();
    _sync();
    return ok;
  }

  Future<bool> loadFromDiskPath(String path, {bool persistPath = true}) async {
    final ok = await _svc.loadFromDiskPath(path, persistPath: persistPath);
    _sync();
    return ok;
  }

  Future<bool> installFromBundledAsset(String assetPath) async {
    final ok = await _svc.installFromBundledAsset(assetPath);
    _sync();
    return ok;
  }

  Future<bool> installFromExternalFile(String sourcePath) async {
    final ok = await _svc.installFromExternalFile(sourcePath);
    _sync();
    return ok;
  }

  void unload() {
    _svc.unload();
    _sync();
  }
}

final coreLexiconProvider =
    NotifierProvider<CoreLexiconNotifier, CoreLexiconState>(
  CoreLexiconNotifier.new,
);

final coreLexiconLoadedProvider = Provider<bool>(
  (ref) => ref.watch(coreLexiconProvider).loaded,
);

/// Ορατότητα στοιχείου πλοήγησης «Λεξικό».
bool isDictionaryNavVisible({
  required bool enableSpellCheck,
  required bool showDictionaryNav,
  required bool coreLexiconLoaded,
}) {
  if (!enableSpellCheck) return false;
  if (!coreLexiconLoaded) return true;
  return showDictionaryNav;
}
