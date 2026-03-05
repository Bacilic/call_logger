import '../database/database_helper.dart';
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
}
