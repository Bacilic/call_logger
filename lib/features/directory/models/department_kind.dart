import 'package:flutter/material.dart';

/// Είδος τμήματος — τι είναι η οντότητα που κουβαλά υπαλλήλους και τηλέφωνα.
///
/// Ο κατάλογος γεννήθηκε από ένα πραγματικό πρόβλημα: οι εξωτερικές εταιρείες
/// (DataMed, Evorad, CCS) καταχωρούνταν ως **υπάλληλοι χωρίς τμήμα**, ενώ στην
/// πράξη συμπεριφέρονται σαν τμήμα — έχουν δικό τους τηλέφωνο κέντρου και
/// κουβαλούν ανθρώπους με τους οποίους μιλάμε ονομαστικά. Ό,τι χρειάζεται η
/// εταιρεία (αναγνώριση κλήσης από τηλέφωνο, «διαλέγω τμήμα και βλέπω τους
/// υπαλλήλους του») το κάνει ήδη το τμήμα· αυτό που έλειπε ήταν να **ξέρει** η
/// εφαρμογή ποιο τμήμα δεν ανήκει στο νοσοκομείο.
///
/// Το είδος δεν είναι κλειδαριά: δεν απαγορεύει τίποτα στον χρήστη. Είναι ο
/// μοχλός για τις εξαιρέσεις που έχουν νόημα — μια εταιρεία δεν ζωγραφίζεται
/// στην κάτοψη του νοσοκομείου και δεν είναι υποψήφια για ticket Lansweeper,
/// αλλά μια κλήση από την DataMed παραμένει κλήση και μετριέται κανονικά.
enum DepartmentKind {
  /// Τμήμα του νοσοκομείου: κλινική, εργαστήριο, γραφείο. Η προεπιλογή.
  hospital('hospital', 'Νοσοκομείο', Icons.local_hospital_outlined),

  /// Εξωτερική εταιρεία/προμηθευτής (DataMed, Agfa, Evorad, CCS).
  company('company', 'Εταιρεία', Icons.business_outlined),

  /// Εξωτερική μονάδα του ίδιου φορέα: Κέντρο Υγείας, ΚΕΦΙΑΠ.
  externalUnit('external_unit', 'Εξωτερική μονάδα', Icons.apartment_outlined);

  const DepartmentKind(this.dbValue, this.label, this.icon);

  /// Πώς λέγεται **η ίδια η οντότητα** στα κουμπιά και τους τίτλους.
  ///
  /// Δεν ταυτίζεται με το [label]: το τμήμα του νοσοκομείου λέγεται «Τμήμα»,
  /// ενώ το είδος του λέγεται «Νοσοκομείο». Χωρίς τη διάκριση, το κουμπί θα
  /// έγραφε «Επεξεργασία Νοσοκομείου».
  String get entityLabel => switch (this) {
    DepartmentKind.hospital => 'Τμήμα',
    DepartmentKind.company => 'Εταιρεία',
    DepartmentKind.externalUnit => 'Εξωτερική μονάδα',
  };

  /// Γενική πτώση — «Επεξεργασία **Εταιρείας**».
  String get entityLabelGenitive => switch (this) {
    DepartmentKind.hospital => 'Τμήματος',
    DepartmentKind.company => 'Εταιρείας',
    DepartmentKind.externalUnit => 'Εξωτερικής μονάδας',
  };

  /// Ονομαστική με άρθρο — «Επαναφέρθηκε **η εταιρεία** «DataMed»».
  ///
  /// Το άρθρο δεν βγαίνει από τη λέξη: το «τμήμα» είναι ουδέτερο, η «εταιρεία»
  /// και η «εξωτερική μονάδα» θηλυκά. Γι' αυτό γράφονται ολόκληρες, όπως ήδη
  /// γίνεται με τον τίτλο νέας εγγραφής.
  String get entityWithArticle => switch (this) {
    DepartmentKind.hospital => 'το τμήμα',
    DepartmentKind.company => 'η εταιρεία',
    DepartmentKind.externalUnit => 'η εξωτερική μονάδα',
  };

  /// Αιτιατική με άρθρο — «αποδεσμεύεται από **την εταιρεία** «DataMed»».
  String get entityWithArticleAccusative => switch (this) {
    DepartmentKind.hospital => 'το τμήμα',
    DepartmentKind.company => 'την εταιρεία',
    DepartmentKind.externalUnit => 'την εξωτερική μονάδα',
  };

