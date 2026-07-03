import 'package:flutter/material.dart';

import '../../../core/services/lookup_service.dart';
import '../../../core/utils/phone_list_parser.dart';
import '../../../core/utils/search_text_normalizer.dart';
import '../models/equipment_model.dart';
import '../models/user_model.dart';
import '../utils/remote_target_rules.dart';
import '../utils/vnc_remote_target.dart';

/// Τα τέσσερα πεδία του έξυπνου επιλογέα (v2 §Α).
enum SelectorField { phone, caller, department, equipment }

/// Σοβαρότητα δείκτη σύγκρουσης (v2 §Α.3 / §Α.6 / §Α.7).
/// - [mismatch] = κόκκινο: η βάση γνωρίζει διαφορετική τιμή.
/// - [unknown]  = κίτρινο: το πεδίο δεν αντιστοιχεί σε γνωστή οντότητα.
enum ConflictSeverity { mismatch, unknown }

/// Μία καταχώρηση σύγκρουσης πάνω σε ένα πεδίο (v2 §Α.7).
class FieldConflict {
  const FieldConflict({required this.severity, required this.message});

  final ConflictSeverity severity;
  final String message;
}

/// Κατάσταση έξυπνου επιλογέα οντοτήτων (τηλέφωνο, καλών, εξοπλισμός, τμήμα).
/// FocusNodes ΔΕΝ αποθηκεύονται εδώ — ζουν στο widget State.
class SmartEntitySelectorState {
  SmartEntitySelectorState({
    this.selectedPhone,
    this.selectedCaller,
    this.selectedEquipment,
    this.phoneError,
    List<String>? recentPhones,
    List<String>? phoneCandidates,
    List<UserModel>? callerCandidates,
    List<EquipmentModel>? equipmentCandidates,
    this.isPhoneAmbiguous = false,
    this.isEquipmentAmbiguous = false,
    this.callerNoMatch = false,
    this.equipmentNoMatch = false,
    this.hasAnyContent = false,
    this.equipmentText = '',
    this.callerDisplayText = '',
    this.departmentText = '',
    this.selectedDepartmentId,
    Map<SelectorField, List<FieldConflict>>? conflicts,
  }) : recentPhones = recentPhones ?? [],
       phoneCandidates = phoneCandidates ?? [],
       callerCandidates = callerCandidates ?? [],
       equipmentCandidates = equipmentCandidates ?? [],
       conflicts = conflicts ?? const {};

  final String? selectedPhone;

  /// Alias για persist (π.χ. `Task.phoneText`) — τιμή πεδίου τηλεφώνου.
  String? get phoneText => selectedPhone;

  final UserModel? selectedCaller;
  final EquipmentModel? selectedEquipment;
  final String? phoneError;
  final List<String> recentPhones;
  final List<String> phoneCandidates;
  final List<UserModel> callerCandidates;
  final List<EquipmentModel> equipmentCandidates;
  final bool isPhoneAmbiguous;
  final bool isEquipmentAmbiguous;

  /// True όταν έγινε phone lookup και βρέθηκαν 0 χρήστες (υπόδειξη "Καμία αντιστοιχία").
  final bool callerNoMatch;

  /// True όταν έγινε equipment lookup και βρέθηκαν 0 (υπόδειξη "Καμία αντιστοιχία").
  final bool equipmentNoMatch;

  /// Ενημερώνεται μετά από Enter ή focus out· χρησιμοποιείται για εμφάνιση κουμπιού "Καθαρισμός όλων".
  final bool hasAnyContent;

  /// Το κείμενο που έχει πληκτρολογήσει ο χρήστης στο πεδίο Κωδικός Εξοπλισμού (ανεξάρτητα από το αν το επέλεξε).
  final String equipmentText;

  /// Κείμενο εμφάνισης καλούντα (όνομα ή "Άγνωστος").
  final String callerDisplayText;

  /// Κείμενο πεδίου Τμήμα (από επιλογή ή ελεύθερο πληκτρολόγηση).
  final String departmentText;

