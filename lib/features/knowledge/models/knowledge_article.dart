/// Μία «συνταγή» της Βάσης Γνώσης (πίνακας `knowledge_base`).
///
/// Δεν είναι αντίγραφο κλήσης: η κλήση κρατά το δικό της περιστατικό, το άρθρο
/// περιγράφει το **είδος** της βλάβης και εξυπηρετεί δεκάδες κλήσεις.
class KnowledgeArticle {
  const KnowledgeArticle({
    this.id,
    this.title = '',
    this.symptom = '',
    this.solution = '',
    this.tags = '',
    this.categoryId,
    this.categoryName,
    this.sourceCallId,
    this.timesUsed = 0,
    this.lastUsedAt,
    this.createdAt,
    this.updatedAt,
  });

  final int? id;

  /// Ο τίτλος του άρθρου (`topic`) — πώς το αναγνωρίζεις σε λίστα.
  final String title;

  /// Το σύμπτωμα στη γλώσσα του καλούντα, τηλεγραφικά και ανορθόγραφα.
  ///
  /// Είναι το κλειδί ταιριάσματος: την επόμενη φορά το πρόβλημα θα ειπωθεί
  /// ξανά έτσι, όχι με τη διατύπωση του ticket.
  final String symptom;

  /// Η λύση (`content`).
  final String solution;

  /// Λέξεις-κλειδιά χωρισμένες με κόμμα.
  final String tags;

  final int? categoryId;

  /// Το όνομα κατηγορίας από το JOIN — δεν αποθηκεύεται στο άρθρο.
  final String? categoryName;

  /// Η κλήση από την οποία γεννήθηκε το άρθρο, αν γεννήθηκε από κλήση.
  final int? sourceCallId;

  final int timesUsed;
  final String? lastUsedAt;
  final String? createdAt;
  final String? updatedAt;

  /// Οι ετικέτες ως καθαρή λίστα, χωρίς κενά και διπλότυπα.
  List<String> get tagList {
    final seen = <String>{};
    for (final raw in tags.split(',')) {
      final value = raw.trim();
      if (value.isNotEmpty) seen.add(value);
    }
    return seen.toList();
  }

  /// Ένα άρθρο χωρίς σύμπτωμα ή χωρίς λύση δεν εξυπηρετεί κανέναν.
  bool get isUsable => symptom.trim().isNotEmpty && solution.trim().isNotEmpty;

  factory KnowledgeArticle.fromMap(Map<String, Object?> map) {
    return KnowledgeArticle(
      id: map['id'] as int?,
      title: (map['topic'] as String?) ?? '',
      symptom: (map['symptom'] as String?) ?? '',
      solution: (map['content'] as String?) ?? '',
      tags: (map['tags'] as String?) ?? '',
      categoryId: map['category_id'] as int?,
      categoryName: map['category_name'] as String?,
      sourceCallId: map['source_call_id'] as int?,
      timesUsed: (map['times_used'] as int?) ?? 0,
      lastUsedAt: map['last_used_at'] as String?,
      createdAt: map['created_at'] as String?,
      updatedAt: map['updated_at'] as String?,
    );
  }

  /// Μόνο τα πεδία που κατέχει ο χρήστης· μετρητές και χρόνοι τα γράφει το
  /// repository, ώστε ο καλών να μην μπορεί να τα αλλοιώσει κατά λάθος.
  Map<String, Object?> toWriteMap() {
    return <String, Object?>{
      'topic': title.trim(),
      'symptom': symptom.trim(),
      'content': solution.trim(),
      'tags': tagList.join(', '),
      'category_id': categoryId,
      'source_call_id': sourceCallId,
    };
  }

  KnowledgeArticle copyWith({
    int? id,
    String? title,
    String? symptom,
    String? solution,
    String? tags,
    int? categoryId,
    bool clearCategory = false,
    String? categoryName,
    int? sourceCallId,
    int? timesUsed,
    String? lastUsedAt,
    String? createdAt,
    String? updatedAt,
  }) {
    return KnowledgeArticle(
      id: id ?? this.id,
      title: title ?? this.title,
      symptom: symptom ?? this.symptom,
      solution: solution ?? this.solution,
      tags: tags ?? this.tags,
      categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
      categoryName: clearCategory ? null : (categoryName ?? this.categoryName),
      sourceCallId: sourceCallId ?? this.sourceCallId,
      timesUsed: timesUsed ?? this.timesUsed,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
