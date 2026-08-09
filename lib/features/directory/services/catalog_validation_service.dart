import 'package:characters/characters.dart';

import '../../../core/utils/search_text_normalizer.dart';
import '../../calls/models/equipment_model.dart';
import '../../calls/models/user_model.dart';
import '../models/catalog_validation_finding.dart';
import '../models/catalog_validation_rules.dart';
import '../models/department_model.dart';

/// Καθαρή λογική των κανόνων επικύρωσης Καταλόγου.
///
/// Κάθε μέθοδος επιστρέφει το κείμενο υπόδειξης ή `null` όταν όλα είναι
/// εντάξει. Οι υποδείξεις είναι προειδοποιήσεις — ποτέ δεν εμποδίζουν
/// την αποθήκευση· η εμφάνισή τους είναι δουλειά του UI.
class CatalogValidationService {
  const CatalogValidationService(this.rules);

  final CatalogValidationRules rules;

  static final RegExp _digitsOnly = RegExp(r'^[0-9]+$');
  static final RegExp _anyLetter = RegExp(r'\p{L}', unicode: true);
  static final RegExp _startsWithLetter = RegExp(r'^\p{L}', unicode: true);

  /// Υπόδειξη για ΕΝΑΝ τηλεφωνικό αριθμό.
  ///
  /// Μη αριθμητικές τιμές μένουν ασχολίαστες — οι κανόνες αφορούν αριθμούς.
  /// Το πρόθεμα εξετάζεται ΜΟΝΟ όταν το πλήθος ψηφίων ταυτίζεται με τα
  /// ψηφία εσωτερικού· τα εξωτερικά τηλέφωνα δεν έχουν πρόθεμα.
  String? phoneHint(String value) {
    final s = value.trim();
    if (s.isEmpty || !_digitsOnly.hasMatch(s)) return null;

    if (rules.internalPrefixEnabled && s.length == rules.internalPhoneDigits) {
      final prefixLength = rules.internalPrefixFrom.toString().length;
      if (s.length >= prefixLength) {
        final prefix = int.parse(s.substring(0, prefixLength));
        if (prefix < rules.internalPrefixFrom ||
            prefix > rules.internalPrefixTo) {
          return 'Το $s δεν ξεκινά από '
              '${rules.internalPrefixFrom}–${rules.internalPrefixTo}';
        }
      }
    }

    final expectations = <String>[
      if (rules.internalPhoneDigitsEnabled)
        '${rules.internalPhoneDigits} (εσωτερικό)',
      if (rules.externalPhoneDigitsEnabled)
        '${rules.externalPhoneDigits} (εξωτερικό)',
    ];
    if (expectations.isEmpty) return null;

    final matchesInternal =
        rules.internalPhoneDigitsEnabled &&
        s.length == rules.internalPhoneDigits;
    final matchesExternal =
        rules.externalPhoneDigitsEnabled &&
        s.length == rules.externalPhoneDigits;
    if (matchesInternal || matchesExternal) return null;

    return 'Το $s έχει ${s.length} ψηφία — '
        'αναμένονται ${expectations.join(' ή ')}';
  }

  /// Υπόδειξη για πεδίο με πολλαπλά τηλέφωνα χωρισμένα με κόμμα.
  /// Επιστρέφει την πρώτη υπόδειξη που θα βρεθεί.
  String? phonesFieldHint(String rawField) {
    for (final segment in rawField.split(',')) {
      final hint = phoneHint(segment);
      if (hint != null) return hint;
    }
    return null;
  }

  /// Υπόδειξη για κωδικό εξοπλισμού: πλήθος ψηφίων εντός εύρους.
  /// Μη αριθμητικοί κωδικοί μένουν ασχολίαστοι.
  String? equipmentCodeHint(String value) {
    if (!rules.equipmentDigitsEnabled) return null;
    final s = value.trim();
    if (s.isEmpty || !_digitsOnly.hasMatch(s)) return null;
    if (s.length >= rules.equipmentMinDigits &&
        s.length <= rules.equipmentMaxDigits) {
      return null;
    }
    final expected = rules.equipmentMinDigits == rules.equipmentMaxDigits
        ? '${rules.equipmentMinDigits}'
        : '${rules.equipmentMinDigits} έως ${rules.equipmentMaxDigits}';
    return 'Το $s έχει ${s.length} ψηφία — αναμένονται $expected';
  }