  /// Επιλεγμένο τμήμα (department_id) όταν υπάρχει σαφής αντιστοίχιση.
  final int? selectedDepartmentId;

  /// Ενεργές συγκρούσεις ανά πεδίο (v2 §Α.7). Επανυπολογίζεται εξ αρχής σε κάθε
  /// ολοκληρωμένο lookup (§Α.4, stateless). Το πεδίο-πηγή δεν περιέχεται ποτέ.
  final Map<SelectorField, List<FieldConflict>> conflicts;

  /// Λίστα συγκρούσεων για ένα πεδίο (κενή αν δεν υπάρχουν).
  List<FieldConflict> conflictsFor(SelectorField field) =>
      conflicts[field] ?? const [];

  /// Σοβαρότητα προς εμφάνιση: κόκκινο αν υπάρχει έστω μία [ConflictSeverity.mismatch],
  /// αλλιώς κίτρινο αν όλες είναι [ConflictSeverity.unknown] (v2 §Α.7).
  ConflictSeverity? conflictSeverityFor(SelectorField field) {
    final list = conflictsFor(field);
    if (list.isEmpty) return null;
    return list.any((c) => c.severity == ConflictSeverity.mismatch)
        ? ConflictSeverity.mismatch
        : ConflictSeverity.unknown;
  }

  /// Tooltip με όλες τις γραμμές σύγκρουσης για ένα πεδίο (v2 §Α.7).
  String? conflictTooltipFor(SelectorField field) {
    final list = conflictsFor(field);
    if (list.isEmpty) return null;
    return list.map((c) => c.message).join('\n');
  }

  String get normalizedCallerDisplayText => callerDisplayText.trim();

  bool get isUnknownCaller => normalizedCallerDisplayText == 'Άγνωστος';

  bool get hasExplicitCallerText =>
      normalizedCallerDisplayText.isNotEmpty && !isUnknownCaller;

  bool get hasPhoneInput => selectedPhone?.trim().isNotEmpty == true;

  bool get hasEquipmentInput => equipmentText.trim().isNotEmpty;

  /// Στόχος AnyDesk: μόνο από regex στο ελεύθερο κείμενο εξοπλισμού (χωρίς κατάλογο εργαλείων εδώ).
  String? get resolvedAnyDeskTarget =>
      RemoteTargetRules.parseAnyDeskFromFreeText(equipmentText);

  bool get canConnectAnyDesk => resolvedAnyDeskTarget != null;

  /// Στόχος VNC από ελεύθερο κείμενο· με επιλεγμένο εξοπλισμό χρησιμοποιήστε [CallRemoteTargets].
  String get resolvedVncTarget =>
      VncRemoteTarget.hostForUnknownEquipmentText(equipmentText);

  bool get canConnectVnc => equipmentText.trim().isNotEmpty;

  String get anydeskTargetDisplay => resolvedAnyDeskTarget ?? '—';

  bool get hasPhoneAssociation {
    final callerPhone = selectedCaller?.phoneJoined ?? '';
    final selPhone = selectedPhone?.trim() ?? '';
    if (selPhone.isEmpty) return false;
    return PhoneListParser.containsPhone(callerPhone, selPhone);
  }

  /// [lookup]: για έλεγχο M2M (`user_equipment`) όταν υπάρχει επιλεγμένος εξοπλισμός με id.
  bool hasEquipmentAssociation(LookupService? lookup) {
    if (selectedCaller == null) return false;
    final text = equipmentText.trim();
    if (text.isEmpty) return false;
    final callerId = selectedCaller!.id;
    if (lookup != null && selectedEquipment?.id != null && callerId != null) {
      final owners = lookup.findUsersForEquipment(selectedEquipment!.id!);
      if (owners.any((u) => u.id == callerId)) return true;
    }

    return equipmentCandidates.any(
      (e) => e.code?.trim() == text || e.displayLabel == text,
    );
  }

