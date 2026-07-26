/// Στενή ταξινόμηση αποτυχίας φόρτωσης γραμματοσειράς ως μη-θανάσιμου σφάλματος.
///
/// Πρέπει να παραμένει στενή: γενικό «unable to load asset» χωρίς .ttf/.otf ή
/// google_fonts στο stack ΔΕΝ θεωρείται μη-θανάσιμο (π.χ. NativeAssetsManifest).
bool isNonFatalFontLoadError(Object error, [StackTrace? stack]) {
  final message = error.toString().toLowerCase();
  if (!message.contains('unable to load asset')) {
    return false;
  }

  final isFontAsset = message.contains('.ttf') || message.contains('.otf');
  if (isFontAsset) {
    return true;
  }

  final stackLower = (stack?.toString() ?? '').toLowerCase();
  return stackLower.contains('google_fonts') ||
      stackLower.contains('loadfontifnecessary');
}
