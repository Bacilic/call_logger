import 'package:characters/characters.dart';

import '../../../core/models/remote_tool.dart';
import '../../../core/models/remote_tool_role.dart';
import '../../../core/services/lansweeper_department_accounts.dart';
import '../../../core/services/lansweeper_identity_diagnosis.dart';
import '../../../core/utils/name_parser.dart';
import '../../../core/utils/search_text_normalizer.dart';
import '../../calls/models/equipment_model.dart';
import '../../calls/utils/equipment_remote_param_key.dart';
import '../../calls/models/user_model.dart';
import '../models/catalog_validation_finding.dart';
import '../models/catalog_validation_rules.dart';
import '../models/department_kind.dart';
import '../models/department_model.dart';

/// Πόσο ύποπτη είναι μια μεμονωμένη τιμή — η κλίμακα που χρωματίζει τα chips.
///
/// Δεν είναι «σωστό/λάθος»: όλα τα σχήματα αποθηκεύονται κανονικά. Είναι
/// **πόσο σπάνιο** είναι αυτό που βλέπεις, ώστε το μάτι να σταματά εκεί που
/// αξίζει.
enum CatalogChipSeverity {
  /// Συνηθισμένο — καμία ένδειξη.
  ok,

  /// Σπάνιο αλλά θεμιτό. Διακριτική ένδειξη, χωρίς δραματοποίηση.
  suspicious,

  /// Σχεδόν πάντα λάθος. Εδώ επιτρέπεται να τραβήξει το βλέμμα.
  wrong,
}

/// Η κρίση για ΕΝΑ chip: πόσο ύποπτο και γιατί.
class CatalogChipDiagnosis {
  const CatalogChipDiagnosis(this.severity, this.message);

  final CatalogChipSeverity severity;

  /// Το «γιατί», για το tooltip. Κενό όταν δεν υπάρχει παρατήρηση.
  final String message;

  static const CatalogChipDiagnosis ok = CatalogChipDiagnosis(
    CatalogChipSeverity.ok,
    '',
  );

