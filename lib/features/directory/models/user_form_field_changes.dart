/// Στιγμιότυπο των πεδίων της φόρμας υπαλλήλου, για σύγκριση «πριν/τώρα».
typedef UserFormFields = ({
  String lastName,
  String firstName,
  String phone,
  String department,
  String location,
  String notes,
});

/// Οι ετικέτες των πεδίων που άλλαξαν, με τη σειρά που εμφανίζονται στη φόρμα.
List<String> changedUserFieldLabels(UserFormFields before, UserFormFields now) {
  final changes = <String>[];
  if (now.lastName != before.lastName) changes.add('Επώνυμο');
  if (now.firstName != before.firstName) changes.add('Όνομα');
  if (now.phone != before.phone) changes.add('Τηλέφωνο');
  if (now.department != before.department) changes.add('Τμήμα');
  if (now.location != before.location) changes.add('Τοποθεσία');
  if (now.notes != before.notes) changes.add('Σημειώσεις');
  return changes;
}

/// Οι αλλαγές που **φαίνονται μέσα στην καρτέλα του εξοπλισμού** του υπαλλήλου.
///
/// Η καρτέλα εξοπλισμού διαβάζει από τη βάση το ονοματεπώνυμο και το τμήμα του
/// κατόχου (πεδίο «Κάτοχος»), το τμήμα του (κλειδωμένο, «Καθορίζεται από τον
/// κάτοχο») και την τοποθεσία του (όταν «Ακολουθεί τη θέση του κατόχου»).
///
/// Το τηλέφωνο και οι σημειώσεις του υπαλλήλου δεν εμφανίζονται πουθενά εκεί,
/// ούτε τα γράφει η αποθήκευση του εξοπλισμού — αλλαγές σε αυτά δεν μπορούν να
/// δημιουργήσουν ασυμφωνία ανάμεσα στις δύο φόρμες.
List<String> ownerFacingChangedLabels(
  UserFormFields before,
  UserFormFields now,
) {
  const ownerFacing = {'Επώνυμο', 'Όνομα', 'Τμήμα', 'Τοποθεσία'};
  return changedUserFieldLabels(
    before,
    now,
  ).where(ownerFacing.contains).toList();
}
