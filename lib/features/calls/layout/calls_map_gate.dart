import '../../../core/services/lookup_service.dart';
import '../models/user_model.dart';
import '../provider/smart_entity_selector_provider.dart';
import 'calls_field_confirmations.dart';

/// Πύλη ορατότητας κάρτας Χάρτη (ΧΑ) στην οθόνη κλήσεων.
class CallsMapGate {
  const CallsMapGate._();

  /// ΧΑ ενεργό όταν υπάρχει επιλεγμένο τμήμα/καλών/εξοπλισμός ή όταν το
  /// **επιβεβαιωμένο** τηλέφωνο αντιστοιχεί ακριβώς σε **χαρτογραφημένο** τμήμα.
  ///
  /// Εξαίρεση: εταιρεία και εξωτερική μονάδα δεν βρίσκονται σε δικό μας κτίριο
  /// και δεν πρόκειται ποτέ να αποκτήσουν θέση. Η κάρτα δεν κρύβεται επειδή
  /// «δεν βρέθηκε» κάτι — δεν έχει νόημα εξαρχής, οπότε φεύγει ολόκληρη αντί να
  /// πιάνει χώρο για να πει «δεν υπάρχει στον χάρτη».
  static bool isMapActive(
    SmartEntitySelectorState header,
    LookupService? lookup, [
    CallsFieldConfirmations confirmations = CallsFieldConfirmations.empty,
  ]) {
    if (header.selectedDepartmentId != null) {
      return _belongsOnMap(lookup, header.selectedDepartmentId);
    }
    if (header.selectedEquipment?.id != null) {
      return _belongsOnMap(lookup, header.selectedEquipment?.departmentId);
    }
    if (header.selectedCaller?.id != null) {
      return _belongsOnMap(lookup, header.selectedCaller?.departmentId);
    }
    if (lookup == null) return false;
    final phone = header.selectedPhone?.trim() ?? '';
    if (phone.isEmpty || !confirmations.phone) return false;
    return phoneResolvesToMappedDepartment(lookup, phone);
  }

  /// Χωρίς κατάλογο δεν ξέρουμε είδος: η κάρτα μένει ορατή, όπως πάντα.
  /// Οντότητα χωρίς τμήμα (π.χ. καλών χωρίς τμήμα) κρίνεται ως νοσοκομείο —
  /// η συμπεριφορά που ίσχυε πριν υπάρξει το «Είδος».
  static bool _belongsOnMap(LookupService? lookup, int? departmentId) {
    if (lookup == null) return true;
    return lookup.departmentKindById(departmentId).belongsOnBuildingMap;
  }

  static bool phoneResolvesToMappedDepartment(
    LookupService lookup,
    String phone,
  ) {
    for (final deptId in departmentIdsForPhone(lookup, phone)) {
      if (isDepartmentMapped(lookup, deptId)) return true;
    }
    return false;
  }

  static List<int> departmentIdsForPhone(LookupService lookup, String phone) {
    final seen = <int>{};
    final out = <int>[];

    void add(int? id) {
      if (id != null && seen.add(id)) out.add(id);
    }

    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    add(lookup.checkPhoneUsage(phone).departmentId);
    for (final u in lookup.findUsersByPhone(phone)) {
      if (_userHasExactPhone(u, digits)) add(u.departmentId);
    }
    for (final d in lookup.departments) {
      final id = d.id;
      if (id == null) continue;
      final direct = d.directPhones ?? const <String>[];
      for (final p in direct) {
        if (_phonesMatch(p, phone)) {
          add(id);
          break;
        }
      }
    }
    return out;
  }

  static bool isDepartmentMapped(LookupService lookup, int deptId) {
    for (final d in lookup.departments) {
      if (d.id == deptId) return d.isMapped;
    }
    return false;
  }

  static bool _userHasExactPhone(UserModel user, String digits) {
    if (digits.isEmpty) return false;
    for (final raw in user.phones) {
      final pd = raw.replaceAll(RegExp(r'[^0-9]'), '');
      if (pd.isNotEmpty && pd == digits) return true;
    }
    return false;
  }

  static bool _phonesMatch(String a, String b) {
    final ta = a.trim();
    final tb = b.trim();
    if (ta.isEmpty || tb.isEmpty) return false;
    if (ta == tb) return true;
    final da = ta.replaceAll(RegExp(r'[^0-9]'), '');
    final db = tb.replaceAll(RegExp(r'[^0-9]'), '');
    return da.isNotEmpty && da == db;
  }
}
