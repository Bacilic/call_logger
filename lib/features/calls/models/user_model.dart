import '../../../core/services/lookup_service.dart';
import '../../../core/utils/phone_list_parser.dart';

/// Μοντέλο χρήστη (πίνακας users + M2M `user_phones` / `phones`).
/// Το [name] είναι υπολογιζόμενο από first_name + last_name για συμβατότητα.
class UserModel {
  UserModel({
    this.id,
    this.firstName,
    this.lastName,
    this.phones = const [],
    this.departmentId,
    this.location,
    this.notes,
    this.isDeleted = false,
  });

  final int? id;
  final String? firstName;
  final String? lastName;
  /// Κανονικοποιημένα τηλέφωνα (από `phones` / `user_phones`).
  final List<String> phones;
  final int? departmentId;
  /// Φυσική τοποθεσία / γραφείο χρήστη (στήλη `users.location`).
  final String? location;
  final String? notes;
  /// Soft delete (πίνακας users.is_deleted).
  final bool isDeleted;

  /// Ένα string για συμβατότητα με κώδικα που περιμένει ενιαίο κείμενο (π.χ. `PhoneListParser`).
  String get phoneJoined => PhoneListParser.joinPhones(phones);

  /// Πλήρες όνομα (first_name + last_name). Συμβατότητα με κώδικα που χρησιμοποιεί name.
  String? get name {
    final f = firstName?.trim() ?? '';
    final l = lastName?.trim() ?? '';
    if (f.isEmpty && l.isEmpty) return null;
    return '$f $l'.trim();
  }

  String? get departmentName =>
      LookupService.instance.getDepartmentName(departmentId);

  /// Για εμφάνιση σε λίστες (όνομα + τμήμα).
  String get fullNameWithDepartment {
    final n = name?.trim() ?? '';
    final d = departmentName?.trim() ?? '';
    if (n.isEmpty) {
      if (d.isNotEmpty) return d;
      return phoneJoined.trim().isEmpty ? '' : phoneJoined;
    }
    return d.isEmpty ? n : '$n ($d)';
  }

  /// Από `getAllUsers` / joins: λίστα `phones` (όχι ενιαία στήλη `phone`).
  static List<String> _phonesFromMap(Map<String, dynamic> map) {
    final p = map['phones'];
    if (p is! List) return const [];
    return p
        .map((e) => e.toString().trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      id: map['id'] as int?,
      firstName: map['first_name'] as String?,
      lastName: map['last_name'] as String?,
      phones: _phonesFromMap(map),
      departmentId: map['department_id'] as int?,
      location: map['location'] as String?,
      notes: map['notes'] as String?,
      isDeleted: (map['is_deleted'] as int?) == 1,
    );
  }

  /// Για επίπεδο SQLite `users` + ξεχωριστή ενημέρωση `user_phones` μέσω [DatabaseHelper.replaceUserPhones].
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      if (firstName != null) 'first_name': firstName,
      if (lastName != null) 'last_name': lastName,
      'phones': List<String>.from(phones),
      if (departmentId != null) 'department_id': departmentId,
      if (location != null) 'location': location,
      if (notes != null) 'notes': notes,
      'is_deleted': isDeleted ? 1 : 0,
    };
  }

  UserModel copyWith({
    int? id,
    String? firstName,
    String? lastName,
    List<String>? phones,
    int? departmentId,
    String? location,
    String? notes,
    bool? isDeleted,
  }) {
    return UserModel(
      id: id ?? this.id,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      phones: phones ?? this.phones,
      departmentId: departmentId ?? this.departmentId,
      location: location ?? this.location,
      notes: notes ?? this.notes,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}