  /// Υπόδειξη για όνομα τμήματος: να περιέχει τουλάχιστον ένα γράμμα,
  /// αλλιώς μοιάζει με αριθμό/τηλέφωνο (το ιστορικό λάθος του πεδίου).
  String? departmentNameHint(String value) {
    if (!rules.departmentNameEnabled) return null;
    final s = value.trim();
    if (s.isEmpty || _anyLetter.hasMatch(s)) return null;
    return 'Το «$s» μοιάζει με αριθμό ή τηλέφωνο, όχι με όνομα τμήματος';
  }

  /// Υπόδειξη για όνομα/επώνυμο υπαλλήλου: να ξεκινά από γράμμα.
  ///
  /// Παραμένει υπόδειξη — καλούντες-εταιρείες (π.χ. «3π») είναι θεμιτοί.
  /// Σύμβολα δηλωμένα στις εξαιρέσεις περνούν καθαρά: το «Όνομα» κρατά
  /// συχνά το πώς φωνάζουν τον άνθρωπο, «(Γωγώ) Γεωργία».
  String? personNameHint(String value) {
    if (!rules.personNameEnabled) return null;
    final s = value.trim();
    if (s.isEmpty || _startsWithLetter.hasMatch(s)) return null;
    if (rules.personNameAllowedSymbolSet.contains(s.characters.first)) {
      return null;
    }
    return 'Ξεκινά από ψηφίο ή σύμβολο — σωστό μόνο αν πρόκειται για εταιρεία';
  }

  /// Υποδείξεις για τα πεδία μιας **γρήγορης καταχώρησης**, έτοιμες γραμμές.
  ///
  /// Η γρήγορη καταχώρηση γίνεται ενώ ο χρήστης μιλά στο τηλέφωνο: δεν τον
  /// διακόπτουμε. Οι υποδείξεις ταξιδεύουν στην εκκρεμότητα που δημιουργείται
  /// ούτως ή άλλως, για έλεγχο σε ήρεμη στιγμή.
  ///
  /// Ίδια μορφή με τη λίστα του «Έλεγχος δεδομένων» (`πεδίο — μήνυμα`), ώστε
  /// ο χρήστης να αναγνωρίζει το ίδιο πράγμα όπου κι αν το δει.
  List<String> quickAddHints({
    String? callerName,
    String? phones,
    String? departmentName,
    String? equipmentCode,
  }) {
    final out = <String>[];
    final nameHint = personNameHint(callerName ?? '');
    if (nameHint != null) out.add('Όνομα — $nameHint');
    final phoneHint = phonesFieldHint(phones ?? '');
    if (phoneHint != null) out.add('Τηλέφωνο — $phoneHint');
    final departmentHint = departmentNameHint(departmentName ?? '');
    if (departmentHint != null) out.add('Τμήμα — $departmentHint');
    final equipHint = equipmentCodeHint(equipmentCode ?? '');
    if (equipHint != null) out.add('Εξοπλισμός — $equipHint');
    return out;
  }

