/// Η πλήρης θέση σε μία γραμμή: «Κτίριο › Όροφος › Τμήμα › Τοποθεσία».
///
/// Διαβάζεται ως διαδρομή από το γενικό στο ειδικό. Ό,τι λείπει παραλείπεται
/// σιωπηλά — «Καινούριο › Γραμματεία Κίνησης» είναι πλήρης απάντηση όταν το
/// τμήμα δεν έχει τοποθετηθεί σε όροφο. Όλα κενά → κενό κείμενο, ώστε ο καλών
/// να κρύψει τη γραμμή αντί να δείξει ένα ορφανό εικονίδιο.
String fullLocationBreadcrumb({
  String? building,
  String? floor,
  String? department,
  String? location,
}) => [building, floor, department, location]
    .map((part) => (part ?? '').trim())
    .where((part) => part.isNotEmpty)
    .join(' › ');
