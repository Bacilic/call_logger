import 'package:characters/characters.dart';

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
  /// Οι διαγραμμένες εγγραφές αγνοούνται: δεν επεξεργάζονται από πουθενά.
  List<CatalogValidationFinding> scan({
    required List<UserModel> users,
    required List<DepartmentModel> departments,
    required List<EquipmentModel> equipment,
    Map<int, List<String>> sharedPhonesByDepartmentId = const {},
  }) {
    final findings = <CatalogValidationFinding>[];

    for (final user in users) {
      final id = user.id;
      if (id == null || user.isDeleted) continue;
      final label = _userLabel(user);

      final lastNameHint = personNameHint(user.lastName ?? '');
      if (lastNameHint != null) {
        findings.add(
          CatalogValidationFinding(
            kind: CatalogEntityKind.user,
            entityId: id,
            entityLabel: label,
            fieldLabel: 'Επώνυμο',
            message: lastNameHint,
            focusedField: 'lastName',
          ),
        );
      }

      final firstNameHint = personNameHint(user.firstName ?? '');
      if (firstNameHint != null) {
        findings.add(
          CatalogValidationFinding(
            kind: CatalogEntityKind.user,
            entityId: id,
            entityLabel: label,
            fieldLabel: 'Όνομα',
            message: firstNameHint,
            focusedField: 'firstName',
          ),
        );
      }

      // Ένα εύρημα ανά προβληματικό τηλέφωνο: ο υπάλληλος μπορεί να έχει
      // πολλά και ο χρήστης θέλει να ξέρει ποιο φταίει.
      for (final phone in user.phones) {
        final hint = phoneHint(phone);
        if (hint == null) continue;
        findings.add(
          CatalogValidationFinding(
            kind: CatalogEntityKind.user,
            entityId: id,
            entityLabel: label,
            fieldLabel: 'Τηλέφωνο',
            message: hint,
            focusedField: 'phone',
          ),
        );
      }
    }

    for (final department in departments) {
      final id = department.id;
      if (id == null) continue;
      final label = department.name.trim().isEmpty
          ? 'Τμήμα #$id'
          : department.name.trim();

      final nameHint = departmentNameHint(department.name);
      if (nameHint != null) {
        findings.add(
          CatalogValidationFinding(
            kind: CatalogEntityKind.department,
            entityId: id,
            entityLabel: label,
            fieldLabel: 'Όνομα',
            message: nameHint,
            focusedField: 'name',
          ),
        );
      }

      for (final phone in sharedPhonesByDepartmentId[id] ?? const <String>[]) {
        final hint = phoneHint(phone);
        if (hint == null) continue;
        findings.add(
          CatalogValidationFinding(
            kind: CatalogEntityKind.department,
            entityId: id,
            entityLabel: label,
            fieldLabel: 'Κοινόχρηστο τηλέφωνο',
            message: hint,
            focusedField: 'phones',
          ),
        );
      }
    }

    for (final item in equipment) {
      final id = item.id;
      if (id == null || item.isDeleted) continue;
      final hint = equipmentCodeHint(item.code ?? '');
      if (hint == null) continue;
      final code = (item.code ?? '').trim();
      findings.add(
        CatalogValidationFinding(
          kind: CatalogEntityKind.equipment,
          entityId: id,
          entityLabel: code.isEmpty ? 'Εξοπλισμός #$id' : code,
          fieldLabel: 'Κωδικός',
          message: hint,
          focusedField: 'code',
        ),
      );
    }

    return findings;
  }

  static String _userLabel(UserModel user) {
    final parts = [
      (user.lastName ?? '').trim(),
      (user.firstName ?? '').trim(),
    ].where((p) => p.isNotEmpty);
    if (parts.isEmpty) return 'Υπάλληλος #${user.id}';
    return parts.join(' ');
  }
}