  /// Σάρωση ΥΠΑΡΧΟΝΤΩΝ δεδομένων με τους ίδιους κανόνες που ισχύουν στις
  /// φόρμες. Καθαρή συνάρτηση: δέχεται ό,τι έχει ήδη διαβαστεί από τη βάση
  /// και επιστρέφει τα ευρήματα ταξινομημένα (υπάλληλοι → τμήματα →
  /// εξοπλισμός), ώστε η λίστα να διαβάζεται με τη σειρά των καρτελών.
  ///
  /// Το [sharedPhonesByDepartmentId] κρατά τα κοινόχρηστα τηλέφωνα κάθε
  /// τμήματος — δεν ζουν στο [DepartmentModel], τα δίνει ο καλών.
  /// Το [ownerUserIdsByEquipmentId] κρατά τους κατόχους κάθε εξοπλισμού
  /// (πίνακας `user_equipment`) — κι αυτούς τους δίνει ο καλών.
  /// Οι διαγραμμένες εγγραφές αγνοούνται: δεν επεξεργάζονται από πουθενά.
  ///
  /// Μετά τους ανά-πεδίο κανόνες έρχονται οι ΔΙΑΣΤΑΥΡΩΣΕΙΣ: κανόνες που
  /// συγκρίνουν εγγραφές μεταξύ τους. Κάθε διένεξη βγαίνει ως ΜΙΑ κάρτα
  /// με όλες τις εμπλεκόμενες εγγραφές μαζί — όχι ένα εύρημα ανά εγγραφή.
  /// Οι χρονοσφραγίδες των εγγραφών ΔΕΝ γεμίζουν εδώ (θέλουν βάση) —
  /// τις συμπληρώνει ο runner από το Ιστορικό Εφαρμογής.
  List<CatalogValidationFinding> scan({
    required List<UserModel> users,
    required List<DepartmentModel> departments,
    required List<EquipmentModel> equipment,
    Map<int, List<String>> sharedPhonesByDepartmentId = const {},
    Map<int, List<int>> ownerUserIdsByEquipmentId = const {},
  }) {
    final findings = <CatalogValidationFinding>[];

    final activeUsers = users
        .where((u) => u.id != null && !u.isDeleted)
        .toList();
    final activeEquipment = equipment
        .where((e) => e.id != null && !e.isDeleted)
        .toList();
    final departmentNameById = <int, String>{
      for (final d in departments)
        if (d.id != null && d.name.trim().isNotEmpty) d.id!: d.name.trim(),
    };
    final equipmentCodesByUserId = <int, List<String>>{};
    for (final entry in ownerUserIdsByEquipmentId.entries) {
      final code =
          (activeEquipment.where((e) => e.id == entry.key).firstOrNull?.code ??
                  '')
              .trim();
      if (code.isEmpty) continue;
      for (final userId in entry.value) {
        equipmentCodesByUserId.putIfAbsent(userId, () => []).add(code);
      }
    }

    _addFieldHintFindings(
      findings,
      users: activeUsers,
      departments: departments,
      equipment: activeEquipment,
      sharedPhonesByDepartmentId: sharedPhonesByDepartmentId,
    );
    _addEmptyDepartmentFindings(
      findings,
      users: activeUsers,
      departments: departments,
      equipment: activeEquipment,
      sharedPhonesByDepartmentId: sharedPhonesByDepartmentId,
    );
    _addPhoneEquipmentCodeFindings(
      findings,
      users: activeUsers,
      departments: departments,
      equipment: activeEquipment,
      sharedPhonesByDepartmentId: sharedPhonesByDepartmentId,
      departmentNameById: departmentNameById,
      equipmentCodesByUserId: equipmentCodesByUserId,
    );
    _addNameConflictFindings(
      findings,
      users: activeUsers,
      departmentNameById: departmentNameById,
      equipmentCodesByUserId: equipmentCodesByUserId,
    );
    _addCrossDepartmentPhoneFindings(
      findings,
      users: activeUsers,
      departmentNameById: departmentNameById,
      equipmentCodesByUserId: equipmentCodesByUserId,
    );
    _addEquipmentOwnerDepartmentFindings(
      findings,
      users: activeUsers,
      equipment: activeEquipment,
      ownerUserIdsByEquipmentId: ownerUserIdsByEquipmentId,
      departmentNameById: departmentNameById,
      equipmentCodesByUserId: equipmentCodesByUserId,
    );

    return findings;
  }