  /// True όταν υπάρχει ήδη γνωστός χρήστης και τουλάχιστον ένα από Τηλέφωνο/Εξοπλισμό έχει τιμή και δεν είναι συσχετισμένο.
  bool needsExistingCallerAssociation(LookupService? lookup) {
    if (selectedCaller == null) return false;
    final phoneFilled = selectedPhone?.trim().isNotEmpty == true;
    final equipmentFilled = equipmentText.trim().isNotEmpty;
    if (!phoneFilled && !equipmentFilled) return false;

    final needsPhone = phoneFilled && !hasPhoneAssociation;
    final needsEquipment = equipmentFilled && !hasEquipmentAssociation(lookup);

    return needsPhone || needsEquipment;
  }

  /// True όταν δεν υπάρχει επιλεγμένος χρήστης από τη βάση, υπάρχει ρητό όνομα καλούντα
  /// και υπάρχει τουλάχιστον ένα στοιχείο προς καταχώρηση (τηλέφωνο ή εξοπλισμός ή τμήμα).
  bool get needsNewCallerCreation =>
      selectedCaller == null &&
      hasExplicitCallerText &&
      (hasPhoneInput || hasEquipmentInput || departmentText.trim().isNotEmpty);

  bool get needsOrphanDepartmentQuickAdd =>
      selectedCaller == null &&
      !hasExplicitCallerText &&
      departmentText.trim().isNotEmpty &&
      (hasPhoneInput || hasEquipmentInput);

  /// True μόνο όταν υπάρχει πραγματική ανάγκη shared καταχώρησης orphan
  /// (όχι όταν τα στοιχεία υπάρχουν ήδη στο ίδιο τμήμα χωρίς σύγκρουση).
  bool needsOrphanDepartmentQuickAddResolved(LookupService? lookup) {
    if (!needsOrphanDepartmentQuickAdd) return false;
    if (lookup == null) return true;
    final deptText = departmentText.trim();
    final departmentId =
        selectedDepartmentId ?? lookup.findDepartmentByName(deptText)?.id;
    final phone = selectedPhone?.trim();
    final equipmentCode = equipmentText.trim().isEmpty
        ? null
        : equipmentText.trim();

    final phoneNeedsShared =
        phone != null &&
        phone.isNotEmpty &&
        (() {
          final usage = lookup.checkPhoneUsage(phone);
          if (usage.hasUserOwners) return true;
          if (departmentId == null) return true;
          return usage.departmentId != departmentId;
        })();

    final equipmentNeedsShared =
        equipmentCode != null &&
        (() {
          final usage = lookup.checkEquipmentUsage(equipmentCode);
          if (usage.hasUserOwners) return true;
          if (departmentId == null) return true;
          return usage.departmentId != departmentId;
        })();

    return phoneNeedsShared || equipmentNeedsShared;
  }

  /// Το κουμπί `+` εμφανίζεται είτε για νέα συσχέτιση σε υπάρχοντα χρήστη είτε για δημιουργία νέου καλούντα.
  bool needsAssociation(LookupService? lookup) =>
      needsExistingCallerAssociation(lookup) ||
      needsNewCallerCreation ||
      needsOrphanDepartmentQuickAddResolved(lookup) ||
      hasPendingDepartmentChange;

  bool get hasPendingDepartmentChange {
    final caller = selectedCaller;
    if (caller?.id == null) return false;
    final nextText = departmentText.trim();
    if (nextText.isEmpty) return false;

    final nextDepartmentId = selectedDepartmentId;
    if (nextDepartmentId != null) {
      return nextDepartmentId != caller!.departmentId;
    }

    // Επιτρέπει “νέο” τμήμα που δεν υπάρχει στη βάση (άρα δεν έχει id ακόμη).
    // Αποφεύγουμε false positives με κανονικοποίηση.
    final oldText = (caller!.departmentName ?? '').trim();
    final oldNorm = SearchTextNormalizer.normalizeForSearch(oldText);
    final nextNorm = SearchTextNormalizer.normalizeForSearch(nextText);
    if (nextNorm.isEmpty) return false;
    return nextNorm != oldNorm;
  }

