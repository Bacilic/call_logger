/// Σφράγισμα των μυστικών που ζουν μέσα στη βάση.
///
/// **Τι είναι και τι ΔΕΝ είναι.** Το κλειδί του σφραγίσματος ζει μέσα στην ίδια
/// την εφαρμογή, γιατί η εφαρμογή οφείλει να διαβάζει τα μυστικά μόνη της σε
/// κάθε σταθμό, χωρίς ρύθμιση και χωρίς κωδικό. Συνέπεια: αυτό είναι
/// **σφραγισμένος φάκελος, όχι κλειδαριά**. Σταματά όποιον ανοίγει το αρχείο
/// της βάσης με εργαλείο και διαβάζει το κλειδί — το σενάριο για το οποίο
/// φτιάχτηκε. Δεν σταματά κάποιον που έχει την εφαρμογή και ψάχνει μέσα της.
///
/// Απόφαση Διευθυντή 27/09/2026: ρητή απόρριψη του δεσίματος στον λογαριασμό
/// των Windows, ώστε τα κλειδιά να συνεχίσουν να ταξιδεύουν με τη βάση.
library;

import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'settings_repository.dart';

/// Κλειδιά κοινών ρυθμίσεων που κουβαλούν μυστικό.
const Set<String> kSealedSettingKeys = {
  kLansweeperApiKeySettingKey,
  kGeminiApiKeySettingKey,
};

/// Κλειδιά προσωπικών ρυθμίσεων που κουβαλούν μυστικό.
///
/// Η τιμή οφείλει να ταυτίζεται με το `OverridableSettingKeys.geminiApiKey`·
/// δεν εισάγεται από εκεί για να μη γεννηθεί κύκλος εξαρτήσεων, και η ταύτιση
/// φυλάγεται με έλεγχο.
const Set<String> kSealedOperatorSettingKeys = {'gemini_api_key_override'};

/// Πρόθεμα που ξεχωρίζει τη σφραγισμένη τιμή από παλιά ακάλυπτη.
const String kSettingSealPrefix = 'sealed:v1:';

/// Το μυστικό του σφραγίσματος. Αλλάζοντάς το, κάθε ήδη σφραγισμένη τιμή
/// γίνεται μη αναγνώσιμη — τα κλειδιά θα πρέπει να ξαναγραφούν.
const String _kAppSealSecret =
    'call_logger.settings.seal.2026-09:Κ7ρ4πτ0-Φ8κ3λ0ς-9Δ2';

const int _kSaltLength = 8;
const int _kMacLength = 8;

/// True όταν η αποθηκευμένη τιμή είναι σφραγισμένη από εμάς.
bool isSealedSettingValue(String stored) =>
    stored.startsWith(kSettingSealPrefix);

/// Σφραγίζει την [plain] για αποθήκευση. Η κενή τιμή μένει κενή — «δεν έχει
/// οριστεί κλειδί» δεν είναι μυστικό, και σφραγίζοντάς το θα έμοιαζε με τιμή.
String sealSettingValue(String plain) {
  if (plain.isEmpty) return '';
  final random = Random.secure();
  final salt = List<int>.generate(_kSaltLength, (_) => random.nextInt(256));
  final cipher = _xorWithKeystream(utf8.encode(plain), salt);
  final mac = _macOf(salt, cipher);
  return '$kSettingSealPrefix${base64.encode([...salt, ...mac, ...cipher])}';
}

/// Ξεσφραγίζει την αποθηκευμένη τιμή.
///
/// - Τιμή χωρίς σφραγίδα επιστρέφεται **ως έχει**: είναι παλιά ακάλυπτη
///   εγγραφή, γραμμένη πριν μπει το σφράγισμα.
/// - Σφραγισμένη αλλά αλλοιωμένη τιμή δίνει `null` — ο καλών το δείχνει ως
///   «δεν έχει οριστεί» αντί να στείλει σκουπίδι στο δίκτυο.
String? unsealSettingValue(String stored) {
  if (!isSealedSettingValue(stored)) return stored;
  final payload = stored.substring(kSettingSealPrefix.length);

  final List<int> bytes;
  try {
    bytes = base64.decode(payload);
  } on FormatException {
    return null;
  }
  if (bytes.length < _kSaltLength + _kMacLength) return null;

  final salt = bytes.sublist(0, _kSaltLength);
  final mac = bytes.sublist(_kSaltLength, _kSaltLength + _kMacLength);
  final cipher = bytes.sublist(_kSaltLength + _kMacLength);
  if (!_macMatches(mac, _macOf(salt, cipher))) return null;

  try {
    return utf8.decode(_xorWithKeystream(cipher, salt));
  } on FormatException {
    return null;
  }
}

List<int> _xorWithKeystream(List<int> data, List<int> salt) {
  final out = List<int>.filled(data.length, 0);
  final hmac = Hmac(sha256, utf8.encode(_kAppSealSecret));
  var block = <int>[];
  var counter = 0;
  for (var i = 0; i < data.length; i++) {
    final offset = i % 32;
    if (offset == 0) {
      block = hmac.convert([...salt, ..._counterBytes(counter)]).bytes;
      counter++;
    }
    out[i] = data[i] ^ block[offset];
  }
  return out;
}

List<int> _counterBytes(int counter) => [
  (counter >> 24) & 0xFF,
  (counter >> 16) & 0xFF,
  (counter >> 8) & 0xFF,
  counter & 0xFF,
];

List<int> _macOf(List<int> salt, List<int> cipher) {
  final hmac = Hmac(sha256, utf8.encode('$_kAppSealSecret:mac'));
  return hmac.convert([...salt, ...cipher]).bytes.sublist(0, _kMacLength);
}

/// Σύγκριση σταθερού χρόνου — δεν αποκαλύπτει πόσα ψηφία ταίριαξαν.
bool _macMatches(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}