  /// Οι ανά-πεδίο κανόνες: μία εγγραφή, ένα πεδίο, ένα εύρημα.
  void _addFieldHintFindings(
    List<CatalogValidationFinding> findings, {
    required List<UserModel> users,
    required List<DepartmentModel> departments,
    required List<EquipmentModel> equipment,
    required Map<int, List<String>> sharedPhonesByDepartmentId,
  }) {
    void add({
      required CatalogEntityKind kind,
      required int entityId,
      required String label,
      required String fieldLabel,
      required String message,
      required String focusedField,
    }) {
      findings.add(
        CatalogValidationFinding(
          type: CatalogFindingType.fieldHint,
          message: message,
          fieldLabel: fieldLabel,
          records: [
            CatalogFindingRecord(
              kind: kind,
              entityId: entityId,
              label: label,
              focusedField: focusedField,
            ),
          ],
        ),
      );
    }

    for (final user in users) {
      final label = _userLabel(user);

      final lastNameHint = personNameHint(user.lastName ?? '');
      if (lastNameHint != null) {
        add(
          kind: CatalogEntityKind.user,
          entityId: user.id!,
          label: label,
          fieldLabel: 'Επώνυμο',
          message: lastNameHint,
          focusedField: 'lastName',
        );
      }

      final firstNameHint = personNameHint(user.firstName ?? '');
      if (firstNameHint != null) {
        add(
          kind: CatalogEntityKind.user,
          entityId: user.id!,
          label: label,
          fieldLabel: 'Όνομα',
          message: firstNameHint,
          focusedField: 'firstName',
        );
      }

      // Ένα εύρημα ανά προβληματικό τηλέφωνο: ο υπάλληλος μπορεί να έχει
      // πολλά και ο χρήστης θέλει να ξέρει ποιο φταίει.
      for (final phone in user.phones) {
        final hint = phoneHint(phone);
        if (hint == null) continue;
        add(
          kind: CatalogEntityKind.user,
          entityId: user.id!,
          label: label,
          fieldLabel: 'Τηλέφωνο',
          message: hint,
          focusedField: 'phone',
        );
      }
    }

    for (final department in departments) {
      final id = department.id;
      if (id == null) continue;
      final label = _departmentLabel(department);

      final nameHint = departmentNameHint(department.name);
      if (nameHint != null) {
        add(
          kind: CatalogEntityKind.department,
          entityId: id,
          label: label,
          fieldLabel: 'Όνομα',
          message: nameHint,
          focusedField: 'name',
        );
      }

      for (final phone in sharedPhonesByDepartmentId[id] ?? const <String>[]) {
        final hint = phoneHint(phone);
        if (hint == null) continue;
        add(
          kind: CatalogEntityKind.department,
          entityId: id,
          label: label,
          fieldLabel: 'Κοινόχρηστο τηλέφωνο',
          message: hint,
          focusedField: 'phones',
        );
      }
    }

    for (final item in equipment) {
      final hint = equipmentCodeHint(item.code ?? '');
      if (hint == null) continue;
      add(
        kind: CatalogEntityKind.equipment,
        entityId: item.id!,
        label: _equipmentLabel(item),
        fieldLabel: 'Κωδικός',
        message: hint,
        focusedField: 'code',
      );
    }
  }

  /// Τμήματα χωρίς κανένα εξάρτημα: ούτε υπάλληλο, ούτε κοινόχρηστο τηλέφωνο,
  /// ούτε εξοπλισμό.
  ///
  /// Δεν είναι σφάλμα — ένα τμήμα μπορεί να αδειάσει θεμιτά (ανακαίνιση,
  /// συγχώνευση). Είναι όμως **κατάσταση** που ζητά απόφαση, και μπορεί να
  /// προκύψει από δώδεκα διαφορετικές ενέργειες· γι' αυτό ελέγχεται εδώ, στα
  /// δεδομένα, αντί να τη φυλάει καθεμιά τους χωριστά.
  void _addEmptyDepartmentFindings(
    List<CatalogValidationFinding> findings, {
    required List<UserModel> users,
    required List<DepartmentModel> departments,
    required List<EquipmentModel> equipment,
    required Map<int, List<String>> sharedPhonesByDepartmentId,
  }) {
    if (!rules.emptyDepartmentEnabled) return;

    final departmentIdsWithUsers = users.map((u) => u.departmentId).toSet();
    final departmentIdsWithEquipment = equipment
        .map((e) => e.departmentId)
        .toSet();

    for (final department in departments) {
      final id = department.id;
      if (id == null) continue;
      if (departmentIdsWithUsers.contains(id)) continue;
      if (departmentIdsWithEquipment.contains(id)) continue;
      final shared = sharedPhonesByDepartmentId[id] ?? const <String>[];
      if (shared.any((phone) => phone.trim().isNotEmpty)) continue;

      findings.add(
        CatalogValidationFinding(
          type: CatalogFindingType.fieldHint,
          fieldLabel: 'Εξαρτήματα',
          message:
              'Δεν έχει κανέναν υπάλληλο, κοινόχρηστο τηλέφωνο ή εξοπλισμό',
          records: [
            CatalogFindingRecord(
              kind: CatalogEntityKind.department,
              entityId: id,
              label: _departmentLabel(department),
              focusedField: 'name',
            ),
          ],
        ),
      );
    }
  }

