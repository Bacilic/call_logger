/// Οι κατάλογοι γραφείων και υπαλλήλων για τον ορισμό τοποθέτησης.
///
/// Φορτώνονται **μία φορά** ανά συνεδρία επίλυσης: 296 γραφεία και 503
/// υπάλληλοι δεν χωρούν σε κάθε πρόταση ξεχωριστά.
///
/// Η ομαδοποίηση των υπαλλήλων είναι η ουσία. Στη Λάμπα τους εξοπλισμούς ενός
/// τμήματος τους χρεώνεται συνήθως η προϊσταμένη ή ο διευθυντής, οπότε:
/// - το ίδιο το γραφείο έχει συχνά έναν μόνο υπάλληλο, καμιά φορά με μηδέν
///   εξοπλισμούς — αυτό είναι **φυσιολογικό**, όχι σκουπίδι·
/// - ο πιθανός κάτοχος βρίσκεται ένα σκαλί πιο πάνω, στο τμήμα.
///
/// Γι' αυτό οι υπάλληλοι έρχονται σε τρεις ομάδες — γραφείο, τμήμα, όλη η
/// βάση — και μέσα σε κάθε ομάδα προηγείται όποιος χρεώνεται περισσότερα.
library;

import '../../utils/text_similarity.dart';

class LampPlacementOffice {
  const LampPlacementOffice({
    required this.id,
    required this.officeName,
    this.departmentName,
  });

  final int id;
  final String officeName;
  final String? departmentName;

  /// «27 · Γραφείο Ιατρών Γυναικολογικής · Μαιευτική-Γυναικολογική Κλινική»
  String get label {
    final department = (departmentName ?? '').trim();
    final name = officeName.trim();
    if (department.isEmpty || department == name) return '$id · $name';
    return '$id · $name · $department';
  }
}

class LampPlacementOwner {
  const LampPlacementOwner({
    required this.id,
    required this.name,
    this.officeId,
    this.officeName,
    this.departmentName,
    this.equipmentCount = 0,
  });

  final int id;
  final String name;
  final int? officeId;
  final String? officeName;
  final String? departmentName;

  /// Πόσους εξοπλισμούς χρεώνεται. Το μηδέν **δεν** είναι πρόβλημα εδώ.
  final int equipmentCount;

  /// «81 · Καμπάς Νικόλαος · Διευθυντής Γυναικολογικής»
  String get label {
    final office = (officeName ?? '').trim();
    return office.isEmpty ? '$id · $name' : '$id · $name · $office';
  }

  String get equipmentCountText =>
      equipmentCount == 1 ? '1 εξοπλισμός' : '$equipmentCount εξοπλισμοί';
}

/// Μια ομάδα υπαλλήλων με τον τίτλο της, όπως εμφανίζεται στη λίστα.
/// Προμηθευτής ή κατηγορία σύμβασης.
///
/// Δεν υπάρχουν χωριστοί πίνακες στη Λάμπα — τα ζεύγη `(id, όνομα)` ζουν
/// μέσα στις ίδιες τις συμβάσεις και εξάγονται από εκεί. Ο έλεγχος έδειξε ότι
/// η αντιστοιχία είναι αξιόπιστη: κανένα id δεν φέρει δύο διαφορετικά ονόματα.
class LampContractLookupEntry {
  const LampContractLookupEntry({required this.id, required this.name});

  final int id;
  final String name;

  String get label => '$id · $name';
}

class LampPlacementOwnerGroup {
  const LampPlacementOwnerGroup({required this.title, required this.owners});

  final String title;
  final List<LampPlacementOwner> owners;
}

class LampPlacementCatalog {
  const LampPlacementCatalog({
    required this.offices,
    required this.owners,
    this.suppliers = const <LampContractLookupEntry>[],
    this.contractCategories = const <LampContractLookupEntry>[],
  });

  static const LampPlacementCatalog empty = LampPlacementCatalog(
    offices: <LampPlacementOffice>[],
    owners: <LampPlacementOwner>[],
  );

  final List<LampPlacementOffice> offices;
  final List<LampPlacementOwner> owners;

  /// Οι προμηθευτές που εμφανίζονται ήδη σε συμβάσεις.
  final List<LampContractLookupEntry> suppliers;

  /// Οι κατηγορίες συμβάσεων (Προμήθεια, Δωρεά, Σύμβαση συντήρησης, …).
  final List<LampContractLookupEntry> contractCategories;

  List<LampContractLookupEntry> searchSuppliers(String query, {int limit = 40}) =>
      _search(suppliers, query, limit);

  List<LampContractLookupEntry> searchContractCategories(String query) =>
      _search(contractCategories, query, contractCategories.length);

