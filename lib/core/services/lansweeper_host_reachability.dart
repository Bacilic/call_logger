import 'dart:async';
import 'dart:io';

/// Αποτέλεσμα ελέγχου προσβασιμότητας κεντρικού υπολογιστή Lansweeper (HTTP ping).
class LansweeperHostReachabilityResult {
  const LansweeperHostReachabilityResult._({
    required this.reachable,
    this.message = '',
  });

  const LansweeperHostReachabilityResult.reachable()
      : this._(reachable: true);

  const LansweeperHostReachabilityResult.unreachable(String message)
      : this._(reachable: false, message: message);

  final bool reachable;
  final String message;
}

/// Γρήγορος δικτυακός έλεγχος αν ο διακομιστής Lansweeper απαντά (χωρίς έλεγχο διαπιστευτηρίων).
abstract final class LansweeperHostReachability {
  static const Duration _timeout = Duration(seconds: 5);

  /// HEAD ή GET στο root (`/`) του `scheme + host + port` του [rawUrl].
  static Future<LansweeperHostReachabilityResult> check(String rawUrl) async {
    final rootUri = _rootUriFrom(rawUrl);
    if (rootUri == null) {
      return LansweeperHostReachabilityResult.unreachable(
        'Μη έγκυρη διεύθυνση URL: ${rawUrl.trim()}',
      );
    }

    final client = HttpClient();
    client.connectionTimeout = _timeout;
    try {
      HttpClientResponse? response;
      Object? lastError;

      for (final method in ['HEAD', 'GET']) {
        try {
          final request = await client
              .openUrl(method, rootUri)
              .timeout(_timeout);
          request.followRedirects = false;
          response = await request.close().timeout(_timeout);
          break;
        } on TimeoutException catch (e) {
          lastError = e;
        } on SocketException catch (e) {
          lastError = e;
          break;
        } catch (e) {
          lastError = e;
        }
      }

      if (response != null) {
        await response.drain<void>().timeout(_timeout);
        return const LansweeperHostReachabilityResult.reachable();
      }

      return LansweeperHostReachabilityResult.unreachable(
        _messageForError(lastError ?? 'Άγνωστο σφάλμα δικτύου'),
      );
    } on TimeoutException {
      return const LansweeperHostReachabilityResult.unreachable(
        'Λήξη χρόνου αναμονής — ο διακομιστής δεν ανταποκρίνεται εντός 5 δευτερολέπτων',
      );
    } on SocketException catch (e) {
      return LansweeperHostReachabilityResult.unreachable(_messageForError(e));
    } catch (e) {
      return LansweeperHostReachabilityResult.unreachable(e.toString());
    } finally {
      client.close(force: true);
    }
  }

  static Uri? _rootUriFrom(String raw) {
    final parsed = Uri.tryParse(raw.trim());
    if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) {
      return null;
    }
    if (parsed.scheme != 'http' && parsed.scheme != 'https') {
      return null;
    }

    return Uri(
      scheme: parsed.scheme,
      userInfo: parsed.userInfo.isEmpty ? null : parsed.userInfo,
      host: parsed.host,
      port: parsed.hasPort ? parsed.port : null,
      path: '/',
    );
  }

  static String _messageForError(Object error) {
    if (error is TimeoutException) {
      return 'Λήξη χρόνου αναμονής — ο διακομιστής δεν ανταποκρίνεται εντός 5 δευτερολέπτων';
    }
    if (error is SocketException) {
      if (_isDnsFailure(error)) {
        return 'Αδυναμία εύρεσης διακομιστή — ελέγξτε το όνομα κεντρικού υπολογιστή';
      }
      return 'Ο διακομιστής δεν απαντά — ελέγξτε τη διεύθυνση και τη συνδεσιμότητα δικτύου';
    }
    return error.toString();
  }

  static bool _isDnsFailure(SocketException error) {
    final message = error.message.toLowerCase();
    if (message.contains('failed host lookup') ||
        message.contains('name or service not known') ||
        message.contains('getaddrinfo') ||
        message.contains('no address associated with hostname') ||
        message.contains('nodename nor servname provided')) {
      return true;
    }
    final osError = error.osError;
    if (osError != null) {
      // Windows WSAHOST_NOT_FOUND / WSANO_DATA
      if (osError.errorCode == 11001 || osError.errorCode == 11004) {
        return true;
      }
    }
    return false;
  }
}
