import '../../../core/services/current_operator.dart';
import '../../../core/utils/conflict_actor_text.dart';
import '../../../core/utils/history_entity_display_utils.dart';

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
    this.categoryIsDeleted = false,
    this.sourceCallId,
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

  /// Η κατηγορία έχει διαγραφεί από τον Κατάλογο — από το JOIN, δεν
  /// αποθηκεύεται στο άρθρο.
  final bool categoryIsDeleted;

  /// Το όνομα κατηγορίας όπως το βλέπει ο χρήστης: με «(διαγραμμένο)» όταν
  /// δεν υπάρχει πια στον Κατάλογο, όπως στις κλήσεις και τις εκκρεμότητες.
  /// `null` όταν το άρθρο δεν έχει κατηγορία.
  String? get categoryDisplayName {
    final name = categoryName?.trim() ?? '';
    if (name.isEmpty) return null;
    return historyDeletedDisplayLabel(
      name,
      isDeleted: categoryIsDeleted,
      deletedSuffix: kCatalogEntityDeletedSuffix,
    );
  }

  /// Η κλήση από την οποία γεννήθηκε το άρθρο, αν γεννήθηκε από κλήση.
  final int? sourceCallId;

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
      categoryIsDeleted: historyEntityIsDeleted(map['category_is_deleted']),
      sourceCallId: map['source_call_id'] as int?,
      createdAt: map['created_at'] as String?,
      updatedAt: map['updated_at'] as String?,
    );
  }

  /// Μόνο τα πεδία που κατέχει ο χρήστης· τους χρόνους τους γράφει το
  /// repository, ώστε ο καλών να μην μπορεί να τους αλλοιώσει κατά λάθος.
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

  /// Το ίδιο περιεχόμενο ως **νέο** άρθρο: χωρίς id και χρόνους, ώστε η
  /// αποθήκευση να το δημιουργήσει αντί να ψάξει γραμμή που δεν υπάρχει.
  KnowledgeArticle asNewArticle() => KnowledgeArticle(
    title: title,
    symptom: symptom,
    solution: solution,
    tags: tags,
    categoryId: categoryId,
    categoryName: categoryName,
    categoryIsDeleted: categoryIsDeleted,
    sourceCallId: sourceCallId,
  );

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
      categoryIsDeleted: clearCategory ? false : categoryIsDeleted,
      sourceCallId: sourceCallId ?? this.sourceCallId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Το άρθρο διαγράφηκε από άλλον όσο ήταν ανοιχτό για διόρθωση — δεν γράφτηκε
/// τίποτα. Η φόρμα προσφέρει να αποθηκευτεί η διόρθωση ως νέο άρθρο.
class KnowledgeArticleDeletedException implements Exception {
  const KnowledgeArticleDeletedException({this.deletedBy, this.deletedAt});

  /// Ποιος το διέγραψε, όπως το γράφει το Ιστορικό — `null` αν δεν φαίνεται.
  final String? deletedBy;
  final DateTime? deletedAt;

  /// Το κείμενο του παραθύρου: ποιος και πότε, όσο το ξέρουμε.
  String describe({required DateTime now}) {
    final who = (deletedBy ?? '').trim();
    final byWhom = who.isEmpty || who == CurrentOperator.unknownAuditName
        ? ''
        : ' από τον χρήστη «$who»';
    return 'Όσο το διορθώνατε, το άρθρο διαγράφηκε$byWhom'
        '${conflictMomentSuffix(deletedAt, now: now)}. '
        'Η διόρθωσή σας δεν έχει αποθηκευτεί.';
  }

  @override
  String toString() =>
      'Το άρθρο διαγράφηκε από άλλον χρήστη όσο ήταν ανοιχτό για διόρθωση.';
}