  /// Τηλέφωνο (προσωπικό ή κοινόχρηστο) που ταυτίζεται με καταχωρημένο
  /// κωδικό εξοπλισμού — το ιστορικό λάθος «3685 ως τηλέφωνο».
  /// ΜΙΑ κάρτα ανά κωδικό, με όλους τους κατόχους του «τηλεφώνου»
  /// και τον εξοπλισμό μαζί.
  void _addPhoneEquipmentCodeFindings(
    List<CatalogValidationFinding> findings, {
    required List<UserModel> users,
    required List<DepartmentModel> departments,
    required List<EquipmentModel> equipment,
    required Map<int, List<String>> sharedPhonesByDepartmentId,
    required Map<int, String> departmentNameById,
    required Map<int, List<String>> equipmentCodesByUserId,
  }) {
    if (!rules.phoneEquipmentCodeEnabled) return;
    final equipmentByCode = <String, EquipmentModel>{};
    for (final e in equipment) {
      final code = (e.code ?? '').trim();
      if (code.isEmpty) continue;
      equipmentByCode.putIfAbsent(code, () => e);
    }
    if (equipmentByCode.isEmpty) return;

    // Συγκέντρωση ανά κωδικό: ποιοι κουβαλούν αυτό το «τηλέφωνο».
    final holdersByCode = <String, List<CatalogFindingRecord>>{};

    for (final user in users) {
      for (final phone in user.phones) {
        final p = phone.trim();
        if (!equipmentByCode.containsKey(p)) continue;
        holdersByCode
            .putIfAbsent(p, () => [])
            .add(
              _userRecord(
                user,
                focusedField: 'phone',
                departmentNameById: departmentNameById,
                equipmentCodesByUserId: equipmentCodesByUserId,
              ),
            );
      }
    }

    for (final department in departments) {
      final id = department.id;
      if (id == null) continue;
      for (final phone in sharedPhonesByDepartmentId[id] ?? const <String>[]) {
        final p = phone.trim();
        if (!equipmentByCode.containsKey(p)) continue;
        holdersByCode
            .putIfAbsent(p, () => [])
            .add(
              _departmentRecord(
                department,
                focusedField: 'phones',
                sharedPhones: sharedPhonesByDepartmentId[id] ?? const [],
              ),
            );
      }
    }

    final codes = holdersByCode.keys.toList()..sort();
    for (final code in codes) {
      final item = equipmentByCode[code]!;
      final records = [
        ..._markNewestUser(holdersByCode[code]!),
        _equipmentRecord(
          item,
          focusedField: 'code',
          departmentNameById: departmentNameById,
        ),
      ];
      findings.add(
        CatalogValidationFinding(
          type: CatalogFindingType.phoneEquipmentCode,
          message:
              'Το $code είναι καταχωρημένος κωδικός εξοπλισμού — '
              'ίσως γράφτηκε σε λάθος πεδίο',
          records: records,
        ),
      );
    }
  }

