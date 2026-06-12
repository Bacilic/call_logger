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

  /// Συναρμολογεί URL προβολής ticket από πρότυπο (`{tid}` ή `[id_ticket]` ή `tid=`).
  static String? buildTicketViewUrl(String template, String ticketId) {
    final id = ticketId.trim();
    if (id.isEmpty) return null;
    final t = template.trim();
    if (t.isEmpty) return null;

    final String result;
    if (t.contains('{tid}')) {
      result = t.replaceAll('{tid}', id);
    } else if (t.contains('[id_ticket]')) {
      result = t.replaceAll('[id_ticket]', id);
    } else if (t.endsWith('=')) {
      result = '$t$id';
    } else {
      final base = Uri.tryParse(t);
      if (base == null || !base.hasScheme || base.host.isEmpty) return null;
      result = base
          .replace(queryParameters: {...base.queryParameters, 'tid': id})
          .toString();
    }

    return isBrowserLaunchableUrl(result) ? result : null;
  }

  /// URL για έλεγχο συνδέσμου προβολής ticket (δοκιμαστικό id).
  static String ticketViewUrlForHelpLink(String fieldText) {
    final template = fieldText.trim().isEmpty
        ? kDefaultLansweeperTicketViewUrl
        : fieldText.trim();
    return buildTicketViewUrl(template, '17132') ??
        buildTicketViewUrl(kDefaultLansweeperTicketViewUrl, '17132')!;
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
