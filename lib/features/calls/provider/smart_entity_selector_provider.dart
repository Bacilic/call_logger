import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/database/directory_repository.dart';
import '../../../core/services/lookup_service.dart';
import '../../../core/utils/name_parser.dart';
import '../../../core/utils/phone_list_parser.dart';
import '../../../core/utils/search_text_normalizer.dart';
import 'lookup_provider.dart';
import '../models/equipment_model.dart';
import '../models/user_model.dart';
import '../../directory/models/department_model.dart';
import '../../tasks/models/task.dart';
import '../../tasks/providers/task_service_provider.dart';
import '../../tasks/providers/tasks_provider.dart';
import '../utils/remote_target_rules.dart';
import '../utils/vnc_remote_target.dart';

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
    this.departmentIsManual = false,
    this.phoneIsManual = false,
    this.callerIsManual = false,
    this.equipmentIsManual = false,
  }) : recentPhones = recentPhones ?? [],
       phoneCandidates = phoneCandidates ?? [],
       callerCandidates = callerCandidates ?? [],
       equipmentCandidates = equipmentCandidates ?? [];

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

  /// True όταν το τμήμα έχει τροποποιηθεί χειροκίνητα από τον χρήστη.
  final bool departmentIsManual;

  /// True όταν το τηλέφωνο έχει τροποποιηθεί χειροκίνητα από τον χρήστη.
  final bool phoneIsManual;

  /// True όταν ο καλών έχει τροποποιηθεί χειροκίνητα από τον χρήστη.
  final bool callerIsManual;

  /// True όταν ο εξοπλισμός έχει τροποποιηθεί χειροκίνητα από τον χρήστη.
  final bool equipmentIsManual;

  static const int _maxRecentPhones = 20;

  String get normalizedCallerDisplayText => callerDisplayText.trim();

  bool get isUnknownCaller => normalizedCallerDisplayText == 'Άγνωστος';

  bool get hasExplicitCallerText =>
      normalizedCallerDisplayText.isNotEmpty && !isUnknownCaller;

  bool get hasPhoneInput => selectedPhone?.trim().isNotEmpty == true;

  bool get hasEquipmentInput => equipmentText.trim().isNotEmpty;

  /// Στόχος AnyDesk για σύνδεση: από [selectedEquipment] (μόνο `anydeskTarget`) ή από regex στο [equipmentText].
  String? get resolvedAnyDeskTarget {
    if (selectedEquipment != null) {
      final fromDb = selectedEquipment!.anydeskTarget?.trim();
      if (fromDb == null || fromDb.isEmpty) return null;
      return RemoteTargetRules.isValidAnyDeskTarget(fromDb) ? fromDb : null;
    }
    return RemoteTargetRules.parseAnyDeskFromFreeText(equipmentText);
  }

  bool get canConnectAnyDesk => resolvedAnyDeskTarget != null;

  /// Στόχος για κλήση VNC ([EquipmentModel.vncTarget] ή IPv4 χωρίς `PC` ή `PC` + κείμενο).
  String get resolvedVncTarget {
    if (selectedEquipment != null) {
      return selectedEquipment!.vncTarget;
    }
    return VncRemoteTarget.hostForUnknownEquipmentText(equipmentText);
  }

  /// Έγκυρη σύνδεση VNC: γνωστός εξοπλισμός με μη κενό/μη «άγνωστο» target, ή μη κενό κείμενο για `PC…`.
  bool get canConnectVnc {
    if (selectedEquipment != null) {
      final raw = selectedEquipment!.vncTarget.trim();
      return raw.isNotEmpty && raw != 'Άγνωστο';
    }
    return equipmentText.trim().isNotEmpty;
  }

  /// Κείμενο εμφάνισης δίπλα στο AnyDesk (και όταν το ID είναι μη έγκυρο αλλά υπάρχει στη βάση).
  String get anydeskTargetDisplay {
    final r = resolvedAnyDeskTarget;
    if (r != null) return r;
    final fromEq = selectedEquipment?.anydeskTarget?.trim();
    if (fromEq != null && fromEq.isNotEmpty) return fromEq;
    return '—';
  }

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
    if (lookup != null &&
        selectedEquipment?.id != null &&
        callerId != null) {
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

  /// Το κουμπί `+` εμφανίζεται είτε για νέα συσχέτιση σε υπάρχοντα χρήστη είτε για δημιουργία νέου καλούντα.
  bool needsAssociation(LookupService? lookup) =>
      needsExistingCallerAssociation(lookup) ||
      needsNewCallerCreation ||
      needsOrphanDepartmentQuickAdd ||
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
      // Για νέο καλούντα, αναφέρουμε εξοπλισμό μόνο αν ο χρήστης
      // τον έχει τροποποιήσει ρητά (equipmentIsManual = true). Έτσι
      // δεν "υπόσχεται" αλλαγή εξοπλισμού όταν το πεδίο προέκυψε
      // μόνο από autofill.
      final includeEquipmentForNewCaller = equipmentFilled && equipmentIsManual;
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

    if (needsOrphanDepartmentQuickAdd) {
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
    bool? departmentIsManual,
    bool? phoneIsManual,
    bool? callerIsManual,
    bool? equipmentIsManual,
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
      departmentIsManual: departmentIsManual ?? this.departmentIsManual,
      phoneIsManual: phoneIsManual ?? this.phoneIsManual,
      callerIsManual: callerIsManual ?? this.callerIsManual,
      equipmentIsManual: equipmentIsManual ?? this.equipmentIsManual,
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
      departmentIsManual: false,
      phoneIsManual: false,
      callerIsManual: false,
      equipmentIsManual: false,
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

/// Notifier για τον έξυπνο επιλογέα: update/clear, recentPhones, clearAfterSubmit.
/// Focus και controllers ανήκουν στο widget· το notifier δουλεύει μόνο με state.
class SmartEntitySelectorNotifier extends Notifier<SmartEntitySelectorState> {
  bool _isFillingFromLookup = false;
  static const int _criticalTaskPriority = 2;

  /// Έως ένα quick task ανά κύκλο φόρμας· set μόνο μετά επιτυχή insert.
  int? _associationQuickTaskId;

  void _resetAssociationQuickTaskCycle() {
    _associationQuickTaskId = null;
  }

  Future<OrphanQuickAddResult?> quickAddOrphanToDepartment({
    bool forceSharedOnConflict = false,
  }) async {
    final s = state;
    if (!s.needsOrphanDepartmentQuickAdd) return null;
    final lookup = (await ref.read(lookupServiceProvider.future)).service;
    final deptText = s.departmentText.trim();
    var departmentId = s.selectedDepartmentId;
    DepartmentModel? selectedDepartment;
    if (departmentId != null) {
      for (final d in lookup.departments) {
        if (d.id == departmentId && !d.isDeleted) {
          selectedDepartment = d;
          break;
        }
      }
    } else {
      selectedDepartment = lookup.findDepartmentByName(deptText);
      departmentId = selectedDepartment?.id;
    }
    final phone = s.selectedPhone?.trim();
    final equipmentCode = s.equipmentText.trim().isEmpty ? null : s.equipmentText.trim();

    final dbOrphan = await DatabaseHelper.instance.database;
    final dirOrphan = DirectoryRepository(dbOrphan);
    final deptExistedBefore =
        deptText.isNotEmpty && await dirOrphan.departmentNameExists(deptText);
    final phoneExistedBefore = (phone != null && phone.isNotEmpty)
        ? await dirOrphan.phoneNumberExists(phone)
        : true;
    final equipmentExistedBefore = (equipmentCode != null)
        ? await dirOrphan.equipmentCodeExists(equipmentCode)
        : true;

    final phoneUsage = (phone != null && phone.isNotEmpty)
        ? lookup.checkPhoneUsage(phone)
        : null;
    final equipmentUsage = (equipmentCode != null)
        ? lookup.checkEquipmentUsage(equipmentCode)
        : null;

    final phoneConflict = phoneUsage != null &&
        (phoneUsage.hasUserOwners ||
            (phoneUsage.departmentId != null &&
                departmentId != null &&
                phoneUsage.departmentId != departmentId));
    final equipmentConflict = equipmentUsage != null &&
        (equipmentUsage.hasUserOwners ||
            (equipmentUsage.departmentId != null &&
                departmentId != null &&
                equipmentUsage.departmentId != departmentId));
    final hasConflict = phoneConflict || equipmentConflict;

    if (hasConflict && !forceSharedOnConflict) {
      final lines = <String>[
        'Εντοπίστηκαν πιθανές συγκρούσεις για Shared Policy.',
      ];
      if (phoneConflict) {
        if (phoneUsage.hasUserOwners) {
          lines.add(
            'Το τηλέφωνο ${phoneUsage.phone} ανήκει ήδη στους: ${phoneUsage.userNames.join(', ')}.',
          );
        }
        if (phoneUsage.departmentId != null && phoneUsage.departmentName != null) {
          lines.add(
            'Το τηλέφωνο ${phoneUsage.phone} έχει ήδη τοποθεσία τμήμα: ${phoneUsage.departmentName}.',
          );
        }
      }
      if (equipmentConflict) {
        if (equipmentUsage.hasUserOwners) {
          lines.add(
            'Ο εξοπλισμός ${equipmentUsage.code} ανήκει ήδη στους: ${equipmentUsage.userNames.join(', ')}.',
          );
        }
        if (equipmentUsage.departmentId != null &&
            equipmentUsage.departmentName != null) {
          lines.add(
            'Ο εξοπλισμός ${equipmentUsage.code} έχει ήδη τοποθεσία τμήμα: ${equipmentUsage.departmentName}.',
          );
        }
      }
      lines.add(
        'Θέλετε να καταχωρηθούν ΚΑΙ ως κοινόχρηστα στο τμήμα ${deptText.isEmpty ? '—' : deptText};',
      );
      return OrphanQuickAddResult(
        requiresConfirmation: true,
        message: lines.join('\n'),
      );
    }

    departmentId ??= await dirOrphan.getOrCreateDepartmentIdByName(
      deptText,
    );
    if (departmentId == null) {
      return const OrphanQuickAddResult(
        requiresConfirmation: false,
        message: 'Δεν βρέθηκε/δημιουργήθηκε τμήμα.',
      );
    }

    if (phone != null && phone.isNotEmpty) {
      await dirOrphan.updatePhoneDepartment(phone, departmentId);
    }
    if (equipmentCode != null) {
      await dirOrphan.updateEquipmentDepartment(
        equipmentCode,
        departmentId,
      );
    }

    ref.invalidate(lookupServiceProvider);
    final refreshed = (await ref.read(lookupServiceProvider.future)).service;
    final finalDepartment = refreshed.findDepartmentByName(deptText);
    state = state.copyWith(
      selectedDepartmentId: finalDepartment?.id ?? departmentId,
      departmentText: finalDepartment?.name ?? deptText,
      departmentIsManual: true,
      callerNoMatch: false,
      equipmentNoMatch: false,
    );

    final added = <String>[];
    if (phone != null && phone.isNotEmpty) added.add('τηλέφωνο');
    if (equipmentCode != null) added.add('εξοπλισμός');
    final associationWorkDone = added.isNotEmpty;
    final success = added.isEmpty
        ? 'Δεν υπήρχε στοιχείο προς καταχώρηση.'
        : 'Καταχωρήθηκε ${added.join(' και ')} ως κοινόχρηστο στο τμήμα ${state.departmentText.trim()}.';

    final newEntityEligible = (deptText.isNotEmpty && !deptExistedBefore) ||
        (phone != null && phone.isNotEmpty && !phoneExistedBefore) ||
        (equipmentCode != null && !equipmentExistedBefore);

    final resolvedDeptId = finalDepartment?.id ?? departmentId;
    final equipResolved = (equipmentCode != null && equipmentCode.isNotEmpty)
        ? refreshed.findEquipmentsByCode(equipmentCode)
        : const <EquipmentModel>[];
    final resolvedEquipmentId =
        equipResolved.isNotEmpty ? equipResolved.first.id : null;

    if (newEntityEligible || _associationQuickTaskId != null) {
      try {
        await _syncAssociationQuickTask(
          newEntityEligible: newEntityEligible,
          associationWorkDone: associationWorkDone,
          summaryText: success,
          callerName: null,
          callerId: null,
          departmentId: resolvedDeptId,
          equipmentId: resolvedEquipmentId,
          phoneText: phone,
          userText: null,
          equipmentText: equipmentCode,
          departmentText: state.departmentText.trim().isEmpty
              ? null
              : state.departmentText.trim(),
        );
      } catch (e, st) {
        debugPrint('Orphan quick task: $e\n$st');
      }
    }

    return OrphanQuickAddResult(
      requiresConfirmation: false,
      message: success,
      successMessage: success,
    );
  }

  bool _computeHasAnyContent({
    String? phoneText,
    String? callerText,
    String? equipmentText,
    String? departmentText,
  }) {
    final phone =
        phoneText?.trim().isNotEmpty ??
        state.selectedPhone?.trim().isNotEmpty ??
        false;
    final caller =
        callerText?.trim().isNotEmpty ??
        state.callerDisplayText.trim().isNotEmpty;
    final equipment =
        equipmentText?.trim().isNotEmpty ??
        state.equipmentText.trim().isNotEmpty;
    final department =
        departmentText?.trim().isNotEmpty ??
        state.departmentText.trim().isNotEmpty;
    return phone ||
        caller ||
        equipment ||
        department ||
        state.selectedCaller != null ||
        state.selectedEquipment != null ||
        state.callerCandidates.isNotEmpty ||
        state.equipmentCandidates.isNotEmpty;
  }

  /// Κλήση μετά από Enter ή focus out· ενημερώνει hasAnyContent για εμφάνιση κουμπιού "Καθαρισμός όλων"
  /// και αποθηκεύει το equipmentText/departmentText. Το UI περνάει τις τρέχουσες τιμές πεδίων.
  void checkContent({
    String? phoneText,
    String? callerText,
    String? equipmentText,
    String? departmentText,
  }) {
    state = state.copyWith(
      hasAnyContent: _computeHasAnyContent(
        phoneText: phoneText,
        callerText: callerText,
        equipmentText: equipmentText,
        departmentText: departmentText,
      ),
      equipmentText: equipmentText?.trim() ?? state.equipmentText,
      // Στο departmentText κρατάμε το ακριβές input του χρήστη (με κενά),
      // ώστε να μην αφαιρούνται αυτόματα τα διαστήματα πληκτρολόγησης.
      departmentText: departmentText ?? state.departmentText,
    );
  }

  @override
  SmartEntitySelectorState build() {
    return SmartEntitySelectorState();
  }

  /// Φόρτωση πεδίων επιλογέα από υπάρχον `Task` (λειτουργία επεξεργασίας).
  Future<void> loadFromTask(Task task) async {
    final lookupService = (await ref.read(
      lookupServiceProvider.future,
    )).service;
    final user = task.callerId != null
        ? lookupService.findUserById(task.callerId)
        : null;

    final phoneRaw = task.phoneText?.trim();
    final phoneValue = phoneRaw != null && phoneRaw.isNotEmpty
        ? phoneRaw
        : null;

    final trimmedUserText = (task.userText ?? '').trim();
    final nameTrim = (user?.name ?? '').trim();
    final callerDisplayText = trimmedUserText.isNotEmpty
        ? trimmedUserText
        : nameTrim;

    final hasAnyContent =
        user != null ||
        phoneValue != null ||
        trimmedUserText.isNotEmpty ||
        (task.departmentText?.trim().isNotEmpty ?? false) ||
        (task.equipmentText?.trim().isNotEmpty ?? false);

    state = state.copyWith(
      selectedCaller: user,
      clearSelectedCaller: user == null,
      selectedPhone: phoneValue,
      clearSelectedPhone: phoneValue == null,
      callerDisplayText: callerDisplayText,
      departmentText: task.departmentText ?? '',
      equipmentText: task.equipmentText ?? '',
      hasAnyContent: hasAnyContent,
      clearPhoneCandidates: true,
      clearCallerCandidates: true,
      clearEquipmentCandidates: true,
      isPhoneAmbiguous: false,
      isEquipmentAmbiguous: false,
      callerNoMatch: false,
      equipmentNoMatch: false,
    );
  }

  void updatePhone(String? value) {
    if (value == state.selectedPhone && state.selectedCaller != null) return;
    state = state.copyWith(
      selectedPhone: value,
      clearSelectedPhone: value == null,
      clearPhoneError: true,
      clearPhoneCandidates: true,
    );
    if (value == null || value.trim().isEmpty) {
      state = state.copyWith(
        clearCallerCandidates: true,
        clearSelectedCaller: true,
        clearEquipmentCandidates: true,
        clearSelectedEquipment: true,
        isPhoneAmbiguous: false,
        isEquipmentAmbiguous: false,
        callerNoMatch: false,
        equipmentNoMatch: false,
      );
    } else {
      state = state.copyWith(
        clearCallerCandidates: true,
        clearSelectedCaller: true,
        clearEquipmentCandidates: true,
        clearSelectedEquipment: true,
        isPhoneAmbiguous: false,
        isEquipmentAmbiguous: false,
        callerNoMatch: false,
        equipmentNoMatch: false,
      );
    }
  }

  /// Ρητή επιλογή τηλεφώνου από λίστα προτάσεων (Autocomplete/Search).
  /// Δεν κάνει destructive reset caller/equipment και κρατά ως source την επιλογή λίστας.
  void setPhone(String phone) {
    final trimmed = phone.trim();
    if (trimmed.isEmpty) {
      updatePhone(null);
      return;
    }
    state = state.copyWith(
      selectedPhone: trimmed,
      clearSelectedPhone: false,
      clearPhoneError: true,
      clearPhoneCandidates: true,
      isPhoneAmbiguous: false,
      phoneIsManual: false,
    );
  }

  List<String> _recentPhonesWithPhoneBumped(String trimmed) {
    final list = List<String>.from(state.recentPhones);
    list.remove(trimmed);
    list.insert(0, trimmed);
    if (list.length > SmartEntitySelectorState._maxRecentPhones) {
      list.length = SmartEntitySelectorState._maxRecentPhones;
    }
    return list;
  }

  /// Επιλογή τηλεφώνου από τη λίστα `phoneCandidates` (ήδη γνωστός καλούντας).
  /// Δεν καθαρίζει context καλούντα / εξοπλισμού.
  void selectPhoneFromCandidates(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    state = state.copyWith(
      selectedPhone: trimmed,
      clearSelectedPhone: false,
      clearPhoneError: true,
      clearPhoneCandidates: true,
      isPhoneAmbiguous: false,
      phoneIsManual: false,
      recentPhones: _recentPhonesWithPhoneBumped(trimmed),
    );

    final callerId = state.selectedCaller?.id;
    final canAutofillEquipment =
        !state.equipmentIsManual || state.equipmentText.trim().isEmpty;
    if (callerId != null && canAutofillEquipment) {
      performEquipmentLookup(callerId);
    }
  }

  void markPhoneAsManual() {
    if (state.phoneIsManual) return;
    state = state.copyWith(phoneIsManual: true);
  }

  void markCallerAsManual() {
    if (state.callerIsManual) return;
    state = state.copyWith(callerIsManual: true);
  }

  void markEquipmentAsManual() {
    if (state.equipmentIsManual) return;
    state = state.copyWith(equipmentIsManual: true);
  }

  void clearPhone() {
    _resetAssociationQuickTaskCycle();
    state = state.copyWithClearSelections();
  }

  /// Μηδενίζει selectedPhone, selectedCaller, selectedEquipment, phoneError, candidates.
  /// Ο καθαρισμός των πεδίων κειμένου γίνεται από το UI.
  void clearAll() {
    _resetAssociationQuickTaskCycle();
    state = state.copyWithClearSelections();
  }

  /// Μηδενίζει μόνο τις λίστες candidates και τα ambiguous flags (όχι τα επιλεγμένα πεδία).
  void clearAllCandidates() {
    state = state.copyWith(
      clearPhoneCandidates: true,
      clearCallerCandidates: true,
      clearEquipmentCandidates: true,
      isPhoneAmbiguous: false,
      isEquipmentAmbiguous: false,
      callerNoMatch: false,
      equipmentNoMatch: false,
    );
  }

  List<String> _splitPhones(String? rawPhone) {
    return PhoneListParser.splitPhones(rawPhone);
  }

  void _setPhoneValueFromLookup(String phone) {
    final trimmed = phone.trim();
    if (trimmed.isEmpty) return;
    state = state.copyWith(
      selectedPhone: trimmed,
      clearSelectedPhone: false,
      clearPhoneError: true,
      clearPhoneCandidates: true,
      isPhoneAmbiguous: false,
      phoneIsManual: false,
    );
    markPhoneUsed(trimmed);
  }

  void _setPhoneCandidatesFromLookup(List<String> phones) {
    if (phones.isEmpty) return;
    final sorted = List<String>.from(phones);
    sorted.sort((a, b) => a.compareTo(b));
    state = state.copyWith(
      phoneCandidates: sorted,
      clearSelectedPhone: true,
      isPhoneAmbiguous: true,
      clearPhoneError: true,
    );
  }

  /// Γεμίζει/διατηρεί ένα μόνο εσωτερικό τηλέφωνο από το προφίλ χρήστη (λίστα στο DB).
  /// - Αν το πεδίο είχε κατά λάθος ολόκληρη τη συνενωμένη λίστα (`phoneJoined`), την καθαρίζει και συνεχίζει με λογική πολλαπλών.
  /// - Αν υπάρχει έγκυρο token μέσα στη λίστα, το κρατάει.
  /// - Αν είναι κενό και υπάρχουν πολλά → candidates· αν ένα → αυτό.
  void _autofillPhoneFromUserProfile(UserModel user) {
    if (!_canAutofillPhone()) return;
    final pool = user.phoneJoined.trim();
    final phones = List<String>.from(user.phones);
    if (phones.isEmpty) return;

    var previous = state.selectedPhone?.trim() ?? '';
    if (previous.isNotEmpty &&
        pool.isNotEmpty &&
        previous == pool &&
        phones.length > 1) {
      state = state.copyWith(clearSelectedPhone: true, clearPhoneError: true);
      previous = '';
    }

    if (phones.length == 1) {
      final only = phones.first;
      if (previous.isEmpty) {
        _setPhoneValueFromLookup(only);
      } else if (PhoneListParser.containsPhone(pool, previous)) {
        _setPhoneValueFromLookup(previous);
      }
      return;
    }

    if (previous.isNotEmpty && PhoneListParser.containsPhone(pool, previous)) {
      _setPhoneValueFromLookup(previous);
      return;
    }
    if (previous.isNotEmpty) {
      return;
    }
    _setPhoneCandidatesFromLookup(phones);
  }

  bool _canAutofillPhone() {
    return !state.phoneIsManual ||
        (state.selectedPhone?.trim().isEmpty ?? true);
  }

  /// Autofill τηλεφώνου από τον κάτοχο του εξοπλισμού μόνο όταν δεν υπάρχει ήδη
  /// επιλεγμένος αριθμός — αλλιώς (π.χ. lookup γραμμής) δεν καλούμε
  /// `_setPhoneCandidatesFromLookup` (αποφυγή `clearSelectedPhone`).
  bool _shouldApplyEquipmentOwnerPhoneAutofill() {
    if (!_canAutofillPhone()) return false;
    return state.selectedPhone?.trim().isEmpty ?? true;
  }

  bool _canAutofillDepartmentForUser(UserModel user) {
    final hasLockedManualDepartmentSelection =
        state.departmentIsManual &&
        state.selectedDepartmentId != null &&
        state.departmentText.trim().isNotEmpty;
    if (hasLockedManualDepartmentSelection) {
      // Όταν ο χρήστης έχει επιλέξει ρητά τμήμα στο header, δεν το
      // αντικαθιστούμε αυτόματα από το προφίλ του caller.
      return false;
    }
    final currentCallerId = state.selectedCaller?.id;
    final newCallerId = user.id;
    if (newCallerId != null && currentCallerId != newCallerId) {
      // Σε αλλαγή καλούντα επιτρέπουμε auto-fill από το νέο προφίλ.
      return true;
    }
    return !state.departmentIsManual || state.departmentText.trim().isEmpty;
  }

  String _departmentTextForUser(UserModel user) {
    if (user.departmentId == null) return '';
    final asyncLookup = ref.read(lookupServiceProvider);
    final lookup = asyncLookup.value?.service;
    if (lookup == null) return '';
    return lookup.departmentIdToName[user.departmentId] ?? '';
  }

  /// Lookup τηλεφώνου: 0 → no match hint, 1 → setCaller + equipment lookup, >1 → dropdown candidates.
  void performPhoneLookup(String phone) {
    if (_isFillingFromLookup) return;

    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 3) {
      _isFillingFromLookup = true;
      try {
        state = state.copyWith(
          clearPhoneCandidates: true,
          clearCallerCandidates: true,
          clearSelectedCaller: true,
          clearEquipmentCandidates: true,
          clearSelectedEquipment: true,
          isPhoneAmbiguous: false,
          isEquipmentAmbiguous: false,
          callerNoMatch: false,
          equipmentNoMatch: false,
        );
      } finally {
        _isFillingFromLookup = false;
      }
      return;
    }

    final snap = ref.read(lookupServiceProvider);
    if (snap.hasValue) {
      _applyPhoneLookupWithCatalog(digits, snap.requireValue.service);
      return;
    }
    // Κατά το πρώτο frame το AsyncValue μπορεί να είναι ακόμα loading.
    ref.read(lookupServiceProvider.future).then((bundle) {
      if (!ref.mounted) return;
      _applyPhoneLookupWithCatalog(digits, bundle.service);
    }).catchError((_) {});
  }

  void _applyPhoneLookupWithCatalog(String digits, LookupService lookup) {
    if (_isFillingFromLookup) return;
    _isFillingFromLookup = true;
    try {
      final users = lookup.findUsersByPhone(digits);
      if (users.isEmpty) {
        final orphanDept = lookup.getDepartmentByPhone(digits);
        final canAutofillDepartment =
            (!state.departmentIsManual || state.departmentText.trim().isEmpty) &&
                state.selectedDepartmentId == null;
        state = state.copyWith(
          clearPhoneCandidates: true,
          callerCandidates: [],
          clearSelectedCaller: true,
          equipmentCandidates: [],
          clearSelectedEquipment: true,
          isPhoneAmbiguous: false,
          isEquipmentAmbiguous: false,
          callerNoMatch: true,
          equipmentNoMatch: false,
          departmentText: (orphanDept != null && canAutofillDepartment)
              ? orphanDept.name
              : state.departmentText,
          selectedDepartmentId: (orphanDept != null && canAutofillDepartment)
              ? orphanDept.id
              : state.selectedDepartmentId,
          departmentIsManual: (orphanDept != null && canAutofillDepartment)
              ? false
              : state.departmentIsManual,
        );
        return;
      }
      if (users.length == 1) {
        final user = users.first;
        final name = user.name ?? user.fullNameWithDepartment;
        final shouldAutofillDepartment = _canAutofillDepartmentForUser(user);
        final canAutofillCaller =
            !state.callerIsManual || state.callerDisplayText.trim().isEmpty;
        if (canAutofillCaller) {
          state = state.copyWith(
            clearPhoneCandidates: true,
            selectedCaller: user,
            callerCandidates: [],
            isPhoneAmbiguous: false,
            callerNoMatch: false,
            callerDisplayText: name,
            departmentText: shouldAutofillDepartment
                ? _departmentTextForUser(user)
                : state.departmentText,
            selectedDepartmentId: shouldAutofillDepartment
                ? user.departmentId
                : state.selectedDepartmentId,
            departmentIsManual: shouldAutofillDepartment
                ? false
                : state.departmentIsManual,
            callerIsManual: false,
          );
        } else if (shouldAutofillDepartment) {
          state = state.copyWith(
            clearPhoneCandidates: true,
            callerCandidates: [],
            isPhoneAmbiguous: false,
            callerNoMatch: false,
            departmentText: _departmentTextForUser(user),
            selectedDepartmentId: user.departmentId,
            departmentIsManual: false,
          );
        } else {
          state = state.copyWith(
            clearPhoneCandidates: true,
            callerCandidates: [],
            isPhoneAmbiguous: false,
            callerNoMatch: false,
          );
        }
        markPhoneUsed(digits);
        if (users.first.id != null) {
          _performEquipmentLookupForUser(users.first.id!);
        }
        return;
      }
      state = state.copyWith(
        clearPhoneCandidates: true,
        callerCandidates: users,
        clearSelectedCaller: true,
        equipmentCandidates: [],
        clearSelectedEquipment: true,
        isPhoneAmbiguous: true,
        isEquipmentAmbiguous: false,
        callerNoMatch: false,
        equipmentNoMatch: false,
      );
    } finally {
      _isFillingFromLookup = false;
    }
  }

  /// Lookup εξοπλισμού για userId: 0 → no match hint, 1 → setEquipment, >1 → dropdown candidates.
  void performEquipmentLookup(int userId) {
    if (_isFillingFromLookup) return;
    _isFillingFromLookup = true;
    try {
      _performEquipmentLookupForUser(userId);
    } finally {
      _isFillingFromLookup = false;
    }
  }

  void _performEquipmentLookupForUser(int userId) {
    final asyncLookup = ref.read(lookupServiceProvider);
    final lookup = asyncLookup.value?.service;
    if (lookup == null) return;
    final list = lookup.findEquipmentsForUser(userId);
    if (list.isEmpty) {
      state = state.copyWith(
        equipmentCandidates: [],
        clearSelectedEquipment: true,
        isEquipmentAmbiguous: false,
        equipmentNoMatch: true,
      );
      return;
    }
    if (list.length == 1) {
      final canAutofillEquipment =
          !state.equipmentIsManual || state.equipmentText.trim().isEmpty;
      if (canAutofillEquipment) {
        state = state.copyWith(
          selectedEquipment: list.first,
          equipmentCandidates: [],
          isEquipmentAmbiguous: false,
          equipmentNoMatch: false,
          equipmentIsManual: false,
        );
      } else {
        state = state.copyWith(
          equipmentCandidates: [],
          isEquipmentAmbiguous: false,
          equipmentNoMatch: false,
        );
      }
      return;
    }
    state = state.copyWith(
      equipmentCandidates: list,
      clearSelectedEquipment: true,
      isEquipmentAmbiguous: true,
      equipmentNoMatch: false,
    );
  }

  void performCallerLookup(String nameOrQuery, {String? phoneFieldDigits}) {
    if (_isFillingFromLookup) return;
    _isFillingFromLookup = true;
    try {
      final query = nameOrQuery.trim();
      if (query.isEmpty || query == 'Άγνωστος') return;
      final asyncLookup = ref.read(lookupServiceProvider);
      final lookup = asyncLookup.value?.service;
      if (lookup == null) return;
      final users = lookup.searchUsersByQuery(query);
      if (users.isEmpty) {
        state = state.copyWith(
          callerCandidates: [],
          clearSelectedCaller: true,
          callerNoMatch: true,
          isPhoneAmbiguous: false,
          clearPhoneCandidates: true,
          equipmentNoMatch: false,
        );
        return;
      }
      if (users.length > 1) {
        state = state.copyWith(
          callerCandidates: users,
          clearSelectedCaller: true,
          callerNoMatch: false,
          clearPhoneCandidates: true,
          isPhoneAmbiguous: false,
        );
        return;
      }

      final user = users.first;
      final displayName = user.name ?? user.fullNameWithDepartment;
      final shouldAutofillDepartment = _canAutofillDepartmentForUser(user);
      state = state.copyWith(
        selectedCaller: user,
        clearPhoneCandidates: true,
        callerCandidates: [],
        callerNoMatch: false,
        isPhoneAmbiguous: false,
        callerDisplayText: displayName,
        departmentText: shouldAutofillDepartment
            ? _departmentTextForUser(user)
            : state.departmentText,
        selectedDepartmentId: shouldAutofillDepartment
            ? user.departmentId
            : state.selectedDepartmentId,
        departmentIsManual: shouldAutofillDepartment
            ? false
            : state.departmentIsManual,
        callerIsManual: false,
      );
      final snap =
          phoneFieldDigits?.replaceAll(RegExp(r'[^0-9]'), '').trim() ?? '';
      if (snap.isNotEmpty &&
          (state.selectedPhone == null ||
              state.selectedPhone!.trim().isEmpty)) {
        state = state.copyWith(
          selectedPhone: snap,
          clearSelectedPhone: false,
          clearPhoneError: true,
        );
      }
      _autofillPhoneFromUserProfile(user);

      final canAutofillEquipment =
          !state.equipmentIsManual || state.equipmentText.trim().isEmpty;
      if (user.id != null && canAutofillEquipment) {
        _performEquipmentLookupForUser(user.id!);
      }
    } finally {
      _isFillingFromLookup = false;
    }
  }

  void performEquipmentLookupByCode(String code) {
    if (_isFillingFromLookup) return;
    _isFillingFromLookup = true;
    try {
      final query = code.trim();
      if (query.isEmpty) return;
      final asyncLookup = ref.read(lookupServiceProvider);
      final lookup = asyncLookup.value?.service;
      if (lookup == null) return;
      final list = lookup.findEquipmentsByCode(query);
      if (list.isEmpty) {
        state = state.copyWith(
          equipmentCandidates: [],
          clearSelectedEquipment: true,
          isEquipmentAmbiguous: false,
          equipmentNoMatch: true,
        );
        return;
      }
      if (list.length > 1) {
        state = state.copyWith(
          equipmentCandidates: list,
          clearSelectedEquipment: true,
          isEquipmentAmbiguous: true,
          equipmentNoMatch: false,
        );
        return;
      }

      final equipment = list.first;
      state = state.copyWith(
        selectedEquipment: equipment,
        clearPhoneCandidates: true,
        equipmentCandidates: [],
        isEquipmentAmbiguous: false,
        equipmentNoMatch: false,
        equipmentIsManual: false,
      );

      final owners = equipment.id != null
          ? lookup.findUsersForEquipment(equipment.id!)
          : <UserModel>[];
      final user = owners.isNotEmpty ? owners.first : null;
      if (user == null) return;

      final shouldAutofillDepartment = _canAutofillDepartmentForUser(user);
      final canAutofillCaller =
          !state.callerIsManual || state.callerDisplayText.trim().isEmpty;
      final hasLockedDepartmentSelection =
          state.departmentIsManual && state.selectedDepartmentId != null;
      final isCallerOutsideSelectedDepartment =
          hasLockedDepartmentSelection &&
          user.departmentId != state.selectedDepartmentId;
      if (canAutofillCaller && !isCallerOutsideSelectedDepartment) {
        state = state.copyWith(
          selectedCaller: user,
          callerCandidates: [],
          isPhoneAmbiguous: false,
          callerNoMatch: false,
          callerDisplayText: user.name ?? user.fullNameWithDepartment,
          departmentText: shouldAutofillDepartment
              ? _departmentTextForUser(user)
              : state.departmentText,
          selectedDepartmentId: shouldAutofillDepartment
              ? user.departmentId
              : state.selectedDepartmentId,
          departmentIsManual: shouldAutofillDepartment
              ? false
              : state.departmentIsManual,
          callerIsManual: false,
        );
      } else if (shouldAutofillDepartment) {
        state = state.copyWith(
          departmentText: _departmentTextForUser(user),
          selectedDepartmentId: user.departmentId,
          departmentIsManual: false,
        );
      }

      if (_shouldApplyEquipmentOwnerPhoneAutofill()) {
        _autofillPhoneFromUserProfile(user);
      }
    } finally {
      _isFillingFromLookup = false;
    }
  }

  void clearPhoneCandidates() {
    state = state.copyWith(clearPhoneCandidates: true, isPhoneAmbiguous: false);
  }

  void setCaller(UserModel? value) {
    final deptText = value == null ? '' : _departmentTextForUser(value);
    state = state.copyWith(
      selectedCaller: value,
      clearSelectedCaller: value == null,
      clearPhoneCandidates: true,
      clearCallerCandidates: true,
      isPhoneAmbiguous: false,
      callerNoMatch: false,
      callerDisplayText: value?.name ?? value?.fullNameWithDepartment ?? '',
      departmentText: deptText,
      selectedDepartmentId: value?.departmentId,
      departmentIsManual: false,
      callerIsManual: false,
    );
    if (value != null) {
      final pool = value.phoneJoined.trim();
      final sp = state.selectedPhone?.trim() ?? '';
      if (pool.isNotEmpty &&
          sp.isNotEmpty &&
          sp == pool &&
          _splitPhones(sp).length > 1) {
        state = state.copyWith(clearSelectedPhone: true, clearPhoneError: true);
      }
    }
  }

  void updateSelectedCaller(UserModel? value) {
    setCaller(value);
  }

  void updateCallerDisplayText(String text) {
    state = state.copyWith(callerDisplayText: text);
  }

  void clearCaller() {
    state = state.copyWith(
      clearSelectedCaller: true,
      clearPhoneCandidates: true,
      clearCallerCandidates: true,
      isPhoneAmbiguous: false,
      callerDisplayText: '',
      departmentText: '',
      clearSelectedDepartmentId: true,
      departmentIsManual: false,
      callerIsManual: false,
    );
  }

  void updateDepartmentText(String text) {
    final trimmed = text.trim();
    int? matchedDepartmentId;
    if (trimmed.isNotEmpty) {
      final lookup = ref.read(lookupServiceProvider).value?.service;
      if (lookup != null) {
        final normalized = SearchTextNormalizer.normalizeForSearch(trimmed);
        for (final dep in lookup.departments) {
          if (SearchTextNormalizer.normalizeForSearch(dep.name) == normalized) {
            matchedDepartmentId = dep.id;
            break;
          }
        }
      }
    }
    state = state.copyWith(
      // Αποθηκεύουμε το raw κείμενο (με κενά) ώστε ο χρήστης να βλέπει
      // ακριβώς αυτό που πληκτρολόγησε. Το trimming χρησιμοποιείται μόνο
      // για matching/clearSelectedDepartmentId.
      departmentText: text,
      selectedDepartmentId: matchedDepartmentId,
      clearSelectedDepartmentId: trimmed.isEmpty,
      departmentIsManual: true,
    );
  }

  void selectDepartment(DepartmentModel dept) {
    final departmentId = dept.id;
    if (departmentId == null) {
      updateDepartmentText(dept.name);
      return;
    }
    final asyncLookup = ref.read(lookupServiceProvider);
    final lookup = asyncLookup.value?.service;

    List<UserModel>? callerCandidates;
    List<EquipmentModel>? equipmentCandidates;
    List<String>? phoneCandidates;
    final hasCallerInput = state.callerDisplayText.trim().isNotEmpty;
    final keepCallerUntouched = hasCallerInput || state.selectedCaller != null;
    final hasPhoneInput = state.selectedPhone?.trim().isNotEmpty == true;
    final hasEquipmentInput = state.equipmentText.trim().isNotEmpty;

    if (lookup != null) {
      // Αν ο καλών είναι ήδη ορισμένος/ορατός, δεν τον πειράζουμε στην αλλαγή τμήματος.
      // Prefill λίστας caller μόνο όταν το πεδίο είναι πραγματικά κενό.
      if (!keepCallerUntouched) {
        callerCandidates = lookup.getUsersByDepartment(departmentId);
      }
      if (!hasEquipmentInput && !state.equipmentIsManual) {
        equipmentCandidates = lookup.getEquipmentByDepartment(departmentId);
      }
      if (!hasPhoneInput && !state.phoneIsManual) {
        phoneCandidates = lookup.getPhonesByDepartment(departmentId);
      }
    }

    state = state.copyWith(
      departmentText: dept.name,
      selectedDepartmentId: departmentId,
      departmentIsManual: true,
      clearSelectedCaller: !keepCallerUntouched,
      callerDisplayText: keepCallerUntouched ? state.callerDisplayText : '',
      callerIsManual: keepCallerUntouched ? state.callerIsManual : false,
      callerCandidates: keepCallerUntouched
          ? state.callerCandidates
          : (callerCandidates ?? state.callerCandidates),
      equipmentCandidates: equipmentCandidates ?? state.equipmentCandidates,
      phoneCandidates: phoneCandidates ?? state.phoneCandidates,
      callerNoMatch: false,
      equipmentNoMatch: false,
      isPhoneAmbiguous: false,
      isEquipmentAmbiguous: false,
    );
  }

  void setEquipment(EquipmentModel? value) {
    state = state.copyWith(
      selectedEquipment: value,
      clearSelectedEquipment: value == null,
      clearEquipmentCandidates: true,
      isEquipmentAmbiguous: false,
      equipmentNoMatch: false,
    );
  }

  void clearEquipment() {
    state = state.copyWith(
      clearSelectedEquipment: true,
      clearEquipmentCandidates: true,
      isEquipmentAmbiguous: false,
      equipmentNoMatch: false,
      equipmentText: '',
      equipmentIsManual: false,
      hasAnyContent: _computeHasAnyContent(equipmentText: ''),
    );
  }

  void setPhoneError(String? message) {
    state = state.copyWith(
      phoneError: message,
      clearPhoneError: message == null,
    );
  }

  void clearPhoneError() {
    state = state.copyWith(clearPhoneError: true);
  }

  void markPhoneUsed(String phone) {
    final trimmed = phone.trim();
    if (trimmed.isEmpty) return;
    state = state.copyWith(recentPhones: _recentPhonesWithPhoneBumped(trimmed));
  }

  void clearAfterSubmit() {
    _resetAssociationQuickTaskCycle();
    state = state.copyWithClearSelections();
  }

  /// Προσθέτει τηλέφωνο/εξοπλισμό στον τρέχοντα χρήστη στη βάση· invalidate lookup· επιστρέφει μήνυμα για SnackBar.
  /// Σε σφάλμα βάσης επιστρέφει κείμενο σφάλματος (όχι throw).
  Future<String?> associateCurrentIfNeeded({
    bool updatePrimaryDepartment = false,
  }) async {
    final lookupForAssoc = ref.read(lookupServiceProvider).value?.service;
    if (!state.needsAssociation(lookupForAssoc)) return null;

    final msg = state.associationTooltip(lookupForAssoc);
    final directory = DirectoryRepository(await DatabaseHelper.instance.database);
    if (state.needsNewCallerCreation) {
      final name = NameParserUtility.stripParentheticalSuffix(
        state.normalizedCallerDisplayText,
      );
      final phone = state.selectedPhone?.trim();
      final equipmentCode = state.equipmentText.trim();
      final parsed = NameParserUtility.parse(name);
      final deptTextRaw = state.departmentText.trim();
      final departmentExistedBefore = deptTextRaw.isNotEmpty &&
          await directory.departmentNameExists(deptTextRaw);
      final phoneExistedBefore = (phone != null && phone.isNotEmpty)
          ? await directory.phoneNumberExists(phone)
          : false;
      final equipmentExistedBefore = equipmentCode.isNotEmpty
          ? await directory.equipmentCodeExists(equipmentCode)
          : false;

      final lookup = ref.read(lookupServiceProvider).value?.service;
      var departmentId =
          state.selectedDepartmentId ??
          (state.departmentText.trim().isNotEmpty && lookup != null
              ? lookup.findDepartmentByName(state.departmentText)?.id
              : null);
      if (departmentId == null && state.departmentText.trim().isNotEmpty) {
        departmentId = await directory
            .getOrCreateDepartmentIdByName(state.departmentText.trim());
      }
      try {
        final parsedPhones = PhoneListParser.splitPhones(phone);
        final userId = await directory.insertUser(
          firstName: parsed.firstName,
          lastName: parsed.lastName,
          phones: parsedPhones.isEmpty ? null : parsedPhones,
          departmentId: departmentId,
        );

        await directory.updateAssociationsIfNeeded(
          userId,
          phone,
          equipmentCode.isNotEmpty ? equipmentCode : null,
        );

        final s = state;
        final lookupNow = ref.read(lookupServiceProvider).value?.service;
        final departmentIdNow =
            s.selectedDepartmentId ??
            (s.departmentText.trim().isNotEmpty && lookupNow != null
                ? lookupNow.findDepartmentByName(s.departmentText)?.id
                : null);
        final equipTrim = s.equipmentText.trim();
        state = state.copyWith(
          selectedCaller: UserModel(
            id: userId,
            firstName: parsed.firstName,
            lastName: parsed.lastName,
            phones: parsedPhones,
            departmentId: departmentIdNow,
          ),
          selectedEquipment: equipTrim.isNotEmpty
              ? EquipmentModel(code: equipTrim)
              : s.selectedEquipment,
          callerDisplayText: s.callerDisplayText.trim().isNotEmpty
              ? s.callerDisplayText
              : name,
          departmentText: s.departmentText,
          phoneIsManual: false,
          callerIsManual: false,
          equipmentIsManual: false,
        );
        ref.invalidate(lookupServiceProvider);
        final refreshedLookup = (await ref.read(lookupServiceProvider.future)).service;
        final matchedNewCallerEquipment = equipTrim.isEmpty
            ? const <EquipmentModel>[]
            : refreshedLookup.findEquipmentsByCode(equipTrim);
        final resolvedEquipmentId = matchedNewCallerEquipment.isEmpty
            ? null
            : matchedNewCallerEquipment.first.id;
        final resolvedDepartmentId = departmentIdNow ??
            (s.departmentText.trim().isNotEmpty
                ? refreshedLookup.findDepartmentByName(s.departmentText)?.id
                : null);
        // Πλήρες EquipmentModel με id — αλλιώς το hasEquipmentAssociation μείνει false
        // και το submit κλήσης ξανατρέχει συσχέτιση + δεύτερη γρήγορη εκκρεμότητα.
        if (matchedNewCallerEquipment.isNotEmpty) {
          state = state.copyWith(
            selectedEquipment: matchedNewCallerEquipment.first,
          );
        }
        await _syncAssociationQuickTask(
          newEntityEligible: true,
          associationWorkDone: true,
          summaryText: msg,
          callerName: state.selectedCaller?.name ?? state.callerDisplayText.trim(),
          callerId: userId,
          departmentId: resolvedDepartmentId,
          equipmentId: resolvedEquipmentId,
          phoneText: s.selectedPhone?.trim(),
          userText: s.callerDisplayText.trim().isEmpty
              ? null
              : s.callerDisplayText.trim(),
          equipmentText: equipTrim.isEmpty ? null : equipTrim,
          departmentText: s.departmentText.trim().isEmpty
              ? null
              : s.departmentText.trim(),
        );
        final createdDeptNow = deptTextRaw.isNotEmpty && !departmentExistedBefore;
        final lines = <String>[];
        final fullName =
            (state.selectedCaller?.name ?? state.callerDisplayText).trim();
        final deptSuffix =
            deptTextRaw.isNotEmpty ? ' στο τμήμα: $deptTextRaw' : '';
        lines.add('Δημιουργήθηκε νέος χρήστης $fullName$deptSuffix');
        if (createdDeptNow) {
          lines.add('Δημιουργήθηκε νέο τμήμα: $deptTextRaw');
        }
        if (phone != null && phone.isNotEmpty) {
          lines.add(
            phoneExistedBefore
                ? 'Συσχετίστηκε τηλέφωνο: $phone'
                : 'Δημιουργήθηκε νέο τηλέφωνο: $phone',
          );
        }
        if (equipmentCode.isNotEmpty) {
          lines.add(
            equipmentExistedBefore
                ? 'Συσχετίστηκε εξοπλισμός: $equipmentCode'
                : 'Δημιουργήθηκε νέος εξοπλισμός: $equipmentCode',
          );
        }
        // Αν υπάρχει επιπλέον "τεχνικό" tooltip μήνυμα, το αφήνουμε στο τέλος ως περίληψη.
        final summary = msg?.trim();
        if (summary != null && summary.isNotEmpty) {
          lines.add(summary);
        }
        return lines.join('\n');
      } catch (e) {
        return 'Σφάλμα αποθήκευσης: $e';
      }
    }

    if (state.selectedCaller?.id == null) return null;
    final userId = state.selectedCaller!.id!;
    final phone = state.hasPhoneAssociation
        ? null
        : state.selectedPhone?.trim();
    final eqCode = state.hasEquipmentAssociation(lookupForAssoc)
        ? null
        : state.equipmentText.trim();
    final hadPhoneWork = phone != null && phone.isNotEmpty;
    final hadEqWork = eqCode != null && eqCode.isNotEmpty;
    final newPhoneRow =
        hadPhoneWork && !await directory.phoneNumberExists(phone);
    final newEquipmentRow =
        hadEqWork && !await directory.equipmentCodeExists(eqCode);
    final deptTrimAssoc = state.departmentText.trim();
    final willCreateDept =
        updatePrimaryDepartment && deptTrimAssoc.isNotEmpty;
    final newDepartmentRow =
        willCreateDept && !await directory.departmentNameExists(deptTrimAssoc);
    final newEntityEligible =
        newPhoneRow || newEquipmentRow || newDepartmentRow;

    try {
      await directory.updateAssociationsIfNeeded(
        userId,
        phone,
        eqCode?.isNotEmpty == true ? eqCode : null,
      );

      final lookup = ref.read(lookupServiceProvider).value?.service;
      var selectedDepartmentId =
          state.selectedDepartmentId ??
          (state.departmentText.trim().isNotEmpty && lookup != null
              ? lookup.findDepartmentByName(state.departmentText)?.id
              : null);
      var updatedDepartmentId = state.selectedCaller?.departmentId;
      var primaryDepartmentChanged = false;
      if (updatePrimaryDepartment &&
          state.departmentText.trim().isNotEmpty &&
          state.selectedCaller?.id != null) {
        // Αν το τμήμα δεν υπάρχει ακόμα στη βάση, το δημιουργούμε ώστε να πάρουμε id.
        selectedDepartmentId ??= await directory
            .getOrCreateDepartmentIdByName(state.departmentText.trim());
      }

      if (updatePrimaryDepartment &&
          selectedDepartmentId != null &&
          selectedDepartmentId != state.selectedCaller?.departmentId &&
          state.selectedCaller?.id != null) {
        final updatedMap = Map<String, dynamic>.from(
          state.selectedCaller!.toMap(),
        );
        updatedMap['department_id'] = selectedDepartmentId;
        await directory.updateUser(
          state.selectedCaller!.id!,
          updatedMap,
        );
        updatedDepartmentId = selectedDepartmentId;
        primaryDepartmentChanged = true;
      }

      final s = state;
      final phoneNow = s.hasPhoneAssociation ? null : s.selectedPhone?.trim();
      final currentPhones = List<String>.from(s.selectedCaller?.phones ?? const []);
      List<String> updatedPhones = currentPhones;
      if (phoneNow != null && phoneNow.isNotEmpty) {
        final joined = PhoneListParser.joinPhones(currentPhones);
        if (!PhoneListParser.containsPhone(joined, phoneNow)) {
          updatedPhones = [...currentPhones, phoneNow];
        }
      }
      state = state.copyWith(
        selectedCaller: UserModel(
          id: s.selectedCaller?.id,
          firstName: s.selectedCaller?.firstName,
          lastName: s.selectedCaller?.lastName,
          phones: updatedPhones,
          departmentId: updatedDepartmentId,
          notes: s.selectedCaller?.notes,
        ),
        selectedEquipment: eqCode?.isNotEmpty == true
            ? EquipmentModel(
                id: s.selectedEquipment?.id,
                code: eqCode,
                type: s.selectedEquipment?.type,
                notes: s.selectedEquipment?.notes,
              )
            : s.selectedEquipment,
        phoneIsManual: false,
        callerIsManual: false,
        equipmentIsManual: false,
      );

      ref.invalidate(lookupServiceProvider);
      final refreshedLookup = (await ref.read(lookupServiceProvider.future)).service;
      final matchedEquipment = eqCode?.isNotEmpty == true
          ? refreshedLookup.findEquipmentsByCode(eqCode!)
          : const <EquipmentModel>[];
      final resolvedEquipmentId = matchedEquipment.isNotEmpty
          ? matchedEquipment.first.id
          : s.selectedEquipment?.id;
      final resolvedDepartmentId = selectedDepartmentId ??
          (s.departmentText.trim().isNotEmpty
              ? refreshedLookup.findDepartmentByName(s.departmentText)?.id
              : null);
      if (matchedEquipment.isNotEmpty) {
        state = state.copyWith(selectedEquipment: matchedEquipment.first);
      }
      await _syncAssociationQuickTask(
        newEntityEligible: newEntityEligible,
        associationWorkDone:
            hadPhoneWork || hadEqWork || primaryDepartmentChanged,
        summaryText: msg,
        callerName: s.selectedCaller?.name ?? s.callerDisplayText.trim(),
        callerId: s.selectedCaller?.id,
        departmentId: resolvedDepartmentId,
        equipmentId: resolvedEquipmentId,
        phoneText: s.selectedPhone?.trim(),
        userText: s.callerDisplayText.trim().isEmpty
            ? null
            : s.callerDisplayText.trim(),
        equipmentText: s.equipmentText.trim().isEmpty
            ? null
            : s.equipmentText.trim(),
        departmentText: s.departmentText.trim().isEmpty
            ? null
            : s.departmentText.trim(),
      );
      return (hadPhoneWork || hadEqWork || primaryDepartmentChanged)
          ? (msg ?? 'Προστέθηκε.')
          : null;
    } catch (e) {
      return 'Σφάλμα αποθήκευσης: $e';
    }
  }

  /// Μία γρήγορη εκκρεμότητα ανά κύκλο: δημιουργία ή append/merge στην υπάρχουσα.
  Future<void> _syncAssociationQuickTask({
    required bool newEntityEligible,
    required bool associationWorkDone,
    required String? summaryText,
    required String? callerName,
    required int? callerId,
    required int? departmentId,
    required int? equipmentId,
    String? phoneText,
    String? userText,
    String? equipmentText,
    String? departmentText,
  }) async {
    final taskService = ref.read(taskServiceProvider);
    final summary = summaryText?.trim();
    final hasSummary = summary != null && summary.isNotEmpty;
    final existingId = _associationQuickTaskId;

    if (existingId != null) {
      var touched = false;
      if (hasSummary && (newEntityEligible || associationWorkDone)) {
        final appended = await taskService.appendToQuickAddDescription(
          existingId,
          summary,
        );
        if (appended) touched = true;
      }
      final merged = await taskService.mergeQuickAddEntitySnapshot(
        taskId: existingId,
        callerId: callerId,
        departmentId: departmentId,
        equipmentId: equipmentId,
        phoneText: phoneText,
        userText: userText,
        equipmentText: equipmentText,
        departmentText: departmentText,
      );
      if (merged) touched = true;
      if (touched) ref.invalidate(tasksProvider);
      return;
    }

    if (!newEntityEligible) return;

    final id = await _insertQuickAddTask(
      callerName: callerName,
      summaryText: summaryText,
      callerId: callerId,
      departmentId: departmentId,
      equipmentId: equipmentId,
      phoneText: phoneText,
      userText: userText,
      equipmentText: equipmentText,
      departmentText: departmentText,
    );
    _associationQuickTaskId = id;
    ref.invalidate(tasksProvider);
  }

  Future<int> _insertQuickAddTask({
    required String? callerName,
    required String? summaryText,
    required int? callerId,
    required int? departmentId,
    required int? equipmentId,
    String? phoneText,
    String? userText,
    String? equipmentText,
    String? departmentText,
  }) async {
    final cleanSummary = summaryText?.trim();
    final caller = callerName?.trim();
    final descriptionCore = cleanSummary?.isNotEmpty == true
        ? cleanSummary!
        : (caller?.isNotEmpty == true
              ? 'Ενημερώθηκε οντότητα καλούντα'
              : 'Quick add');
    final quickDescription = '${Task.quickAddTag} $descriptionCore';
    return ref.read(taskServiceProvider).createFromCall(
      callId: null,
      callerName: caller,
      description: quickDescription,
      callDate: DateTime.now(),
      callerId: callerId,
      equipmentId: equipmentId,
      departmentId: departmentId,
      phoneId: null,
      phoneText: phoneText?.isEmpty == true ? null : phoneText,
      userText: userText?.isEmpty == true ? null : userText,
      equipmentText: equipmentText?.isEmpty == true ? null : equipmentText,
      departmentText: departmentText?.isEmpty == true ? null : departmentText,
      priority: _criticalTaskPriority,
      categoryName: Task.quickAddCategoryEl,
    );
  }
}

/// Κατάσταση έξυπνου επιλογέα για τη φόρμα **Κλήσεων** (ξεχωριστό instance από Tasks).
final callSmartEntityProvider =
    NotifierProvider<SmartEntitySelectorNotifier, SmartEntitySelectorState>(
      SmartEntitySelectorNotifier.new,
    );

/// Κατάσταση έξυπνου επιλογέα για φόρμες **Εκκρεμοτήτων** / άλλες οθόνες.
final taskSmartEntityProvider =
    NotifierProvider<SmartEntitySelectorNotifier, SmartEntitySelectorState>(
      SmartEntitySelectorNotifier.new,
    );