  /// Ίδιο ή αντεστραμμένο ονοματεπώνυμο — πιθανό ίδιο πρόσωπο.
  ///
  /// Οι δύο κανόνες (διπλότυπα, αντεστραμμένα) μοιράζονται την ίδια
  /// οικογένεια: ΜΙΑ κάρτα ανά όνομα, με ΟΛΕΣ τις εμπλεκόμενες εγγραφές —
  /// τρεις εγγραφές «Δρόσος Βασίλης»/«Βασίλης Δρόσος» είναι μία απόφαση,
  /// όχι τρεις χωριστές κάρτες.
  void _addNameConflictFindings(
    List<CatalogValidationFinding> findings, {
    required List<UserModel> users,
    required Map<int, String> departmentNameById,
    required Map<int, List<String>> equipmentCodesByUserId,
  }) {
    if (!rules.swappedNamesEnabled && !rules.duplicateNamesEnabled) return;

    String norm(String? s) => SearchTextNormalizer.normalizeForSearch(s ?? '');
    String orderedKey(UserModel u) =>
        '${norm(u.lastName)}|${norm(u.firstName)}';

    // Ομαδοποίηση με ΑΤΑΞΙΝΟΜΗΤΟ κλειδί, ώστε «Δρόσος Βασίλης» και
    // «Βασίλης Δρόσος» να πέφτουν στην ίδια ομάδα. Εγγραφές με ένα μόνο
    // μέρος ονόματος (εταιρείες) δεν έχουν έννοια αντιστροφής και
    // ομαδοποιούνται μόνο κατά ταυτόσημο κλειδί.
    final groups = <String, List<UserModel>>{};
    for (final user in users) {
      final last = norm(user.lastName);
      final first = norm(user.firstName);
      if (last.isEmpty && first.isEmpty) continue;
      final String key;
      if (last.isEmpty || first.isEmpty) {
        key = 'exact:$last|$first';
      } else {
        final parts = [last, first]..sort();
        key = 'pair:${parts.join('|')}';
      }
      groups.putIfAbsent(key, () => []).add(user);
    }

    for (final group in groups.values) {
      if (group.length < 2) continue;

      final byOrdered = <String, List<UserModel>>{};
      for (final user in group) {
        byOrdered.putIfAbsent(orderedKey(user), () => []).add(user);
      }
      final hasDuplicates = byOrdered.values.any((g) => g.length >= 2);
      final hasSwapped = byOrdered.length >= 2;

      // Ποιες εγγραφές αφορά η κάρτα, ανάλογα με τους ενεργούς κανόνες.
      final List<UserModel> included;
      if (rules.swappedNamesEnabled && hasSwapped) {
        // Η αντιστροφή εμπλέκει όλη την ομάδα — και τα πιστά διπλότυπα
        // μέσα της, γιατί συμμετέχουν στην ίδια απόφαση.
        included = group;
      } else if (rules.duplicateNamesEnabled && hasDuplicates) {
        included = [
          for (final sub in byOrdered.values)
            if (sub.length >= 2) ...sub,
        ];
      } else {
        continue;
      }
      if (included.length < 2) continue;

      included.sort((a, b) => a.id!.compareTo(b.id!));
      final includedOrderedKeys = included.map(orderedKey).toSet();
      final conflictHasSwapped = includedOrderedKeys.length >= 2;
      final conflictHasDuplicates =
          included.length > includedOrderedKeys.length;

      final String message;
      if (conflictHasSwapped && conflictHasDuplicates) {
        message =
            'Ίδιο ή αντεστραμμένο ονοματεπώνυμο σε ${included.length} '
            'εγγραφές — πιθανό ίδιο πρόσωπο';
      } else if (conflictHasSwapped) {
        message = 'Πιθανό ίδιο πρόσωπο με αντεστραμμένα πεδία';
      } else {
        message =
            'Ίδιο ονοματεπώνυμο σε ${included.length} εγγραφές — '
            'πιθανό διπλότυπο';
      }

      findings.add(
        CatalogValidationFinding(
          type: CatalogFindingType.nameConflict,
          message: message,
          records: _markNewestUser([
            for (final user in included)
              _userRecord(
                user,
                focusedField: 'lastName',
                departmentNameById: departmentNameById,
                equipmentCodesByUserId: equipmentCodesByUserId,
              ),
          ]),
        ),
      );
    }
  }

