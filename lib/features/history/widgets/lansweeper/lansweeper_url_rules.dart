import '../../../../core/database/settings_repository.dart';

/// Κανόνες επικύρωσης για τα δύο ξεχωριστά URL Lansweeper (API vs φόρμα web).
abstract final class LansweeperUrlRules {
  /// Έγκυρο URL για POST AddTicket: http(s) και διαδρομή που περιέχει `api.aspx`.
  static bool isApiEndpointUrl(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return false;
    final u = Uri.tryParse(t);
    if (u == null || !u.hasScheme || u.host.isEmpty) return false;
    if (u.scheme != 'http' && u.scheme != 'https') return false;
    final lowerPath = u.path.toLowerCase();
    final lower = t.toLowerCase();
    return lowerPath.contains('api.aspx') || lower.contains('/api.aspx');
  }

  /// Έγκυρο URL για άνοιγμα στον browser (http/https με host).
  static bool isBrowserLaunchableUrl(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return false;
    final u = Uri.tryParse(t);
    if (u == null || !u.hasScheme || u.host.isEmpty) return false;
    return u.scheme == 'http' || u.scheme == 'https';
  }

  /// URL για βοήθεια API: το πεδίο αν είναι έγκυρο, αλλιώς παράδειγμα.
  static String apiUrlForHelpLink(String fieldText) {
    final t = fieldText.trim();
    return isApiEndpointUrl(t) ? t : kExampleLansweeperApiUrl;
  }

  /// URL για βοήθεια φόρμας: το πεδίο αν ανοίγει στον browser, αλλιώς προεπιλογή.
  static String ticketFormUrlForHelpLink(String fieldText) {
    final t = fieldText.trim();
    return isBrowserLaunchableUrl(t) ? t : kDefaultLansweeperUrl;
  }

  /// URL σελίδας σύνδεσης (`login.aspx`) στο ίδιο origin με τη φόρμα αιτήματος.
  static String loginUrlDerivedFromTicketFormUrl(String ticketFormUrl) {
    final t = ticketFormUrl.trim();
    final u = Uri.tryParse(t);
    if (u == null || !u.hasScheme || u.host.isEmpty) {
      return kDefaultLansweeperLoginUrl;
    }
    return u.replace(path: '/login.aspx', queryParameters: {}).toString();
  }

  /// URL για βοήθεια σελίδας σύνδεσης: έγκυρο πεδίο ή προεπιλογή.
  static String loginPageUrlForHelpLink(String fieldText) {
    final t = fieldText.trim();
    return isBrowserLaunchableUrl(t) ? t : kDefaultLansweeperLoginUrl;
  }
}
