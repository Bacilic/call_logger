import '../../../core/database/old_database/lamp_cross_check_snapshot.dart';
import '../../../core/utils/text_similarity.dart';
import '../../calls/models/equipment_model.dart';
import '../../calls/models/user_model.dart';
import '../models/catalog_validation_finding.dart';
import '../models/department_model.dart';
import '../models/lamp_cross_check_finding.dart';
import '../models/lamp_cross_check_rules.dart';
import 'lamp_entity_matcher.dart';

/// Συγκρίνει τον Κατάλογο με το μητρώο της Λάμπας και βγάζει τις αποκλίσεις.
///
/// Καθαρή λογική: δέχεται έτοιμα δεδομένα και επιστρέφει ευρήματα, χωρίς να
/// αγγίζει βάση ή οθόνη. Την τροφοδοσία την κάνει ο runner.
class LampCrossCheckService {
  const LampCrossCheckService(this.rules);

  final LampCrossCheckRules rules;

  List<LampCrossCheckFinding> compare({
    required List<UserModel> users,
    required List<DepartmentModel> departments,
    required List<EquipmentModel> equipment,
    required LampCrossCheckSnapshot snapshot,
    required Map<int, List<String>> sharedPhonesByDepartmentId,
    required Map<int, List<int>> ownerUserIdsByEquipmentId,
  }) {
    final findings = <LampCrossCheckFinding>[];
    final userMatches = LampEntityMatcher.matchUsers(users, snapshot);
    final departmentMatches = LampEntityMatcher.matchDepartments(
      departments,
      snapshot,
    );
    final usersById = {
      for (final user in users)
        if (user.id != null) user.id!: user,
    };
    final departmentsById = {
      for (final department in departments)
        if (department.id != null) department.id!: department,
    };

    _checkUsers(findings, users, userMatches, departmentsById, snapshot);
    _checkDepartments(
      findings,
      departments,
      departmentMatches,
      sharedPhonesByDepartmentId,
    );
    _checkEquipment(
      findings,
      equipment,
      snapshot,
      usersById,
      departmentsById,
      userMatches,
      ownerUserIdsByEquipmentId,
    );
    return findings;
  }

  // ---- Υπάλληλοι.