  /// Ίδιο τηλέφωνο σε υπαλλήλους ΔΙΑΦΟΡΕΤΙΚΩΝ τμημάτων — σχεδόν πάντα
  /// μπαγιάτικη εγγραφή μετά από μετακίνηση. Στο ίδιο τμήμα το κοινό
  /// τηλέφωνο βάρδιας είναι θεμιτό και δεν ελέγχεται. ΜΙΑ κάρτα ανά
  /// τηλέφωνο, με όλους τους κατόχους του.
  void _addCrossDepartmentPhoneFindings(
    List<CatalogValidationFinding> findings, {
    required List<UserModel> users,
    required Map<int, String> departmentNameById,
    required Map<int, List<String>> equipmentCodesByUserId,
  }) {
    if (!rules.crossDepartmentPhoneEnabled) return;

    final usersByPhone = <String, List<UserModel>>{};
    for (final user in users) {
      if (user.departmentId == null) continue;
      for (final phone in user.phones) {
        final p = phone.trim();
        if (p.isEmpty) continue;
        usersByPhone.putIfAbsent(p, () => []).add(user);
      }
    }

    final phones = usersByPhone.keys.toList()..sort();
    for (final phone in phones) {
      final holders = usersByPhone[phone]!;
      final departmentIds = holders.map((u) => u.departmentId).toSet();
      if (departmentIds.length < 2) continue;
      holders.sort((a, b) => a.id!.compareTo(b.id!));
      findings.add(
        CatalogValidationFinding(
          type: CatalogFindingType.crossDepartmentPhone,
          message:
              'Το $phone είναι καταχωρημένο σε ${holders.length} υπαλλήλους '
              'σε ${departmentIds.length} τμήματα',
          records: _markNewestUser([
            for (final user in holders)
              _userRecord(
                user,
                focusedField: 'phone',
                departmentNameById: departmentNameById,
                equipmentCodesByUserId: equipmentCodesByUserId,
              ),
          ]),
        ),
      );
    }
  }

  /// Εξοπλισμός χρεωμένος σε υπάλληλο άλλου τμήματος από αυτό στο οποίο
  /// ανήκει — κάποιο από τα δύο δεν ενημερώθηκε μετά από μετακίνηση.
  /// ΜΙΑ κάρτα ανά εξοπλισμό, με όλους τους ασύμφωνους κατόχους.
  void _addEquipmentOwnerDepartmentFindings(
    List<CatalogValidationFinding> findings, {
    required List<UserModel> users,
    required List<EquipmentModel> equipment,
    required Map<int, List<int>> ownerUserIdsByEquipmentId,
    required Map<int, String> departmentNameById,
    required Map<int, List<String>> equipmentCodesByUserId,
  }) {
    if (!rules.equipmentOwnerDepartmentEnabled) return;
    if (ownerUserIdsByEquipmentId.isEmpty) return;

    final usersById = <int, UserModel>{for (final u in users) u.id!: u};

    for (final item in equipment) {
      final equipmentDepartmentId = item.departmentId;
      if (equipmentDepartmentId == null) continue;

      final mismatched = <UserModel>[];
      for (final ownerId
          in ownerUserIdsByEquipmentId[item.id] ?? const <int>[]) {
        final owner = usersById[ownerId];
        if (owner == null || owner.departmentId == null) continue;
        if (owner.departmentId == equipmentDepartmentId) continue;
        mismatched.add(owner);
      }
      if (mismatched.isEmpty) continue;

      mismatched.sort((a, b) => a.id!.compareTo(b.id!));
      final equipmentDepartment =
          departmentNameById[equipmentDepartmentId] ??
          'Τμήμα #$equipmentDepartmentId';

      final String message;
      if (mismatched.length == 1) {
        final owner = mismatched.single;
        final ownerDepartment =
            departmentNameById[owner.departmentId] ??
            'Τμήμα #${owner.departmentId}';
        message =
            'Χρεωμένος στην εγγραφή «${_userLabel(owner)}» '
            '($ownerDepartment), ενώ ανήκει στο «$equipmentDepartment»';
      } else {
        message =
            'Χρεωμένος σε ${mismatched.length} υπαλλήλους άλλων τμημάτων, '
            'ενώ ανήκει στο «$equipmentDepartment»';
      }

      findings.add(
        CatalogValidationFinding(
          type: CatalogFindingType.equipmentOwnerDepartment,
          message: message,
          records: [
            _equipmentRecord(
              item,
              focusedField: 'department',
              departmentNameById: departmentNameById,
            ),
            for (final owner in mismatched)
              _userRecord(
                owner,
                focusedField: 'department',
                departmentNameById: departmentNameById,
                equipmentCodesByUserId: equipmentCodesByUserId,
              ),
          ],
        ),
      );
    }
  }

