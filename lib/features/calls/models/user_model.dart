/// Μοντέλο χρήστη (πίνακας users).
class UserModel {
  UserModel({
    this.id,
    this.name,
    this.department,
    this.phone,
    this.location,
    this.notes,
  });

  final int? id;
  final String? name;
  final String? department;
  final String? phone;
  final String? location;
  final String? notes;

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      id: map['id'] as int?,
      name: map['name'] as String?,
      department: map['department'] as String?,
      phone: map['phone'] as String?,
      location: map['location'] as String?,
      notes: map['notes'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (department != null) 'department': department,
      if (phone != null) 'phone': phone,
      if (location != null) 'location': location,
      if (notes != null) 'notes': notes,
    };
  }
}
