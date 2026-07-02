/// Μοντέλο εγγραφής κατηγορίας κλήσεων (`categories`).
class CategoryModel {
  const CategoryModel({
    this.id,
    required this.name,
    this.isDeleted = false,
  });

  final int? id;
  final String name;
  final bool isDeleted;

  factory CategoryModel.fromMap(Map<String, dynamic> map) {
    return CategoryModel(
      id: map['id'] as int?,
      name: (map['name'] as String?)?.trim() ?? '',
      isDeleted: (map['is_deleted'] as int?) == 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name.trim(),
      'is_deleted': isDeleted ? 1 : 0,
    };
  }
}