  // ---- Κατασκευή chips εγγραφών.

  CatalogFindingRecord _userRecord(
    UserModel user, {
    required String focusedField,
    required Map<int, String> departmentNameById,
    required Map<int, List<String>> equipmentCodesByUserId,
  }) {
    final details = <String>[
      departmentNameById[user.departmentId] ?? 'χωρίς τμήμα',
      user.phones.isEmpty ? 'χωρίς τηλέφωνο' : 'τηλ. ${user.phones.join(', ')}',
      switch (equipmentCodesByUserId[user.id] ?? const <String>[]) {
        [] => 'χωρίς εξοπλισμό',
        final codes => 'εξοπλ. ${codes.join(', ')}',
      },
    ];
    return CatalogFindingRecord(
      kind: CatalogEntityKind.user,
      entityId: user.id!,
      label: _userLabel(user),
      focusedField: focusedField,
      details: details.join(' · '),
    );
  }

  CatalogFindingRecord _departmentRecord(
    DepartmentModel department, {
    required String focusedField,
    required List<String> sharedPhones,
  }) {
    return CatalogFindingRecord(
      kind: CatalogEntityKind.department,
      entityId: department.id!,
      label: _departmentLabel(department),
      focusedField: focusedField,
      details: sharedPhones.isEmpty
          ? 'χωρίς κοινόχρηστα τηλέφωνα'
          : 'κοινόχρηστα τηλ. ${sharedPhones.join(', ')}',
    );
  }

  CatalogFindingRecord _equipmentRecord(
    EquipmentModel item, {
    required String focusedField,
    required Map<int, String> departmentNameById,
  }) {
    final type = (item.type ?? '').trim();
    final details = <String>[
      departmentNameById[item.departmentId] ?? 'χωρίς τμήμα',
      if (type.isNotEmpty) type,
    ];
    return CatalogFindingRecord(
      kind: CatalogEntityKind.equipment,
      entityId: item.id!,
      label: _equipmentLabel(item),
      focusedField: focusedField,
      details: details.join(' · '),
    );
  }

  /// Σημαδεύει ως «νεότερη» την εγγραφή-υπάλληλο με το μεγαλύτερο id,
  /// όταν οι υπάλληλοι της κάρτας είναι τουλάχιστον δύο — τα ids
  /// μεγαλώνουν με τη σειρά δημιουργίας, άρα η μεγαλύτερη είναι συνήθως
  /// το διπλότυπο. Σε μικτές κάρτες (χρήστης + εξοπλισμός) δεν έχει νόημα.
  List<CatalogFindingRecord> _markNewestUser(
    List<CatalogFindingRecord> records,
  ) {
    final userRecords = records
        .where((r) => r.kind == CatalogEntityKind.user)
        .toList();
    if (userRecords.length < 2) return records;
    final newestId = userRecords
        .map((r) => r.entityId)
        .reduce((a, b) => a > b ? a : b);
    return [
      for (final record in records)
        if (record.kind == CatalogEntityKind.user &&
            record.entityId == newestId)
          CatalogFindingRecord(
            kind: record.kind,
            entityId: record.entityId,
            label: record.label,
            focusedField: record.focusedField,
            details: record.details,
            isNewest: true,
          )
        else
          record,
    ];
  }

  static String _userLabel(UserModel user) {
    final parts = [
      (user.lastName ?? '').trim(),
      (user.firstName ?? '').trim(),
    ].where((p) => p.isNotEmpty);
    if (parts.isEmpty) return 'Υπάλληλος #${user.id}';
    return parts.join(' ');
  }

  static String _departmentLabel(DepartmentModel department) {
    final name = department.name.trim();
    return name.isEmpty ? 'Τμήμα #${department.id}' : name;
  }

  static String _equipmentLabel(EquipmentModel item) {
    final code = (item.code ?? '').trim();
    return code.isEmpty ? 'Εξοπλισμός #${item.id}' : code;
  }
}