  String? get pendingDepartmentChangeTooltip {
    if (!hasPendingDepartmentChange) return null;
    final caller = selectedCaller;
    final nextDepartmentText = departmentText.trim();
    final oldDepartment = caller?.departmentName?.trim();
    final oldText = (oldDepartment == null || oldDepartment.isEmpty)
        ? 'Χωρίς τμήμα'
        : oldDepartment;
    final callerName = caller?.name?.trim().isNotEmpty == true
        ? caller!.name!.trim()
        : normalizedCallerDisplayText;
    return 'Αλλαγή τμήματος ($oldText -> $nextDepartmentText) για $callerName';
  }

  /// Πράσινο: νέος καλούντας ή orphans σε τμήμα που δεν υπάρχει ακόμη στη βάση (όλα νέα).
  /// Πορτοκαλί: υπάρχων καλούντας (ενημέρωση/συσχέτιση/αλλαγή τμήματος) ή νέα καταχώρηση που «δένει»
  /// σε υπάρχον τμήμα (εμπλουτισμός τμήματος με τηλέφωνο/εξοπλισμό).
  Color associationColor(LookupService? lookup) {
    if (selectedCaller != null) {
      return Colors.orange;
    }
    if (needsOrphanDepartmentQuickAdd || needsNewCallerCreation) {
      final d = departmentText.trim();
      final deptExists =
          d.isNotEmpty && lookup?.findDepartmentByName(d)?.id != null;
      return deptExists ? Colors.orange : Colors.green;
    }
    return Colors.green;
  }

  /// Τι ακριβώς θα συμβεί είτε για υπάρχοντα χρήστη είτε για νέο καλούντα.
  String? associationTooltip(LookupService? lookup) {
    if (!needsAssociation(lookup)) return null;
    final phoneFilled = hasPhoneInput;
    final equipmentFilled = hasEquipmentInput;

    if (needsNewCallerCreation) {
      // Για νέο καλούντα συσχετίζεται ό,τι υπάρχει στη φόρμα (v2 §Γ: η τιμή
      // του πεδίου είναι η αλήθεια, ανεξάρτητα από το πώς αποκτήθηκε).
      final includeEquipmentForNewCaller = equipmentFilled;
      final parts = <String>[];
      if (phoneFilled) {
        parts.add('τηλέφωνο: ${selectedPhone!.trim()}');
      }
      if (includeEquipmentForNewCaller) {
        parts.add('εξοπλισμό: ${equipmentText.trim()}');
      }
      if (parts.isEmpty) {
        return 'Προσθήκη νέου καλούντα: $normalizedCallerDisplayText';
      }
      return 'Προσθήκη νέου καλούντα: $normalizedCallerDisplayText με ${parts.join(' και ')}';
    }

    if (needsOrphanDepartmentQuickAddResolved(lookup)) {
      final parts = <String>[];
      if (phoneFilled) parts.add('τηλέφωνο: ${selectedPhone!.trim()}');
      if (equipmentFilled) parts.add('εξοπλισμό: ${equipmentText.trim()}');
      return 'Προσθήκη στο τμήμα ${departmentText.trim()}: ${parts.join(' και ')}';
    }

    final name = selectedCaller?.name ?? 'άγνωστος';
    final parts = <String>[];
    if (phoneFilled && !hasPhoneAssociation) {
      parts.add('τηλεφώνου: ${selectedPhone!.trim()}');
    }
    if (equipmentFilled && !hasEquipmentAssociation(lookup)) {
      parts.add('εξοπλισμού: ${equipmentText.trim()}');
    }
    final base = parts.isEmpty
        ? null
        : 'Προσθήκη ${parts.join(' και ')} στο $name';
    final departmentPart = pendingDepartmentChangeTooltip;
    if (base == null) return departmentPart;
    if (departmentPart == null) return base;
    // Δεύτερη γραμμή για την αλλαγή τμήματος, ώστε το tooltip
    // να μην γίνεται υπερβολικά μακρύ σε μία μόνο σειρά.
    return '$base\n$departmentPart';
  }

