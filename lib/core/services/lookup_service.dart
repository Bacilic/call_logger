import '../database/database_helper.dart';
import '../utils/search_text_normalizer.dart';
import '../../features/calls/models/equipment_model.dart';
import '../../features/calls/models/user_model.dart';

/// Αποτέλεσμα αναζήτησης: χρήστης και εξοπλισμός του.
class LookupResult {
  LookupResult({required this.user, required this.equipment});

  final UserModel user;
  final List<EquipmentModel> equipment;
}

/// Υπηρεσία in-memory lookup: φορτώνει Users/Equipment μία φορά, search στη μνήμη.
class LookupService {
  LookupService() : _loaded = false;

  bool _loaded;
  final List<UserModel> _users = [];
  final List<EquipmentModel> _equipment = [];
  Map<int, List<EquipmentModel>> _equipmentByUserId = {};

  /// Φόρτωση από βάση ΜΟΝΟ μία φορά κατά το init.
  Future<void> loadFromDatabase() async {
    if (_loaded) return;
    final db = await DatabaseHelper.instance.database;
    final userMaps = await db.query('users');
    final equipmentMaps = await db.query('equipment');
    _users.clear();
    _equipment.clear();
    for (final map in userMaps) {
      _users.add(UserModel.fromMap(map));
    }
    for (final map in equipmentMaps) {
      _equipment.add(EquipmentModel.fromMap(map));
    }
    _equipmentByUserId = {};
    for (final e in _equipment) {
      if (e.userId != null) {
        _equipmentByUserId.putIfAbsent(e.userId!, () => []).add(e);
      }
    }
    _loaded = true;
  }

  /// Αναζήτηση στη μνήμη βάσει digits (phone). Επιστρέφει αποτέλεσμα μόνο αν query.length >= 3.
  LookupResult? search(String query) {
    final digits = query.trim();
    if (digits.length < 3) return null;
    final lower = digits.toLowerCase();
    for (final u in _users) {
      final phone = (u.phone ?? '').trim().toLowerCase();
      if (phone.contains(lower) || phone.startsWith(lower)) {
        final equipment = _equipmentByUserId[u.id] ?? [];
        return LookupResult(user: u, equipment: equipment);
      }
    }
    return null;
  }

  /// Επιστρέφει τηλέφωνα (από users) που ταιριάζουν με το prefix (ψηφία), όταν prefix.length >= 2.
  /// Χωρίς ταξινόμηση κατά πρόσφατη χρήση (γίνεται στο call_header_provider).
  List<String> searchPhonesByPrefix(String prefix) {
    final digits = _digitsOnly(prefix);
    if (digits.length < 2) return [];
    final lower = digits.toLowerCase();
    final seen = <String>{};
    final result = <String>[];
    for (final u in _users) {
      final phone = (u.phone ?? '').trim();
      if (phone.isEmpty) continue;
      final phoneNorm = phone.toLowerCase();
      if ((phoneNorm.contains(lower) || phoneNorm.startsWith(lower)) &&
          seen.add(phoneNorm)) {
        result.add(phone);
      }
    }
    return result;
  }

  /// Αναζήτηση χρηστών στη μνήμη: name, phone, department περιέχουν το query (case-insensitive).
  List<UserModel> searchUsersByQuery(String query) {
    final q = SearchTextNormalizer.normalizeForSearch(query);
    if (q.isEmpty) return [];
    return _users.where((u) {
      return SearchTextNormalizer.matchesNormalizedQuery(u.name ?? '', q) ||
          SearchTextNormalizer.matchesNormalizedQuery(u.phone ?? '', q) ||
          SearchTextNormalizer.matchesNormalizedQuery(u.department ?? '', q);
    }).toList();
  }

  /// Επιστρέφει εξοπλισμό του χρήστη που αντιστοιχεί στο τηλέφωνο (αν βρεθεί, ≥3 ψηφία).
  List<EquipmentModel> searchEquipmentsByPhone(String phone) {
    final digits = _digitsOnly(phone);
    if (digits.length < 3) return [];
    final result = search(digits);
    if (result == null) return [];
    return _equipmentByUserId[result.user.id] ?? [];
  }

  /// Όλοι οι χρήστες whose phone περιέχει/ταιριάζει με τα ψηφία (≥3). Ταξινόμηση κατά name.
  List<UserModel> findUsersByPhone(String phone) {
    final digits = _digitsOnly(phone);
    if (digits.length < 3) return [];
    final lower = digits.toLowerCase();
    final list = _users
        .where((u) {
          final p = (u.phone ?? '').trim().toLowerCase();
          return p.contains(lower) || p.startsWith(lower);
        })
        .toList();
    list.sort((a, b) => (a.name ?? '').compareTo(b.name ?? ''));
    return list;
  }

  /// Εξοπλισμός που ανήκει στον χρήστη (user_id).
  List<EquipmentModel> findEquipmentsForUser(int userId) {
    return _equipmentByUserId[userId] ?? [];
  }

  static String _digitsOnly(String s) {
    return s.replaceAll(RegExp(r'[^0-9]'), '');
  }
}