  bool get hasRemark => severity != CatalogChipSeverity.ok;
}

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

  /// Το σχήμα που θεωρείται «λατινικός κωδικός»: γράμματα, ψηφία και τα τρία
  /// σημεία που μπαίνουν θεμιτά σε κωδικούς εξοπλισμού («SRV-01», «PC_2»).
  static final RegExp _latinCodeShape = RegExp(r'^[A-Za-z0-9._-]+$');
  static final RegExp _latinCodeChar = RegExp(r'[A-Za-z0-9._-]');
  static final RegExp _greekLetter = RegExp(r'[Ͱ-Ͽἀ-῿]');

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

  /// Η κρίση για κωδικό εξοπλισμού ως σκέτο κείμενο — η μορφή που θέλει η
  /// γραμμή υπόδειξης κάτω από το πεδίο πληκτρολόγησης.
  String? equipmentCodeFieldHint(String value) {
    final diagnosis = equipmentCodeChipDiagnosis(value);
    return diagnosis.hasRemark ? diagnosis.message : null;
  }

  /// Η κρίση για ένα τηλέφωνο, στη μορφή που χρωματίζει chip.
  ///
  /// Τα τηλέφωνα δεν έχουν βαθμίδες: ή τηρούν τους κανόνες ή όχι.
  CatalogChipDiagnosis phoneChipDiagnosis(String value) {
    final hint = phoneHint(value);
    return hint == null
        ? CatalogChipDiagnosis.ok
        : CatalogChipDiagnosis(CatalogChipSeverity.suspicious, hint);
  }

  /// Η κρίση για έναν κωδικό εξοπλισμού, σε **τρεις βαθμίδες**.
  ///
  /// Σκέτος αριθμός είναι ο κανόνας — εκεί μετράει μόνο το πλήθος ψηφίων.
  /// Λατινικά γράμματα («PC470») είναι σπάνια αλλά υπαρκτά, οπότε λένε
  /// «κοίτα το» και τίποτα παραπάνω. Ελληνικά ή σύμβολα είναι σχεδόν πάντα
  /// ξεχασμένο πληκτρολόγιο, και μόνο εκεί επιτρέπεται η έντονη ένδειξη.
  ///
  /// Κάθε βαθμίδα έχει τον δικό της διακόπτη: όταν σβήσει, η τιμή περνά ως
  /// συνηθισμένη αντί να υποβαθμιστεί σε ηπιότερη παρατήρηση.
  CatalogChipDiagnosis equipmentCodeChipDiagnosis(String value) {
    final s = value.trim();
    if (s.isEmpty) return CatalogChipDiagnosis.ok;

    if (_digitsOnly.hasMatch(s)) {
      final hint = equipmentCodeHint(s);
      return hint == null
          ? CatalogChipDiagnosis.ok
          : CatalogChipDiagnosis(CatalogChipSeverity.suspicious, hint);
    }

    if (!_latinCodeShape.hasMatch(s)) {
      if (!rules.equipmentForeignCodeEnabled) return CatalogChipDiagnosis.ok;
      final offenders = s.characters
          .where((c) => !_latinCodeChar.hasMatch(c))
          .toSet()
          .join(' ');
      final cause = _greekLetter.hasMatch(s)
          ? 'μάλλον ξεχασμένο ελληνικό πληκτρολόγιο'
          : 'σύμβολα δεν συνηθίζονται σε κωδικό';
      return CatalogChipDiagnosis(
        CatalogChipSeverity.wrong,
        'Το «$s» έχει χαρακτήρες εκτός λατινικών: $offenders — $cause',
      );
    }

    if (!rules.equipmentLatinCodeEnabled) return CatalogChipDiagnosis.ok;
    return CatalogChipDiagnosis(
      CatalogChipSeverity.suspicious,
      'Το «$s» έχει γράμματα — σπάνιο σχήμα κωδικού, οι περισσότεροι είναι '
      'σκέτοι αριθμοί',
    );
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

  /// Υπόδειξη για «Όνομα» που κουβαλά ψευδώνυμο σε παρένθεση.
  ///
  /// Γράφεται με τα δύο κομμάτια χωρισμένα, ώστε ο χρήστης να δει τι θα γίνει
  /// πριν ανοίξει την καρτέλα.
  String? nicknameInNameHint(String value) {
    if (!rules.nicknameInNameEnabled) return null;
    final split = NameParserUtility.splitNicknameFromName(value);
    if (split == null) return null;
    return 'Το «${split.nickname}» μοιάζει με ψευδώνυμο μέσα στο όνομα — '
        'με δικό του πεδίο, το όνομα μένει «${split.name}»';
    // Η υπόθεση «πρώτο = ψευδώνυμο» γράφεται ρητά στο μήνυμα: ο χρήστης
    // βλέπει τι θα μπει πού και ανταλλάσσει στην καρτέλα αν χρειάζεται.
  }

  /// Υπόδειξη για τηλέφωνο **εταιρείας** που έχει μορφή εσωτερικού.
  ///
  /// Τετραψήφιο με πρόθεμα του δικού μας τηλεφωνικού κέντρου μέσα στη DataMed
  /// σημαίνει σχεδόν πάντα ένα από τα δύο: λάθος Είδος (είναι τμήμα μας και
  /// δηλώθηκε εταιρεία) ή λάθος αριθμός (γράφτηκε το εσωτερικό του τεχνικού
  /// αντί για το τηλέφωνο της εταιρείας).
  ///
  /// Ζει ΜΟΝΟ στη φόρμα: στη σάρωση δεδομένων δεν μπαίνει, γιατί ο σκοπός
  /// είναι να πιαστεί τη στιγμή της πληκτρολόγησης, όχι να γεμίσει λίστα.
  /// Καλείται μόνο όταν το Είδος είναι «Εταιρεία» — την απόφαση αυτή την
  /// παίρνει η φόρμα, που ξέρει τι έχει επιλεγμένο εκείνη τη στιγμή.
  String? companyInternalPhoneHint(String value) {
    if (!rules.companyInternalPhoneEnabled) return null;
    final v = value.trim();
    if (v.isEmpty || !_digitsOnly.hasMatch(v)) return null;
    if (v.length != rules.internalPhoneDigits) return null;

    // Χωρίς κανόνα προθέματος κάθε τετραψήφιο θα ήταν ύποπτο — και τα
    // τετραψήφια των εταιρειών είναι θεμιτά αν δεν μοιάζουν με δικά μας.
    if (!rules.internalPrefixEnabled) return null;
    final prefix = int.tryParse(v.substring(0, 2));
    if (prefix == null) return null;
    if (prefix < rules.internalPrefixFrom || prefix > rules.internalPrefixTo) {
      return null;
    }
    return 'Το $v έχει μορφή δικού μας εσωτερικού — οι εταιρείες '
        'δεν έχουν εσωτερικά του νοσοκομείου';
  }

  /// Υπόδειξη για το αναγνωριστικό Lansweeper ενός υπαλλήλου — το ΣΤΟΧΕΥΜΕΝΟ
  /// μήνυμα της διάγνωσης ([diagnoseLansweeperIdentity]), ίδιο με τη φόρμα.
  /// Κενή τιμή = «χωρίς αναγνωριστικό», απολύτως θεμιτό.
  String? lansweeperUserIdentifierHint(String value) {
    if (!rules.lansweeperIdentifierEnabled) return null;
    final s = value.trim();
    if (s.isEmpty) return null;
    final diagnosis = diagnoseLansweeperIdentity(s);
    if (diagnosis.isValid) return null;
    return _composeDiagnosisMessage('«$s»', diagnosis);
  }

  /// Ένα μήνυμα ΑΝΑ προβληματικό λογαριασμό τμήματος — όχι συγκεντρωτικό:
  /// κάθε λάθος αναφέρεται χωριστά, με τη δική του διάγνωση.
  List<String> lansweeperDepartmentAccountProblems(String? stored) {
    if (!rules.lansweeperIdentifierEnabled) return const [];
    final raw = (stored ?? '').trim();
    if (raw.isEmpty) return const [];
    final out = <String>[];
    for (final account in decodeLansweeperAccounts(raw)) {
      final diagnosis = diagnoseLansweeperIdentity(account.username);
      if (diagnosis.isValid) continue;
      out.add(_composeDiagnosisMessage('«${account.username}»', diagnosis));
    }
    return out;
  }

  /// Ήπιες υποψίες τομέα (πορτοκαλί): ΕΓΚΥΡΕΣ ταυτότητες με τομέα
  /// διαφορετικό από τον [referenceDomain]. Χωρίς μέτρο σύγκρισης η λίστα
  /// μένει κενή.
  List<String> lansweeperDomainMismatchProblems(
    String? stored,
    String? referenceDomain,
  ) {
    if (!rules.lansweeperIdentifierEnabled) return const [];
    final raw = (stored ?? '').trim();
    if (raw.isEmpty) return const [];
    final out = <String>[];
    for (final account in decodeLansweeperAccounts(raw)) {
      final hint = lansweeperDomainMismatchHint(
        account.username,
        referenceDomain,
      );
      if (hint != null) out.add('«${account.username}»: $hint');
    }
    return out;
  }

  static String _composeDiagnosisMessage(
    String subject,
    LansweeperIdentityDiagnosis diagnosis,
  ) {
    final suggestion = diagnosis.suggestion;
    return suggestion == null
        ? '$subject: ${diagnosis.problem}'
        : '$subject: ${diagnosis.problem} — $suggestion';
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

    /// Ταυτότητα πράκτορα (Ρυθμίσεις API) για τις ήπιες υποψίες τομέα.
    ///
    /// Προεπιλογή «διαβάστηκε και δεν έχει οριστεί»: οι καλούντες που δεν
    /// ασχολούνται με τον πράκτορα παίρνουν τη σημερινή συμπεριφορά, ενώ
    /// όποιος τον διαβάζει οφείλει να πει και αν τα κατάφερε.
    LansweeperAgentIdentity lansweeperAgentIdentity =
        const LansweeperAgentIdentity.read(null),

    /// Τα ενεργά εργαλεία απομακρυσμένης σύνδεσης, για τον κανόνα του διπλού
    /// στόχου. Χωρίς αυτά ο κανόνας σιωπά: δεν ξέρουμε ποιο id είναι ποιος
    /// ρόλος, άρα δεν μπορούμε να εξαιρέσουμε την επιφάνεια των Windows.
    List<RemoteTool> remoteTools = const [],
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

    // Μέτρο σύγκρισης τομέα: του πράκτορα αν είναι «τομέας\όνομα», αλλιώς ο
    // πλειοψηφικός τομέας των αναγνωριστικών που ήδη σαρώνονται.
    final referenceDomain = lansweeperReferenceDomain(
      agent: lansweeperAgentIdentity,
      knownIdentities: [
        for (final user in activeUsers) user.lansweeperUsername ?? '',
        for (final department in departments)
          ...decodeLansweeperAccounts(
            department.lansweeperUsernames,
          ).map((account) => account.username),
      ],
    );

    _addFieldHintFindings(
      findings,
      users: activeUsers,
      departments: departments,
      equipment: activeEquipment,
      sharedPhonesByDepartmentId: sharedPhonesByDepartmentId,
      lansweeperReferenceDomain: referenceDomain,
    );
    _addEmptyDepartmentFindings(
      findings,
      users: activeUsers,
      departments: departments,
      equipment: activeEquipment,
      sharedPhonesByDepartmentId: sharedPhonesByDepartmentId,
    );
    _addDepartmentBuildingFindings(findings, departments: departments);
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
      departments: departments,
      sharedPhonesByDepartmentId: sharedPhonesByDepartmentId,
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
    _addEquipmentInCompanyFindings(
      findings,
      users: activeUsers,
      departments: departments,
      equipment: activeEquipment,
      ownerUserIdsByEquipmentId: ownerUserIdsByEquipmentId,
      departmentNameById: departmentNameById,
      equipmentCodesByUserId: equipmentCodesByUserId,
    );
    _addEquipmentWithoutDepartmentFindings(
      findings,
      users: activeUsers,
      equipment: activeEquipment,
      ownerUserIdsByEquipmentId: ownerUserIdsByEquipmentId,
      departmentNameById: departmentNameById,
    );
    _addDuplicateRemoteTargetFindings(
      findings,
      equipment: activeEquipment,
      departmentNameById: departmentNameById,
      remoteTools: remoteTools,
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
    String? lansweeperReferenceDomain,
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

      // Το ψευδώνυμο σε παρένθεση: ξεχωριστό εύρημα, με εστίαση στο νέο πεδίο.
      // Ελέγχεται μόνο όσο το πεδίο είναι ΚΕΝΟ — αλλιώς η μεταφορά έχει ήδη
      // γίνει και η παρένθεση που έμεινε σημαίνει κάτι άλλο.
      if ((user.nickname ?? '').trim().isEmpty) {
        final nicknameHint = nicknameInNameHint(user.firstName ?? '');
        if (nicknameHint != null) {
          add(
            kind: CatalogEntityKind.user,
            entityId: user.id!,
            label: label,
            fieldLabel: 'Ψευδώνυμο',
            message: nicknameHint,
            focusedField: 'nickname',
          );
        }
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

      final lansweeperHint = lansweeperUserIdentifierHint(
        user.lansweeperUsername ?? '',
      );
      if (lansweeperHint != null) {
        add(
          kind: CatalogEntityKind.user,
          entityId: user.id!,
          label: label,
          fieldLabel: 'Αναγνωριστικό Lansweeper',
          message: lansweeperHint,
          focusedField: 'lansweeperUsername',
        );
      } else if (rules.lansweeperIdentifierEnabled) {
        // Έγκυρο μεν, με ύποπτο τομέα δε — ήπια υποψία, όχι λάθος.
        final mismatch = lansweeperDomainMismatchHint(
          user.lansweeperUsername ?? '',
          lansweeperReferenceDomain,
        );
        if (mismatch != null) {
          add(
            kind: CatalogEntityKind.user,
            entityId: user.id!,
            label: label,
            fieldLabel: 'Αναγνωριστικό Lansweeper',
            message: mismatch,
            focusedField: 'lansweeperUsername',
          );
        }
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

      // Ένα εύρημα ΑΝΑ προβληματικό λογαριασμό — κάθε λάθος χωριστά.
      for (final problem in lansweeperDepartmentAccountProblems(
        department.lansweeperUsernames,
      )) {
        add(
          kind: CatalogEntityKind.department,
          entityId: id,
          label: label,
          fieldLabel: 'Αναγνωριστικά Lansweeper',
          message: problem,
          focusedField: 'lansweeperUsernames',
        );
      }
      for (final mismatch in lansweeperDomainMismatchProblems(
        department.lansweeperUsernames,
        lansweeperReferenceDomain,
      )) {
        add(
          kind: CatalogEntityKind.department,
          entityId: id,
          label: label,
          fieldLabel: 'Αναγνωριστικά Lansweeper',
          message: mismatch,
          focusedField: 'lansweeperUsernames',
        );
      }
    }

    for (final item in equipment) {
      // Η ΙΔΙΑ κρίση με τα chips των φορμών: ένας κωδικός δεν επιτρέπεται να
      // περνά καθαρός στη μια οθόνη και να κοκκινίζει στην άλλη.
      final diagnosis = equipmentCodeChipDiagnosis(item.code ?? '');
      if (!diagnosis.hasRemark) continue;
      add(
        kind: CatalogEntityKind.equipment,
        entityId: item.id!,
        label: _equipmentLabel(item),
        fieldLabel: 'Κωδικός',
        message: diagnosis.message,
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

  /// Τμήματα χωρίς κτίριο.
  ///
  /// Το κτίριο δεν πληκτρολογείται πια — διαλέγεται από κοινό κατάλογο, και η
  /// φόρμα δεν προσφέρει «κανένα». Άρα ένα κενό κτίριο σημαίνει ότι κάποια
  /// απόφαση έμεινε στη μέση: σβήστηκε το κτίριο από τη λίστα, ή η μεταφορά
  /// από τη Λάμπα το άφησε για αργότερα. Εδώ μαζεύονται όλα μαζί, με
  /// μετάβαση στην καρτέλα του καθενός.
  void _addDepartmentBuildingFindings(
    List<CatalogValidationFinding> findings, {
    required List<DepartmentModel> departments,
  }) {
    if (!rules.departmentBuildingEnabled) return;

    for (final department in departments) {
      final id = department.id;
      if (id == null) continue;
      // Το κτίριο είναι κτίριο **του νοσοκομείου**. Η DataMed και το Κέντρο
      // Υγείας δεν έχουν θέση στον κατάλογο κτιρίων, οπότε το κενό πεδίο εκεί
      // είναι η σωστή κατάσταση και όχι εύρημα.
      if (!department.kind.expectsHospitalBuilding) continue;
      if ((department.building ?? '').trim().isNotEmpty) continue;

      findings.add(
        CatalogValidationFinding(
          type: CatalogFindingType.fieldHint,
          fieldLabel: 'Κτίριο',
          message: 'Δεν έχει κτίριο',
          records: [
            CatalogFindingRecord(
              kind: CatalogEntityKind.department,
              entityId: id,
              label: _departmentLabel(department),
              focusedField: 'building',
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

  /// Ίδιο τηλέφωνο σε ΔΙΑΦΟΡΕΤΙΚΑ τμήματα — σχεδόν πάντα μπαγιάτικη εγγραφή
  /// μετά από μετακίνηση, και η αναγνώριση του καλούντα γίνεται διφορούμενη.
  ///
  /// Μετρούν και οι δύο μορφές κατοχής: το **προσωπικό** τηλέφωνο του
  /// υπαλλήλου και το **κοινόχρηστο** του τμήματος. Το ίδιο σενάριο
  /// μετακίνησης αφήνει το ίδιο ίχνος και στα δύο, οπότε ένας κανόνας που
  /// έβλεπε μόνο τα προσωπικά έχανε τη μισή εικόνα.
  ///
  /// Μέσα στο ΙΔΙΟ τμήμα τίποτα δεν ελέγχεται: το κοινό τηλέφωνο βάρδιας
  /// είναι θεμιτό, και το κοινόχρηστο που είναι ταυτόχρονα προσωπικό κάποιου
  /// του τμήματος είναι πλεονασμός, όχι λάθος.
  ///
  /// ΜΙΑ κάρτα ανά τηλέφωνο, με όλες τις εμπλεκόμενες εγγραφές μαζί.
  void _addCrossDepartmentPhoneFindings(
    List<CatalogValidationFinding> findings, {
    required List<UserModel> users,
    required List<DepartmentModel> departments,
    required Map<int, List<String>> sharedPhonesByDepartmentId,
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

    final departmentsByPhone = <String, List<DepartmentModel>>{};
    for (final department in departments) {
      final id = department.id;
      if (id == null) continue;
      for (final phone
          in sharedPhonesByDepartmentId[id] ?? const <String>[]) {
        final p = phone.trim();
        if (p.isEmpty) continue;
        departmentsByPhone.putIfAbsent(p, () => []).add(department);
      }
    }

    final phones = <String>{...usersByPhone.keys, ...departmentsByPhone.keys}
        .toList()
      ..sort();
    for (final phone in phones) {
      final holders = usersByPhone[phone] ?? const <UserModel>[];
      final owningDepartments =
          departmentsByPhone[phone] ?? const <DepartmentModel>[];

      final departmentIds = <int>{
        for (final user in holders) user.departmentId!,
        for (final department in owningDepartments) department.id!,
      };
      if (departmentIds.length < 2) continue;

      final sortedHolders = [...holders]..sort((a, b) => a.id!.compareTo(b.id!));
      final sortedDepartments = [...owningDepartments]
        ..sort((a, b) => a.id!.compareTo(b.id!));

      // Όταν εμπλέκονται και κοινόχρηστα, η λέξη «υπαλλήλους» θα έλεγε ψέματα:
      // κάποιες από τις εγγραφές είναι τμήματα.
      final total = sortedHolders.length + sortedDepartments.length;
      final what = sortedDepartments.isEmpty ? 'υπαλλήλους' : 'εγγραφές';
      findings.add(
        CatalogValidationFinding(
          type: CatalogFindingType.crossDepartmentPhone,
          message:
              'Το $phone είναι καταχωρημένο σε $total $what '
              'σε ${departmentIds.length} τμήματα',
          records: _markNewestUser([
            for (final user in sortedHolders)
              _userRecord(
                user,
                focusedField: 'phone',
                departmentNameById: departmentNameById,
                equipmentCodesByUserId: equipmentCodesByUserId,
              ),
            for (final department in sortedDepartments)
              _departmentRecord(
                department,
                focusedField: 'phones',
                sharedPhones:
                    sharedPhonesByDepartmentId[department.id!] ??
                    const <String>[],
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

  /// Εξοπλισμός που κατέληξε σε **εταιρεία**.
  ///
  /// Δύο μονοπάτια οδηγούν εκεί, και τα δύο σιωπηλά: το τμήμα του μηχανήματος
  /// είναι εταιρεία, ή ο κάτοχός του ανήκει σε εταιρεία. Και τα δύο μπαίνουν
  /// στην ΙΔΙΑ κάρτα — για τον χρήστη είναι μία απόφαση: «σε ποιον ανήκει
  /// τελικά αυτό το μηχάνημα;».
  ///
  /// Η εξωτερική μονάδα ΔΕΝ ελέγχεται: στα Κέντρα Υγείας τα μηχανήματα είναι
  /// δικά μας, με δικούς μας κωδικούς και δική μας απομακρυσμένη σύνδεση.
  void _addEquipmentInCompanyFindings(
    List<CatalogValidationFinding> findings, {
    required List<UserModel> users,
    required List<DepartmentModel> departments,
    required List<EquipmentModel> equipment,
    required Map<int, List<int>> ownerUserIdsByEquipmentId,
    required Map<int, String> departmentNameById,
    required Map<int, List<String>> equipmentCodesByUserId,
  }) {
    if (!rules.equipmentInCompanyEnabled) return;

    final companyById = <int, DepartmentModel>{
      for (final d in departments)
        if (d.id != null && d.kind == DepartmentKind.company) d.id!: d,
    };
    if (companyById.isEmpty) return;

    final usersById = <int, UserModel>{for (final u in users) u.id!: u};

    for (final item in equipment) {
      final ownDepartment = companyById[item.departmentId];

      final companyOwners = <UserModel>[];
      for (final ownerId
          in ownerUserIdsByEquipmentId[item.id] ?? const <int>[]) {
        final owner = usersById[ownerId];
        if (owner == null) continue;
        if (!companyById.containsKey(owner.departmentId)) continue;
        companyOwners.add(owner);
      }

      if (ownDepartment == null && companyOwners.isEmpty) continue;
      companyOwners.sort((a, b) => a.id!.compareTo(b.id!));

      final String message;
      if (ownDepartment != null && companyOwners.isNotEmpty) {
        final people = companyOwners.length == 1 ? 'πρόσωπο' : 'πρόσωπα';
        message =
            'Ανήκει στην εταιρεία «${_departmentLabel(ownDepartment)}» και '
            'είναι χρεωμένος σε ${companyOwners.length} $people εταιρείας';
      } else if (ownDepartment != null) {
        message =
            'Ανήκει στην εταιρεία «${_departmentLabel(ownDepartment)}» — '
            'ο κατάλογος εξοπλισμού είναι του νοσοκομείου';
      } else if (companyOwners.length == 1) {
        final owner = companyOwners.single;
        final company = departmentNameById[owner.departmentId] ?? 'εταιρεία';
        message =
            'Χρεωμένος στην εγγραφή «${_userLabel(owner)}» της εταιρείας '
            '«$company» — τα δικά μας μηχανήματα δεν χρεώνονται σε εταιρείες';
      } else {
        message =
            'Χρεωμένος σε ${companyOwners.length} πρόσωπα εταιρειών — '
            'τα δικά μας μηχανήματα δεν χρεώνονται σε εταιρείες';
      }

      findings.add(
        CatalogValidationFinding(
          type: CatalogFindingType.equipmentInCompany,
          message: message,
          records: [
            _equipmentRecord(
              item,
              focusedField: 'department',
              departmentNameById: departmentNameById,
            ),
            if (ownDepartment != null)
              CatalogFindingRecord(
                kind: CatalogEntityKind.department,
                entityId: ownDepartment.id!,
                label: _departmentLabel(ownDepartment),
                focusedField: 'name',
                details: DepartmentKind.company.label,
              ),
            for (final owner in companyOwners)
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

  /// Εξοπλισμός χωρίς τμήμα.
  ///
  /// Οι φόρμες απαιτούν τμήμα, όμως μια διαγραμμένη καρτέλα τμήματος αφήνει
  /// πίσω της ακέφαλα μηχανήματα: η βάση μηδενίζει τη στήλη αντί να τα σβήσει.
  /// Ένα εύρημα ανά μηχάνημα — το καθένα θέλει τη δική του απόφαση.
  ///
  /// Ορφανό είναι το μηχάνημα που δεν ανήκει ΠΟΥΘΕΝΑ: ούτε άμεσα σε τμήμα,
  /// ούτε έμμεσα μέσω κατόχου. Η κενή στήλη τμήματος από μόνη της δεν αρκεί —
  /// δεκάδες μηχανήματα είναι χρεωμένα σε υπάλληλο που έχει τμήμα, και για
  /// αυτά ο κανόνας σιωπά.
  void _addEquipmentWithoutDepartmentFindings(
    List<CatalogValidationFinding> findings, {
    required List<UserModel> users,
    required List<EquipmentModel> equipment,
    required Map<int, List<int>> ownerUserIdsByEquipmentId,
    required Map<int, String> departmentNameById,
  }) {
    if (!rules.equipmentWithoutDepartmentEnabled) return;

    final departmentIdByUserId = <int, int?>{
      for (final u in users) u.id!: u.departmentId,
    };

    for (final item in equipment) {
      if (item.departmentId != null) continue;
      final belongsThroughOwner =
          (ownerUserIdsByEquipmentId[item.id] ?? const <int>[]).any(
            (ownerId) => departmentIdByUserId[ownerId] != null,
          );
      if (belongsThroughOwner) continue;
      findings.add(
        CatalogValidationFinding(
          type: CatalogFindingType.fieldHint,
          fieldLabel: 'Τμήμα',
          message: 'Δεν ανήκει σε κανένα τμήμα',
          records: [
            _equipmentRecord(
              item,
              focusedField: 'department',
              departmentNameById: departmentNameById,
            ),
          ],
        ),
      );
    }
  }

  /// Ίδιος στόχος απομακρυσμένης σύνδεσης σε δύο ή περισσότερα μηχανήματα.
  ///
  /// Το ίδιο αναγνωριστικό AnyDesk ή η ίδια διεύθυνση VNC σε δύο κωδικούς
  /// σημαίνει σχεδόν πάντα μπαγιάτικη εγγραφή μετά από αντικατάσταση — και
  /// τότε ο συνάδελφος συνδέεται σε **ξένο** υπολογιστή νομίζοντας ότι πάει
  /// στον σωστό.
  ///
  /// Η απομακρυσμένη επιφάνεια των Windows εξαιρείται ρητά: εκεί η κοινή τιμή
  /// είναι θεμιτή και συνηθισμένη.
  ///
  /// ΜΙΑ κάρτα ανά διπλή τιμή, με όλα τα μηχανήματα που τη μοιράζονται.
  void _addDuplicateRemoteTargetFindings(
    List<CatalogValidationFinding> findings, {
    required List<EquipmentModel> equipment,
    required Map<int, String> departmentNameById,
    required List<RemoteTool> remoteTools,
  }) {
    if (!rules.duplicateRemoteTargetEnabled) return;
    if (remoteTools.isEmpty) return;

    // Μόνο εργαλεία που ξέρουμε: για άγνωστο id δεν ξέρουμε ρόλο, άρα δεν
    // μπορούμε να πούμε αν η κοινή τιμή είναι θεμιτή.
    final judgedTools = <int, RemoteTool>{
      for (final tool in remoteTools)
        if (tool.role != ToolRole.rdp) tool.id: tool,
    };
    if (judgedTools.isEmpty) return;

    // Κλειδί: id εργαλείου + κανονικοποιημένη τιμή. Οι διευθύνσεις δεν
    // ξεχωρίζουν από πεζά/κεφαλαία, τα αναγνωριστικά AnyDesk είναι αριθμοί.
    final itemsByTarget = <String, List<EquipmentModel>>{};
    for (final item in equipment) {
      for (final entry in item.remoteParams.entries) {
        if (EquipmentRemoteParamKey.isReservedKey(entry.key)) continue;
        final toolId = int.tryParse(entry.key);
        if (toolId == null || !judgedTools.containsKey(toolId)) continue;
        final value = entry.value.trim();
        if (value.isEmpty) continue;
        itemsByTarget
            .putIfAbsent('$toolId|${value.toLowerCase()}', () => [])
            .add(item);
      }
    }

    final keys = itemsByTarget.keys.toList()..sort();
    for (final key in keys) {
      final items = itemsByTarget[key]!;
      if (items.length < 2) continue;
      items.sort((a, b) => a.id!.compareTo(b.id!));

      final toolId = int.parse(key.split('|').first);
      final tool = judgedTools[toolId]!;
      // Η τιμή γράφεται όπως την πληκτρολόγησε ο χρήστης στο πρώτο μηχάνημα,
      // όχι κανονικοποιημένη — αλλιώς δεν την αναγνωρίζει στην καρτέλα.
      final shown = (items.first.remoteParams['$toolId'] ?? '').trim();

      findings.add(
        CatalogValidationFinding(
          type: CatalogFindingType.duplicateRemoteTarget,
          message:
              'Το «${tool.name}» δείχνει την ίδια τιμή «$shown» σε '
              '${items.length} μηχανήματα',
          records: [
            for (final item in items)
              _equipmentRecord(
                item,
                focusedField: 'code',
                departmentNameById: departmentNameById,
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
