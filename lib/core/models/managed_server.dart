/// Ένας διακομιστής με στοιχεία διαχειριστή (πίνακας `servers`).
///
/// Σκόπιμα **γενικός**: δεν ξέρει τίποτα για το medico ούτε για την αποσύνδεση
/// χρήστη. Είναι απλώς «ένα μηχάνημα στο δίκτυο με λογαριασμό διαχειριστή».
/// Κάθε λειτουργία που θα χτιστεί από πάνω (αποσύνδεση σήμερα, επανεκκίνηση
/// αύριο) χρησιμοποιεί την ίδια λίστα — γι' αυτό δεν υπάρχει στήλη
/// «τι υποστηρίζει ο καθένας»: θα γερνούσε με την πρώτη νέα λειτουργία.
class ManagedServer {
  const ManagedServer({
    required this.id,
    required this.name,
    required this.host,
    required this.adminUser,
    required this.adminPassword,
    required this.isDefault,
    required this.sortOrder,
    this.notes,
    this.deletedAt,
  });

  final int id;

  /// Φιλική ονομασία για τον χειριστή (π.χ. «Medico κύριος»).
  final String name;

  /// Διεύθυνση IP ή όνομα υπολογιστή.
  final String host;

  /// Λογαριασμός διαχειριστή **του διακομιστή** (προεπιλογή `Administrator`).
  final String adminUser;

  /// Κωδικός σε καθαρό κείμενο — ρητή απόφαση χρήστη, στα πρότυπα του VNC.
  final String adminPassword;

  /// Ο διακομιστής που προτείνεται όταν ο εξοπλισμός δεν δείχνει κάποιον δικό του.
  final bool isDefault;

  final int sortOrder;
  final String? notes;
  final String? deletedAt;

  bool get hasCredentials =>
      adminUser.trim().isNotEmpty && adminPassword.isNotEmpty;

  /// Ετικέτα για λίστες και επιλογείς: «Medico κύριος — 192.168.13.82».
  String get displayLabel {
    final n = name.trim();
    final h = host.trim();
    if (n.isEmpty) return h;
    if (h.isEmpty) return n;
    return '$n — $h';
  }

  ManagedServer copyWith({
    int? id,
    String? name,
    String? host,
    String? adminUser,
    String? adminPassword,
    bool? isDefault,
    int? sortOrder,
    String? notes,
    String? deletedAt,
    bool clearDeletedAt = false,
  }) {
    return ManagedServer(
      id: id ?? this.id,
      name: name ?? this.name,
      host: host ?? this.host,
      adminUser: adminUser ?? this.adminUser,
      adminPassword: adminPassword ?? this.adminPassword,
      isDefault: isDefault ?? this.isDefault,
      sortOrder: sortOrder ?? this.sortOrder,
      notes: notes ?? this.notes,
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
    );
  }

  factory ManagedServer.fromMap(Map<String, Object?> row) {
    final idRaw = row['id'];
    return ManagedServer(
      id: idRaw is int ? idRaw : int.tryParse('$idRaw') ?? 0,
      name: (row['name'] as String?)?.trim() ?? '',
      host: (row['host'] as String?)?.trim() ?? '',
      adminUser: (row['admin_user'] as String?)?.trim() ?? '',
      adminPassword: (row['admin_password'] as String?) ?? '',
      isDefault: _asBool(row['is_default']),
      sortOrder: _asInt(row['sort_order']),
      notes: (row['notes'] as String?)?.trim(),
      deletedAt: (row['deleted_at'] as String?)?.trim(),
    );
  }

  Map<String, Object?> toInsertMap() => {
    'name': name.trim(),
    'host': host.trim(),
    'admin_user': adminUser.trim(),
    'admin_password': adminPassword,
    'is_default': isDefault ? 1 : 0,
    'sort_order': sortOrder,
    'notes': notes?.trim(),
    'deleted_at': deletedAt,
  };

  static bool _asBool(Object? raw) {
    if (raw is bool) return raw;
    if (raw is int) return raw != 0;
    final s = '${raw ?? ''}'.trim();
    return s == '1' || s.toLowerCase() == 'true';
  }

  static int _asInt(Object? raw) {
    if (raw is int) return raw;
    return int.tryParse('${raw ?? ''}'.trim()) ?? 0;
  }
}