  void _checkUsers(
    List<LampCrossCheckFinding> findings,
    List<UserModel> users,
    Map<int, LampUserMatch> matches,
    Map<int, DepartmentModel> departmentsById,
    LampCrossCheckSnapshot snapshot,
  ) {
    for (final user in users) {
      final id = user.id;
      if (id == null) continue;
      final match = matches[id];
      if (match == null) continue;
      final label = _userLabel(user);

      switch (match.outcome) {
        case LampMatchOutcome.spelling:
          if (rules.userNameSpellingEnabled) {
            findings.add(
              LampCrossCheckFinding(
                kind: LampCrossCheckKind.userNameSpelling,
                title: 'Το όνομα γράφεται αλλιώς στις δύο βάσεις',
                entityKind: CatalogEntityKind.user,
                entityId: id,
                entityLabel: label,
                focusedField: 'lastName',
                catalogValue: label,
                lampValue: match.owner!.fullName,
                note: match.note,
              ),
            );
          }
        case LampMatchOutcome.ambiguous:
          if (rules.userAmbiguousMatchEnabled) {
            findings.add(
              LampCrossCheckFinding(
                kind: LampCrossCheckKind.userAmbiguousMatch,
                title: 'Δεν ξεχωρίζει ποιος είναι στη Λάμπα',
                entityKind: CatalogEntityKind.user,
                entityId: id,
                entityLabel: label,
                focusedField: 'lastName',
                catalogValue: label,
                // Οι υποψήφιοι συνοδεύονται από το γραφείο τους: όταν δύο
                // άνθρωποι έχουν ολόιδιο ονοματεπώνυμο, δύο πανομοιότυπες
                // γραμμές δεν βοηθούν σε τίποτα — ο χρήστης χρειάζεται κάτι
                // που να τους ξεχωρίζει για να πει ποιος είναι ποιος.
                lampValue: match.candidates
                    .take(3)
                    .map((owner) => _ownerWithOffice(owner, snapshot))
                    .join(' · '),
                note: match.note,
              ),
            );
          }
        case LampMatchOutcome.missing:
          if (rules.userMissingInLampEnabled) {
            findings.add(
              LampCrossCheckFinding(
                kind: LampCrossCheckKind.userMissing,
                title: 'Ο υπάλληλος δεν βρέθηκε στη Λάμπα',
                entityKind: CatalogEntityKind.user,
                entityId: id,
                entityLabel: label,
                focusedField: 'lastName',
                catalogValue: label,
                note: 'Η Λάμπα πάγωσε — το νέο προσωπικό λείπει θεμιτά',
              ),
            );
          }
        case LampMatchOutcome.exact:
          break;
      }

      final owner = match.owner;
      if (owner == null) continue;

      if (rules.userDepartmentEnabled) {
        final catalogName = departmentsById[user.departmentId]?.name ?? '';
        final lampName = snapshot.offices[owner.officeId]?.displayName ?? '';
        if (_differentPlace(catalogName, lampName)) {
          findings.add(
            LampCrossCheckFinding(
              kind: LampCrossCheckKind.userDepartment,
              title: 'Ο υπάλληλος ανήκει αλλού στις δύο βάσεις',
              entityKind: CatalogEntityKind.user,
              entityId: id,
              entityLabel: label,
              focusedField: 'department',
              catalogValue: _orDash(catalogName),
              lampValue: _orDash(lampName),
            ),
          );
        }
      }

      _checkPhones(
        findings,
        catalogPhones: user.phones,
        lampPhones: owner.phones,
        onlyInLampEnabled: rules.userPhoneOnlyInLampEnabled,
        onlyInCatalogEnabled: rules.userPhoneOnlyInCatalogEnabled,
        onlyInLampKind: LampCrossCheckKind.userPhoneOnlyInLamp,
        onlyInCatalogKind: LampCrossCheckKind.userPhoneOnlyInCatalog,
        entityKind: CatalogEntityKind.user,
        entityId: id,
        entityLabel: label,
        focusedField: 'phone',
      );
    }
  }

  // ---- Τμήματα.

  void _checkDepartments(
    List<LampCrossCheckFinding> findings,
    List<DepartmentModel> departments,
    Map<int, LampDepartmentMatch> matches,
    Map<int, List<String>> sharedPhonesByDepartmentId,
  ) {
    for (final department in departments) {
      final id = department.id;
      if (id == null) continue;
      final match = matches[id];
      if (match == null) continue;

      switch (match.outcome) {
        case LampMatchOutcome.spelling:
          if (rules.departmentNameSpellingEnabled) {
            findings.add(
              LampCrossCheckFinding(
                kind: LampCrossCheckKind.departmentNameSpelling,
                title: 'Η ονομασία γράφεται αλλιώς στις δύο βάσεις',
                entityKind: CatalogEntityKind.department,
                entityId: id,
                entityLabel: department.name,
                focusedField: 'name',
                catalogValue: department.name,
                lampValue: match.lampName,
                note: match.note,
              ),
            );
          }
        case LampMatchOutcome.ambiguous:
        case LampMatchOutcome.missing:
          if (rules.departmentMissingInLampEnabled) {
            findings.add(
              LampCrossCheckFinding(
                kind: LampCrossCheckKind.departmentMissing,
                title: 'Το τμήμα δεν βρέθηκε στα γραφεία της Λάμπας',
                entityKind: CatalogEntityKind.department,
                entityId: id,
                entityLabel: department.name,
                focusedField: 'name',
                catalogValue: department.name,
                note: match.note,
              ),
            );
          }
        case LampMatchOutcome.exact:
          break;
      }

      if (!match.isResolved) continue;

      _checkPhones(
        findings,
        catalogPhones: sharedPhonesByDepartmentId[id] ?? const [],
        lampPhones: match.phones,
        onlyInLampEnabled: rules.departmentPhoneOnlyInLampEnabled,
        onlyInCatalogEnabled: rules.departmentPhoneOnlyInCatalogEnabled,
        onlyInLampKind: LampCrossCheckKind.departmentPhoneOnlyInLamp,
        onlyInCatalogKind: LampCrossCheckKind.departmentPhoneOnlyInCatalog,
        entityKind: CatalogEntityKind.department,
        entityId: id,
        entityLabel: department.name,
        focusedField: 'phones',
      );
    }
  }

