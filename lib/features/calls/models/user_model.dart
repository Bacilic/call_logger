/// Μοντέλο χρήστη (πίνακας users): id, name, phone, department, location, notes.
class UserModel {
  UserModel({
    this.id,
    this.name,
    this.phone,
    this.department,
    this.location,
    this.notes,
  });

  final int? id;
  final String? name;
  final String? phone;
  final String? department;
  final String? location;
  final String? notes;

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      id: map['id'] as int?,
      name: map['name'] as String?,
      phone: map['phone'] as String?,
      department: map['department'] as String?,
      location: map['location'] as String?,
      notes: map['notes'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (phone != null) 'phone': phone,
      if (department != null) 'department': department,
      if (location != null) 'location': location,
      if (notes != null) 'notes': notes,
    };
  }
}