  /// True όταν μπορεί να γίνει υποβολή κλήσης: εσωτερικό με τουλάχιστον ένα ψηφίο
  /// και χωρίς χαρακτήρες γράμματος (π.χ. `210-LAB` μένει ανενεργό).
  bool get canSubmitCall {
    final raw = selectedPhone?.trim() ?? '';
    if (raw.isEmpty) return false;
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return false;
    if (RegExp(r'[A-Za-zΑ-Ωα-ω]').hasMatch(raw)) return false;
    return true;
  }

  SmartEntitySelectorState copyWith({
    String? selectedPhone,
    bool clearSelectedPhone = false,
    UserModel? selectedCaller,
    bool clearSelectedCaller = false,
    EquipmentModel? selectedEquipment,
    bool clearSelectedEquipment = false,
    String? phoneError,
    bool clearPhoneError = false,
    List<String>? recentPhones,
    List<String>? phoneCandidates,
    bool clearPhoneCandidates = false,
    List<UserModel>? callerCandidates,
    bool clearCallerCandidates = false,
    List<EquipmentModel>? equipmentCandidates,
    bool clearEquipmentCandidates = false,
    bool? isPhoneAmbiguous,
    bool? isEquipmentAmbiguous,
    bool? callerNoMatch,
    bool? equipmentNoMatch,
    bool? hasAnyContent,
    String? equipmentText,
    String? callerDisplayText,
    String? departmentText,
    int? selectedDepartmentId,
    bool clearSelectedDepartmentId = false,
    Map<SelectorField, List<FieldConflict>>? conflicts,
    bool clearConflicts = false,
  }) {
    return SmartEntitySelectorState(
      selectedPhone: clearSelectedPhone
          ? null
          : (selectedPhone ?? this.selectedPhone),
      selectedCaller: clearSelectedCaller
          ? null
          : (selectedCaller ?? this.selectedCaller),
      selectedEquipment: clearSelectedEquipment
          ? null
          : (selectedEquipment ?? this.selectedEquipment),
      phoneError: clearPhoneError ? null : (phoneError ?? this.phoneError),
      recentPhones: recentPhones ?? this.recentPhones,
      phoneCandidates: clearPhoneCandidates
          ? []
          : (phoneCandidates ?? this.phoneCandidates),
      callerCandidates: clearCallerCandidates
          ? []
          : (callerCandidates ?? this.callerCandidates),
      equipmentCandidates: clearEquipmentCandidates
          ? []
          : (equipmentCandidates ?? this.equipmentCandidates),
      isPhoneAmbiguous: isPhoneAmbiguous ?? this.isPhoneAmbiguous,
      isEquipmentAmbiguous: isEquipmentAmbiguous ?? this.isEquipmentAmbiguous,
      callerNoMatch: callerNoMatch ?? this.callerNoMatch,
      equipmentNoMatch: equipmentNoMatch ?? this.equipmentNoMatch,
      hasAnyContent: hasAnyContent ?? this.hasAnyContent,
      equipmentText: equipmentText ?? this.equipmentText,
      callerDisplayText: callerDisplayText ?? this.callerDisplayText,
      departmentText: departmentText ?? this.departmentText,
      selectedDepartmentId: clearSelectedDepartmentId
          ? null
          : (selectedDepartmentId ?? this.selectedDepartmentId),
      conflicts: clearConflicts ? const {} : (conflicts ?? this.conflicts),
    );
  }

  SmartEntitySelectorState copyWithClearSelections() {
    return copyWith(
      clearSelectedPhone: true,
      clearSelectedCaller: true,
      clearSelectedEquipment: true,
      clearPhoneError: true,
      clearPhoneCandidates: true,
      clearCallerCandidates: true,
      clearEquipmentCandidates: true,
      isPhoneAmbiguous: false,
      isEquipmentAmbiguous: false,
      callerNoMatch: false,
      equipmentNoMatch: false,
      hasAnyContent: false,
      equipmentText: '',
      callerDisplayText: '',
      departmentText: '',
      clearSelectedDepartmentId: true,
      clearConflicts: true,
    );
  }
}

class OrphanQuickAddResult {
  const OrphanQuickAddResult({
    required this.requiresConfirmation,
    required this.message,
    this.successMessage,
  });

  final bool requiresConfirmation;
  final String message;
  final String? successMessage;
}