  /// Γενική με άρθρο — «η αποθήκευση **της εταιρείας** «DataMed»».
  String get entityGenitiveWithArticle => switch (this) {
    DepartmentKind.hospital => 'του τμήματος',
    DepartmentKind.company => 'της εταιρείας',
    DepartmentKind.externalUnit => 'της εξωτερικής μονάδας',
  };

  /// Τίτλος διαγραμμένης εγγραφής — αλλάζει και το γένος του επιθέτου:
  /// «Διαγραμμένο τμήμα», αλλά «Διαγραμμένη εταιρεία».
  String get deletedEntityTitle => switch (this) {
    DepartmentKind.hospital => 'Διαγραμμένο τμήμα',
    DepartmentKind.company => 'Διαγραμμένη εταιρεία',
    DepartmentKind.externalUnit => 'Διαγραμμένη εξωτερική μονάδα',
  };

  /// Τίτλος νέας εγγραφής — γράφεται ολόκληρος επειδή αλλάζει και το γένος:
  /// «Νέο τμήμα», αλλά «Νέα εταιρεία».
  String get newEntityTitle => switch (this) {
    DepartmentKind.hospital => 'Νέο τμήμα',
    DepartmentKind.company => 'Νέα εταιρεία',
    DepartmentKind.externalUnit => 'Νέα εξωτερική μονάδα',
  };

  /// Η τιμή που γράφεται στη στήλη `departments.kind`.
  final String dbValue;

  /// Η ετικέτα που βλέπει ο χρήστης στη φόρμα και στην αναζήτηση.
  final String label;

  final IconData icon;

  /// Ζωγραφίζεται στην κάτοψη του κτιρίου;
  ///
  /// Μόνο το νοσοκομείο έχει κάτοψη. Ούτε η εταιρεία ούτε το Κέντρο Υγείας
  /// βρίσκονται μέσα στα κτίριά μας, οπότε δεν έχουν θέση να δείξουν.
  bool get belongsOnBuildingMap => this == DepartmentKind.hospital;

  /// Μπορεί να είναι αιτών σε ticket Lansweeper;
  ///
  /// Το Lansweeper ξέρει μόνο λογαριασμούς του νοσοκομείου. Ένας εξωτερικός
  /// συνεργάτης δεν έχει λογαριασμό εκεί, και δεν πρέπει να προτείνεται.
  bool get participatesInLansweeper => this == DepartmentKind.hospital;

  /// Μπορεί να είναι **κάτοχος** εξοπλισμού;
  ///
  /// Κριτήριο είναι η **ιδιοκτησία του μηχανήματος**, όχι η θέση του κτιρίου.
  /// Το Κέντρο Υγείας δουλεύει με δικά μας μηχανήματα, με δικούς μας κωδικούς
  /// και δική μας απομακρυσμένη σύνδεση — γι' αυτό υπάρχει άλλωστε το AnyDesk.
  /// Τα μηχανήματα της DataMed δεν είναι δικά μας: όταν η DataMed τηλεφωνεί,
  /// μιλά **για** δικό μας μηχάνημα — άλλο η αναφορά, άλλο η κατοχή.
  bool get canOwnEquipment => this != DepartmentKind.company;

  /// Οφείλει να ανήκει σε κτίριο του νοσοκομείου;
  ///
  /// Ο κανόνας επικύρωσης «Δεν έχει κτίριο» έχει νόημα μόνο εδώ: το κτίριο της
  /// DataMed δεν είναι δικό μας και δεν υπάρχει στον κατάλογο κτιρίων.
  bool get expectsHospitalBuilding => this == DepartmentKind.hospital;

  /// Το είδος από την αποθηκευμένη τιμή, με πτώση στο [hospital].
  ///
  /// Άγνωστη ή κενή τιμή σημαίνει «γράφτηκε πριν υπάρξει το πεδίο» ή «γράφτηκε
  /// από νεότερη έκδοση». Και στις δύο περιπτώσεις η ασφαλής ανάγνωση είναι
  /// «τμήμα του νοσοκομείου»: έτσι μια παλιά βάση συμπεριφέρεται ακριβώς όπως
  /// συμπεριφερόταν πάντα, χωρίς να εξαφανιστεί τμήμα από τον χάρτη.
  static DepartmentKind fromDbValue(Object? value) {
    final raw = value?.toString().trim();
    if (raw == null || raw.isEmpty) return DepartmentKind.hospital;
    for (final kind in DepartmentKind.values) {
      if (kind.dbValue == raw) return kind;
    }
    return DepartmentKind.hospital;
  }
}