  // ---- Εξοπλισμός.

  void _checkEquipment(
    List<LampCrossCheckFinding> findings,
    List<EquipmentModel> equipment,
    LampCrossCheckSnapshot snapshot,
    Map<int, UserModel> usersById,
    Map<int, DepartmentModel> departmentsById,
    Map<int, LampUserMatch> userMatches,
    Map<int, List<int>> ownerUserIdsByEquipmentId,
  ) {
    for (final item in equipment) {
      final id = item.id;
      final code = item.code?.trim() ?? '';
      if (id == null || code.isEmpty) continue;
      final label = 'Εξοπλισμός $code';
      final lamp = snapshot.equipmentByCode[code];

      if (lamp == null) {
        if (rules.equipmentMissingInLampEnabled &&
            !_isNewerThanLamp(code, snapshot.lastEquipmentCode)) {
          findings.add(
            LampCrossCheckFinding(
              kind: LampCrossCheckKind.equipmentMissing,
              title: 'Ο κωδικός $code δεν υπάρχει στη Λάμπα',
              entityKind: CatalogEntityKind.equipment,
              entityId: id,
              entityLabel: label,
              focusedField: 'code',
              catalogValue: _equipmentDetails(item, departmentsById),
              note: 'Λάθος πληκτρολόγηση, ή μηχάνημα που δεν καταγράφηκε ποτέ',
            ),
          );
        }
        continue;
      }

      if (rules.equipmentRetiredInLampEnabled && _isRetired(lamp.stateName)) {
        findings.add(
          LampCrossCheckFinding(
            kind: LampCrossCheckKind.equipmentRetired,
            title: 'Η Λάμπα το έχει εκτός χρήσης',
            entityKind: CatalogEntityKind.equipment,
            entityId: id,
            entityLabel: label,
            focusedField: 'code',
            catalogValue: _equipmentDetails(item, departmentsById),
            lampValue: lamp.stateName,
          ),
        );
      }

      if (rules.equipmentTypeEnabled) {
        final type = item.type?.trim() ?? '';
        final category = lamp.categoryName;
        if (type.isNotEmpty &&
            category.isNotEmpty &&
            !_sameMeaning(type, category)) {
          findings.add(
            LampCrossCheckFinding(
              kind: LampCrossCheckKind.equipmentType,
              title: 'Το είδος διαφέρει από την κατηγορία της Λάμπας',
              entityKind: CatalogEntityKind.equipment,
              entityId: id,
              entityLabel: label,
              focusedField: 'type',
              catalogValue: type,
              lampValue: category,
              note: 'Συνήθως σημαίνει ότι ο κωδικός δείχνει σε άλλο μηχάνημα',
            ),
          );
        }
      }

      if (rules.equipmentOwnerEnabled) {
        final catalogOwners = [
          for (final userId in ownerUserIdsByEquipmentId[id] ?? const <int>[])
            if (usersById[userId] != null) usersById[userId]!,
        ];
        final lampOwner = snapshot.owners[lamp.ownerId];
        if (catalogOwners.isNotEmpty && lampOwner != null) {
          // Ο κάτοχος θεωρείται ο ίδιος όταν η ταύτιση του Καταλόγου δείχνει
          // στον ίδιο ιδιοκτήτη — έτσι μια διαφορά στη γραφή του ονόματος
          // δεν παριστάνει αλλαγή κατόχου.
          final same = catalogOwners.any(
            (user) => userMatches[user.id]?.owner?.id == lampOwner.id,
          );
          if (!same) {
            findings.add(
              LampCrossCheckFinding(
                kind: LampCrossCheckKind.equipmentOwner,
                title: 'Το μηχάνημα είναι χρεωμένο αλλού',
                entityKind: CatalogEntityKind.equipment,
                entityId: id,
                entityLabel: label,
                focusedField: 'owner',
                catalogValue: catalogOwners.map(_userLabel).join(' · '),
                lampValue: lampOwner.fullName,
              ),
            );
          }
        }
      }

      if (rules.equipmentDepartmentEnabled) {
        final catalogName = _equipmentDepartmentName(
          item,
          departmentsById,
          usersById,
          ownerUserIdsByEquipmentId[id] ?? const <int>[],
        );
        final lampName = snapshot.offices[lamp.officeId]?.displayName ?? '';
        if (_differentPlace(catalogName, lampName)) {
          findings.add(
            LampCrossCheckFinding(
              kind: LampCrossCheckKind.equipmentDepartment,
              title: 'Το μηχάνημα βρίσκεται αλλού στις δύο βάσεις',
              entityKind: CatalogEntityKind.equipment,
              entityId: id,
              entityLabel: label,
              focusedField: 'department',
              catalogValue: _orDash(catalogName),
              lampValue: _orDash(lampName),
            ),
          );
        }
      }
    }
  }

