/// Μοντέλο εγγραφής κατηγορίας κλήσεων (`categories`).
class CategoryModel {
  const CategoryModel({this.id, required this.name});

  final int? id;
  final String name;

  factory CategoryModel.fromMap(Map<String, dynamic> map) {
    return CategoryModel(
      id: map['id'] as int?,
      name: (map['name'] as String?)?.trim() ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name.trim(),
    };
  }
}
