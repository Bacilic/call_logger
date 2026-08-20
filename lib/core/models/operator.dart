import 'dart:convert';

/// Ο χρήστης της εφαρμογής — αυτός που κάθεται μπροστά στην οθόνη.
///
/// Δεν έχει σχέση με τον πίνακα `users`: εκείνος κρατά τους **υπαλλήλους του
/// νοσοκομείου**, δηλαδή τον κατάλογο. Εδώ ζουν όσοι **χειρίζονται** την
/// εφαρμογή. Στον κώδικα λέγονται `operators` ώστε να μην μπερδεύονται με τους
/// πρώτους· στην οθόνη εμφανίζονται ως «Χρήστες».
class Operator {
  const Operator({
    this.id,
    required this.displayName,
    this.windowsAccount,
    this.isAdmin = false,
    this.isActive = true,
    this.permissionOverrides = const <String, bool>{},
    required this.createdAt,
  });

  final int? id;

  /// Το όνομα που βλέπει ο άνθρωπος — και που σφραγίζει το Ιστορικό.
  final String displayName;

  /// Ο λογαριασμός Windows που ταυτίζεται με αυτό το προφίλ, σε πεζά.
  ///
  /// `null` σημαίνει **αυτόνομο προφίλ**: υπάρχει και δουλεύει, αλλά δεν
  /// αναγνωρίζεται αυτόματα — επιλέγεται ρητά.
  final String? windowsAccount;

  /// Ο διαχειριστής τα μπορεί όλα και δεν περνά από τη λίστα δικαιωμάτων.
  final bool isAdmin;

  final bool isActive;

  /// **Μόνο τα δικαιώματα που άλλαξε ρητά ο διαχειριστής.**
  ///
  /// Ό,τι λείπει από εδώ παίρνει την προεπιλογή του ίδιου του δικαιώματος. Έτσι
  /// ένα νέο δικαίωμα σε μελλοντική έκδοση δεν χρειάζεται καμία διόρθωση στα
  /// υπάρχοντα προφίλ — απλώς ισχύει η προεπιλογή του.
  final Map<String, bool> permissionOverrides;

  final DateTime createdAt;

  Operator copyWith({
    int? id,
    String? displayName,
    String? windowsAccount,
    bool clearWindowsAccount = false,
    bool? isAdmin,
    bool? isActive,
    Map<String, bool>? permissionOverrides,
    DateTime? createdAt,
  }) {
    return Operator(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      windowsAccount: clearWindowsAccount
          ? null
          : (windowsAccount ?? this.windowsAccount),
      isAdmin: isAdmin ?? this.isAdmin,
      isActive: isActive ?? this.isActive,
      permissionOverrides: permissionOverrides ?? this.permissionOverrides,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'display_name': displayName,
    'windows_account': windowsAccount,
    'is_admin': isAdmin ? 1 : 0,
    'is_active': isActive ? 1 : 0,
    'permissions_json': permissionOverrides.isEmpty
        ? null
        : jsonEncode(permissionOverrides),
    'created_at': createdAt.toIso8601String(),
  };

  static Operator fromMap(Map<String, Object?> map) {
    return Operator(
      id: (map['id'] as num?)?.toInt(),
      displayName: (map['display_name'] as String?)?.trim() ?? '',
      windowsAccount: normalizeWindowsAccount(map['windows_account'] as String?),
      isAdmin: _asBool(map['is_admin']),
      isActive: _asBool(map['is_active'], whenNull: true),
      permissionOverrides: decodePermissionOverrides(
        map['permissions_json'] as String?,
      ),
      createdAt:
          DateTime.tryParse((map['created_at'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  static bool _asBool(Object? value, {bool whenNull = false}) {
    if (value == null) return whenNull;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = value.toString().trim().toLowerCase();
    return text == '1' || text == 'true';
  }
}

/// Κανονικοποιεί λογαριασμό Windows για αποθήκευση και σύγκριση.
///
/// Τα Windows δεν ξεχωρίζουν πεζά από κεφαλαία στα ονόματα λογαριασμών, οπότε
/// κρατάμε πάντα πεζά — αλλιώς το ίδιο πρόσωπο θα εμφανιζόταν ως δύο χρήστες.
/// Όπου το περιβάλλον δίνει «ΤΟΜΕΑΣ\όνομα», κρατάμε μόνο το όνομα.
/// Κενό ή `null` σημαίνει «αυτόνομο προφίλ, χωρίς λογαριασμό».
String? normalizeWindowsAccount(String? raw) {
  final trimmed = raw?.trim() ?? '';
  if (trimmed.isEmpty) return null;
  final separator = trimmed.lastIndexOf('\\');
  final name = separator >= 0 ? trimmed.substring(separator + 1) : trimmed;
  final normalized = name.trim().toLowerCase();
  return normalized.isEmpty ? null : normalized;
}

/// Διαβάζει τις αποθηκευμένες παρακάμψεις δικαιωμάτων.
///
/// Χαλασμένο ή άγνωστο περιεχόμενο δίνει **κενές παρακάμψεις**, όχι σφάλμα: ο
/// χρήστης πέφτει στις προεπιλογές αντί να μείνει κλειδωμένος έξω.
Map<String, bool> decodePermissionOverrides(String? raw) {
  final text = raw?.trim() ?? '';
  if (text.isEmpty) return const <String, bool>{};
  try {
    final decoded = jsonDecode(text);
    if (decoded is! Map) return const <String, bool>{};
    final result = <String, bool>{};
    decoded.forEach((key, value) {
      if (key is! String) return;
      if (value is bool) result[key] = value;
    });
    return Map.unmodifiable(result);
  } catch (_) {
    return const <String, bool>{};
  }
}