  // ---- Κοινά.

  /// Τα τηλέφωνα που ξέρει μόνο η μία πλευρά, ως δύο ξεχωριστά ευρήματα.
  ///
  /// Χωριστοί διακόπτες επίτηδες: η Λάμπα κρατά συχνά παλιά τηλέφωνα που δεν
  /// αφορούν πια κανέναν, ενώ ένα τηλέφωνο που ξέρει μόνο ο Κατάλογος είναι
  /// συνήθως το φρέσκο. Οι δύο κατευθύνσεις δεν έχουν την ίδια αξία.
  void _checkPhones(
    List<LampCrossCheckFinding> findings, {
    required Iterable<String> catalogPhones,
    required Iterable<String> lampPhones,
    required bool onlyInLampEnabled,
    required bool onlyInCatalogEnabled,
    required LampCrossCheckKind onlyInLampKind,
    required LampCrossCheckKind onlyInCatalogKind,
    required CatalogEntityKind entityKind,
    required int entityId,
    required String entityLabel,
    required String focusedField,
  }) {
    if (!onlyInLampEnabled && !onlyInCatalogEnabled) return;
    final catalog = catalogPhones.map(_digits).where((p) => p.isNotEmpty).toSet();
    final lamp = lampPhones.map(_digits).where((p) => p.isNotEmpty).toSet();

    if (onlyInLampEnabled) {
      final extra = lamp.difference(catalog);
      if (extra.isNotEmpty) {
        findings.add(
          LampCrossCheckFinding(
            kind: onlyInLampKind,
            title: 'Τηλέφωνο που ξέρει μόνο η Λάμπα',
            entityKind: entityKind,
            entityId: entityId,
            entityLabel: entityLabel,
            focusedField: focusedField,
            catalogValue: _orDash(catalog.join(', ')),
            lampValue: extra.join(', '),
          ),
        );
      }
    }

    if (onlyInCatalogEnabled) {
      final extra = catalog.difference(lamp);
      if (extra.isNotEmpty) {
        findings.add(
          LampCrossCheckFinding(
            kind: onlyInCatalogKind,
            title: 'Τηλέφωνο που ξέρει μόνο ο Κατάλογος',
            entityKind: entityKind,
            entityId: entityId,
            entityLabel: entityLabel,
            focusedField: focusedField,
            catalogValue: extra.join(', '),
            lampValue: _orDash(lamp.join(', ')),
          ),
        );
      }
    }
  }

  /// Το τμήμα ενός μηχανήματος: η δική του στήλη, αλλιώς του κατόχου του.
  ///
  /// Ίδια σειρά με τον Κατάλογο — ένα μηχάνημα χωρίς δικό του τμήμα ανήκει
  /// στο τμήμα του ανθρώπου που το κρατά.
  String _equipmentDepartmentName(
    EquipmentModel item,
    Map<int, DepartmentModel> departmentsById,
    Map<int, UserModel> usersById,
    List<int> ownerUserIds,
  ) {
    final own = departmentsById[item.departmentId]?.name ?? '';
    if (own.isNotEmpty) return own;
    for (final userId in ownerUserIds) {
      final name = departmentsById[usersById[userId]?.departmentId]?.name ?? '';
      if (name.isNotEmpty) return name;
    }
    return '';
  }

