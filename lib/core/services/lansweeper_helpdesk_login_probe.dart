import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Αποτέλεσμα δοκιμής διαπιστευτηρίων Help Desk (browser), όχι API key.
class LansweeperHelpdeskLoginProbeResult {
  const LansweeperHelpdeskLoginProbeResult({
    required this.ok,
    required this.message,
  });

  final bool ok;
  final String message;
}

/// Προσομοίωση υποβολής φόρμας `login.aspx` (ASP.NET Web Forms) για επαλήθευση.
abstract final class LansweeperHelpdeskLoginProbe {
  static const Duration _timeout = Duration(seconds: 18);

  /// Δοκιμάζει σύνδεση με GET της σελίδας σύνδεσης και POST των πεδίων της φόρμας.
  static Future<LansweeperHelpdeskLoginProbeResult> test({
    required String loginPageUrl,
    required String username,
    required String password,
  }) async {
    final trimmedUrl = loginPageUrl.trim();
    if (trimmedUrl.isEmpty) {
      return const LansweeperHelpdeskLoginProbeResult(
        ok: false,
        message: 'Συμπληρώστε URL σελίδας σύνδεσης (π.χ. …/login.aspx).',
      );
    }
    final loginUri = Uri.tryParse(trimmedUrl);
    if (loginUri == null ||
        !loginUri.hasScheme ||
        (loginUri.scheme != 'http' && loginUri.scheme != 'https')) {
      return LansweeperHelpdeskLoginProbeResult(
        ok: false,
        message: 'Μη έγκυρο URL σύνδεσης: $trimmedUrl',
      );
    }
    if (username.trim().isEmpty || password.isEmpty) {
      return const LansweeperHelpdeskLoginProbeResult(
        ok: false,
        message: 'Συμπληρώστε όνομα χρήστη και κωδικό.',
      );
    }

    final client = HttpClient();
    try {
      client.userAgent = 'CallLogger LansweeperLoginProbe/1';

      final getReq = await client.getUrl(loginUri).timeout(_timeout);
      getReq.followRedirects = true;
      getReq.maxRedirects = 8;
      final getResp = await getReq.close().timeout(_timeout);
      final getBody = await getResp
          .transform(utf8.decoder)
          .join()
          .timeout(_timeout);

      if (getResp.statusCode < 200 || getResp.statusCode >= 400) {
        return LansweeperHelpdeskLoginProbeResult(
          ok: false,
          message:
              'Αποτυχία φόρτωσης σελίδας σύνδεσης (HTTP ${getResp.statusCode}).',
        );
      }

      final form = _extractLoginForm(html: getBody, documentUri: loginUri);
      if (form == null) {
        return const LansweeperHelpdeskLoginProbeResult(
          ok: false,
          message:
              'Δεν βρέθηκε φόρμα σύνδεσης (password field) στη σελίδα. Ελέγξτε το URL.',
        );
      }

      final fields = <String, String>{...form.hiddenFields};
      fields[form.usernameFieldName] = username.trim();
      fields[form.passwordFieldName] = password;
      if (form.submitName != null && form.submitValue != null) {
        fields[form.submitName!] = form.submitValue!;
      }

      final encodedBody = fields.entries
          .map(
            (e) =>
                '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
          )
          .join('&');

      final postReq = await client.postUrl(form.postUri).timeout(_timeout);
      postReq.followRedirects = false;
      postReq.headers.set(
        HttpHeaders.contentTypeHeader,
        'application/x-www-form-urlencoded; charset=UTF-8',
      );
      postReq.headers.set(HttpHeaders.refererHeader, trimmedUrl);
      postReq.write(encodedBody);

      final postResp = await postReq.close().timeout(_timeout);
      final status = postResp.statusCode;
      final location = postResp.headers.value(HttpHeaders.locationHeader);
      final postBody = await postResp
          .transform(utf8.decoder)
          .join()
          .timeout(_timeout);

      if (status == HttpStatus.found ||
          status == HttpStatus.movedPermanently ||
          status == HttpStatus.seeOther ||
          status == HttpStatus.temporaryRedirect) {
        final loc = location ?? '';
        final locLower = loc.toLowerCase();
        if (loc.isNotEmpty && !locLower.contains('login.aspx')) {
          return const LansweeperHelpdeskLoginProbeResult(
            ok: true,
            message: 'Τα διαπιστευτήρια ελέγχθηκαν: η σύνδεση φαίνεται επιτυχής.',
          );
        }
        if (loc.isEmpty) {
          return const LansweeperHelpdeskLoginProbeResult(
            ok: false,
            message:
                'Λήφθηκε ανακατεύθυνση χωρίς Location· δοκιμάστε άλλο URL ή ελέγξτε το Lansweeper.',
          );
        }
      }

      if (_responseIndicatesFailure(postBody)) {
        return const LansweeperHelpdeskLoginProbeResult(
          ok: false,
          message: 'Λάθος όνομα χρήστη ή κωδικός (ή απορρίφθηκε η σύνδεση).',
        );
      }

      if (status >= 200 &&
          status < 300 &&
          _htmlContainsPasswordField(postBody)) {
        return const LansweeperHelpdeskLoginProbeResult(
          ok: false,
          message:
              'Η σελίδα σύνδεσης επέστρεψε ξανά· πιθανό λάθος στα διαπιστευτήρια.',
        );
      }

      if (status >= 200 &&
          status < 300 &&
          !_htmlContainsPasswordField(postBody)) {
        return const LansweeperHelpdeskLoginProbeResult(
          ok: true,
          message:
              'Τα διαπιστευτήρια ελέγχθηκαν: η απόκριση δεν δείχνει σφάλμα σύνδεσης.',
        );
      }

      return LansweeperHelpdeskLoginProbeResult(
        ok: false,
        message: 'Απρόσμενη απόκριση διακομιστή (HTTP $status).',
      );
    } on SocketException catch (e) {
      return LansweeperHelpdeskLoginProbeResult(
        ok: false,
        message: 'Δίκτυο: ${e.message}',
      );
    } on TimeoutException {
      return const LansweeperHelpdeskLoginProbeResult(
        ok: false,
        message: 'Λήξη χρόνου αναμονής· ελέγξτε δίκτυο ή URL.',
      );
    } catch (e) {
      return LansweeperHelpdeskLoginProbeResult(
        ok: false,
        message: 'Σφάλμα: $e',
      );
    } finally {
      client.close(force: true);
    }
  }

