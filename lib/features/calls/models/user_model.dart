/// Μοντέλο χρήστη (πίνακας users): id, last_name, first_name, phone, department, location, notes.
/// Το [name] είναι υπολογιζόμενο από first_name + last_name για συμβατότητα.
class UserModel {
  UserModel({
    this.id,
    this.firstName,
    this.lastName,
    this.phone,
    this.department,
    this.location,
    this.notes,
  });

  final int? id;
  final String? firstName;
  final String? lastName;
  final String? phone;
  final String? department;
  final String? location;
  final String? notes;

  /// Πλήρες όνομα (first_name + last_name). Συμβατότητα με κώδικα που χρησιμοποιεί name.
  String? get name {
    final f = firstName?.trim() ?? '';
    final l = lastName?.trim() ?? '';
    if (f.isEmpty && l.isEmpty) return null;
    return '$f $l'.trim();
  }

  /// Για εμφάνιση σε λίστες (όνομα + τμήμα).
  String get fullNameWithDepartment {
    final n = name?.trim() ?? '';
    final d = department?.trim() ?? '';
    if (n.isEmpty) return d.isNotEmpty ? d : (phone ?? '');
    return d.isEmpty ? n : '$n ($d)';
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    // Νέο σχήμα: first_name, last_name. Παλιό: name (fallback για συμβατότητα).
    final fn = map['first_name'] as String?;
    final ln = map['last_name'] as String?;
    final legacyName = map['name'] as String?;
    String? firstName = fn;
    String? lastName = ln;
    if ((firstName == null || lastName == null) && legacyName != null) {
      final parts = legacyName.trim().split(RegExp(r'\s+'));
      if (parts.isEmpty) {
        firstName = firstName ?? '';
        lastName = lastName ?? '';
      } else {
        lastName = lastName ?? parts.last;
        firstName = firstName ?? parts.sublist(0, parts.length - 1).join(' ');
      }
    }
    return UserModel(
      id: map['id'] as int?,
      firstName: firstName,
      lastName: lastName,
      phone: map['phone'] as String?,
      department: map['department'] as String?,
      location: map['location'] as String?,
      notes: map['notes'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      if (firstName != null) 'first_name': firstName,
      if (lastName != null) 'last_name': lastName,
      if (phone != null) 'phone': phone,
      if (department != null) 'department': department,
      if (location != null) 'location': location,
      if (notes != null) 'notes': notes,
    };
  }
}