  /// Τι ξέρει ο Κατάλογος για ένα μηχάνημα, **χωρίς τον κωδικό**: εκείνον τον
  /// λένε ήδη ο τίτλος και η ετικέτα του ευρήματος, και μια τρίτη φορά δεν
  /// προσθέτει τίποτα. Όταν δεν ξέρει τίποτα άλλο, το λέει — για ένα μηχάνημα
  /// που λείπει από τη Λάμπα, το κενό είδος και τμήμα είναι μέρος της ιστορίας.
  String _equipmentDetails(
    EquipmentModel item,
    Map<int, DepartmentModel> departmentsById,
  ) {
    final parts = <String>[
      item.type?.trim() ?? '',
      departmentsById[item.departmentId]?.name ?? '',
    ].where((part) => part.isNotEmpty).toList();
    return parts.isEmpty ? 'Χωρίς είδος και τμήμα' : parts.join(' · ');
  }

  /// Μηχάνημα που γράφτηκε **μετά** το πάγωμα της Λάμπας.
  ///
  /// Η Λάμπα σταμάτησε να ενημερώνεται όταν περάσαμε στο Lansweeper, οπότε
  /// κάθε κωδικός πάνω από τον τελευταίο της είναι θεμιτά άγνωστος — το να
  /// τον δείχνει ο έλεγχος είναι θόρυβος που σκεπάζει τα αληθινά ευρήματα.
  ///
  /// Κωδικός που δεν είναι αριθμός **δεν** σιωπά: δεν συγκρίνεται με το
  /// σύνορο, και είναι ακριβώς η λάθος πληκτρολόγηση που ψάχνει ο έλεγχος.
  static bool _isNewerThanLamp(String code, int? lastLampCode) {
    if (lastLampCode == null) return false;
    final numeric = int.tryParse(code);
    return numeric != null && numeric > lastLampCode;
  }

  static bool _isRetired(String stateName) {
    if (stateName.isEmpty) return false;
    final normalized = TextSimilarity.normalize(stateName).toUpperCase();
    return LampEquipmentRecord.retiredStateRoots.any(normalized.contains);
  }

  /// Δύο ονομασίες θέσης θεωρούνται διαφορετικές μόνο όταν **και οι δύο**
  /// υπάρχουν και δεν εννοούν το ίδιο. Το κενό δεν είναι απόκλιση: για αυτό
  /// υπάρχουν οι δικοί τους κανόνες στους Κανόνες Επικύρωσης.
  static bool _differentPlace(String catalog, String lamp) {
    if (catalog.trim().isEmpty || lamp.trim().isEmpty) return false;
    return !_sameMeaning(catalog, lamp);
  }

  /// Ίδιο νόημα: ταυτίζονται μετά την κανονικοποίηση, ή το ένα περιέχει το
  /// άλλο («Πληροφορική» και «Γραφείο Πληροφορικής»).
  static bool _sameMeaning(String a, String b) {
    final na = TextSimilarity.normalize(a);
    final nb = TextSimilarity.normalize(b);
    if (na.isEmpty || nb.isEmpty) return true;
    return na == nb || na.contains(nb) || nb.contains(na);
  }

  static String _digits(String phone) => phone.replaceAll(RegExp(r'\D'), '');

  static String _orDash(String value) =>
      value.trim().isEmpty ? '—' : value.trim();

  static String _userLabel(UserModel user) =>
      '${user.lastName ?? ''} ${user.firstName ?? ''}'.trim();

  /// «Ορφανού Μαρία (Αιματολογικό)» — το γραφείο ξεχωρίζει τους ομώνυμους.
  static String _ownerWithOffice(
    LampOwnerRecord owner,
    LampCrossCheckSnapshot snapshot,
  ) {
    final office = snapshot.offices[owner.officeId]?.displayName ?? '';
    return office.isEmpty ? owner.fullName : '${owner.fullName} ($office)';
  }
}