  static bool _htmlContainsPasswordField(String html) {
    final lower = html.toLowerCase();
    return lower.contains('type="password"') ||
        lower.contains("type='password'") ||
        lower.contains('type=password');
  }

  static bool _responseIndicatesFailure(String html) {
    final lower = html.toLowerCase();
    const needles = <String>[
      'your login attempt was not successful',
      'login failed',
      'invalid credentials',
      'incorrect password',
      'wrong password',
      'authentication failed',
      'σφάλμα σύνδεσης',
      'λανθασμένο',
      'αποτυχία σύνδεσης',
    ];
    for (final n in needles) {
      if (lower.contains(n)) return true;
    }
    return false;
  }
}

class _ParsedLoginForm {
  _ParsedLoginForm({
    required this.postUri,
    required this.hiddenFields,
    required this.usernameFieldName,
    required this.passwordFieldName,
    this.submitName,
    this.submitValue,
  });

  final Uri postUri;
  final Map<String, String> hiddenFields;
  final String usernameFieldName;
  final String passwordFieldName;
  final String? submitName;
  final String? submitValue;
}

_ParsedLoginForm? _extractLoginForm({
  required String html,
  required Uri documentUri,
}) {
  final lower = html.toLowerCase();
  final pwdMarker = lower.indexOf('type="password"');
  final pwdMarker2 = lower.indexOf("type='password'");
  final pwdMarker3 = lower.indexOf('type=password');
  int pwdIdx = pwdMarker;
  if (pwdIdx < 0) pwdIdx = pwdMarker2;
  if (pwdIdx < 0) pwdIdx = pwdMarker3;
  if (pwdIdx < 0) return null;

  final formOpen = lower.lastIndexOf('<form', pwdIdx);
  if (formOpen < 0) return null;
  final formTagEnd = html.indexOf('>', formOpen);
  if (formTagEnd < 0) return null;
  final formClose = lower.indexOf('</form>', pwdIdx);
  if (formClose < 0) return null;

  final formTag = html.substring(formOpen, formTagEnd + 1);
  final formInner = html.substring(formTagEnd + 1, formClose);

  final actionMatch = RegExp(
    r'''action\s*=\s*["']([^"']*)["']''',
    caseSensitive: false,
  ).firstMatch(formTag);
  final actionRaw = (actionMatch?.group(1) ?? '').trim();
  final postUri = actionRaw.isEmpty
      ? documentUri
      : documentUri.resolve(actionRaw);

  final inputs = _parseInputTags(formInner);
  String? passwordName;
  String? usernameName;
  String? submitName;
  String? submitValue;
  final hidden = <String, String>{};

  for (final inp in inputs) {
    final type = (inp['type'] ?? 'text').toLowerCase().trim();
    final name = inp['name']?.trim();
    if (name == null || name.isEmpty) continue;

    if (type == 'hidden') {
      hidden[name] = inp['value'] ?? '';
      continue;
    }
    if (type == 'password') {
      passwordName = name;
      continue;
    }
    if (type == 'text' || type == 'email') {
      final nLower = name.toLowerCase();
      if (nLower.contains('user') ||
          nLower.contains('login') ||
          nLower.contains('email') ||
          nLower.contains('name')) {
        usernameName ??= name;
      }
    }
  }

  if (passwordName == null) return null;

  if (usernameName == null || usernameName.isEmpty) {
    for (final inp in inputs) {
      final type = (inp['type'] ?? 'text').toLowerCase().trim();
      final name = inp['name']?.trim();
      if (name == null || name.isEmpty) continue;
      if (type == 'text' || type == 'email') {
        usernameName = name;
        break;
      }
    }
  }

  if (usernameName == null || usernameName.isEmpty) return null;

  for (final inp in inputs) {
    final type = (inp['type'] ?? '').toLowerCase();
    final name = inp['name']?.trim();
    if (name == null) continue;
    if (type == 'submit' || type == 'image') {
      final nLower = name.toLowerCase();
      final vLower = (inp['value'] ?? '').toLowerCase();
      if (nLower.contains('login') ||
          vLower.contains('log') ||
          vLower.contains('sign')) {
        submitName = name;
        final v = inp['value'];
        submitValue = (v != null && v.isNotEmpty) ? v : 'Login';
        break;
      }
    }
  }
  if (submitName == null) {
    for (final inp in inputs) {
      final type = (inp['type'] ?? '').toLowerCase();
      final name = inp['name']?.trim();
      if (name == null) continue;
      if (type == 'submit' || type == 'image') {
        submitName = name;
        final v = inp['value'];
        submitValue = (v != null && v.isNotEmpty) ? v : 'Login';
        break;
      }
    }
  }

  return _ParsedLoginForm(
    postUri: postUri,
    hiddenFields: hidden,
    usernameFieldName: usernameName,
    passwordFieldName: passwordName,
    submitName: submitName,
    submitValue: submitValue,
  );
}

List<Map<String, String>> _parseInputTags(String fragment) {
  final out = <Map<String, String>>[];
  final re = RegExp(r'<input\s*([^>]+)/?\s*>', caseSensitive: false);
  for (final m in re.allMatches(fragment)) {
    final attrs = m.group(1)!;
    final map = <String, String>{};
    for (final key in ['type', 'name', 'id', 'value']) {
      var mm = RegExp(
        '$key\\s*=\\s*"((?:\\\\.|[^"\\\\])*)"',
        caseSensitive: false,
      ).firstMatch(attrs);
      mm ??= RegExp(
        "$key\\s*=\\s*'((?:\\\\.|[^'\\\\])*)'",
        caseSensitive: false,
      ).firstMatch(attrs);
      if (mm != null) {
        map[key] = mm.group(1)!.replaceAll(r'\"', '"').replaceAll(r"\'", "'");
      }
    }
    if (map.containsKey('name')) {
      out.add(map);
    }
  }
  return out;
}