  static List<LampContractLookupEntry> _search(
    List<LampContractLookupEntry> source,
    String query,
    int limit,
  ) {
    final needle = TextSimilarity.normalize(query);
    final matches = needle.isEmpty
        ? source
        : source
              .where(
                (entry) =>
                    TextSimilarity.normalize(entry.label).contains(needle),
              )
              .toList(growable: false);
    return matches.take(limit).toList(growable: false);
  }

  LampPlacementOffice? officeById(int? id) {
    if (id == null) return null;
    for (final office in offices) {
      if (office.id == id) return office;
    }
    return null;
  }

  /// Γραφεία που ταιριάζουν στο [query] — κενό ερώτημα φέρνει όλα.
  List<LampPlacementOffice> searchOffices(String query, {int limit = 40}) {
    final needle = TextSimilarity.normalize(query);
    final matches = needle.isEmpty
        ? offices
        : offices
              .where(
                (office) => TextSimilarity.normalize(
                  office.label,
                ).contains(needle),
              )
              .toList(growable: false);
    return matches.take(limit).toList(growable: false);
  }

  /// Οι ίδιες ομάδες σε ενιαία λίστα, με τον τίτλο μόνο στο πρώτο στοιχείο
  /// κάθε ομάδας — έτσι η λίστα του autocomplete μένει επίπεδη (τα headers
  /// δεν γίνονται κατά λάθος επιλέξιμα με το πληκτρολόγιο) αλλά διαβάζεται
  /// σαν ομαδοποιημένη.
  List<({LampPlacementOwner owner, String? groupTitle})> flattenedOwnerOptions({
    int? officeId,
    String query = '',
    int limitPerGroup = 25,
  }) {
    return <({LampPlacementOwner owner, String? groupTitle})>[
      for (final group in ownerGroups(
        officeId: officeId,
        query: query,
        limitPerGroup: limitPerGroup,
      ))
        for (var i = 0; i < group.owners.length; i++)
          (owner: group.owners[i], groupTitle: i == 0 ? group.title : null),
    ];
  }

  /// Οι υπάλληλοι σε τρεις ομάδες, φιλτραρισμένοι από το [query].
  ///
  /// Χωρίς επιλεγμένο γραφείο υπάρχει μόνο η τρίτη ομάδα: δεν έχει νόημα να
  /// δείξεις «σε αυτό το γραφείο» όταν δεν υπάρχει γραφείο.
  List<LampPlacementOwnerGroup> ownerGroups({
    int? officeId,
    String query = '',
    int limitPerGroup = 25,
  }) {
    final needle = TextSimilarity.normalize(query);
    bool matchesQuery(LampPlacementOwner owner) =>
        needle.isEmpty ||
        TextSimilarity.normalize(owner.label).contains(needle);

    final office = officeById(officeId);
    final department = (office?.departmentName ?? '').trim();

    final inOffice = <LampPlacementOwner>[];
    final inDepartment = <LampPlacementOwner>[];
    final everyoneElse = <LampPlacementOwner>[];
    for (final owner in owners) {
      if (!matchesQuery(owner)) continue;
      if (office != null && owner.officeId == office.id) {
        inOffice.add(owner);
      } else if (department.isNotEmpty &&
          (owner.departmentName ?? '').trim() == department) {
        inDepartment.add(owner);
      } else {
        everyoneElse.add(owner);
      }
    }

    // Πρώτος όποιος χρεώνεται τα περισσότερα: στη Λάμπα είναι συνήθως ο
    // διευθυντής ή η προϊσταμένη του τμήματος.
    int byEquipment(LampPlacementOwner a, LampPlacementOwner b) {
      final byCount = b.equipmentCount.compareTo(a.equipmentCount);
      return byCount != 0 ? byCount : a.name.compareTo(b.name);
    }

    inOffice.sort(byEquipment);
    inDepartment.sort(byEquipment);
    everyoneElse.sort(byEquipment);

    return <LampPlacementOwnerGroup>[
      if (inOffice.isNotEmpty)
        LampPlacementOwnerGroup(
          title: 'Σε αυτό το γραφείο · ${inOffice.length}',
          owners: inOffice.take(limitPerGroup).toList(growable: false),
        ),
      if (inDepartment.isNotEmpty)
        LampPlacementOwnerGroup(
          title: 'Στο τμήμα «$department» · ${inDepartment.length}',
          owners: inDepartment.take(limitPerGroup).toList(growable: false),
        ),
      if (everyoneElse.isNotEmpty)
        LampPlacementOwnerGroup(
          title: office == null
              ? 'Όλοι οι υπάλληλοι · ${everyoneElse.length}'
              : 'Υπόλοιπη βάση · ${everyoneElse.length}',
          owners: everyoneElse.take(limitPerGroup).toList(growable: false),
        ),
    ];
  }
}
