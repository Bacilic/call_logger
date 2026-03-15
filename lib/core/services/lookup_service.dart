import '../database/database_helper.dart';
import '../utils/phone_list_parser.dart';
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

  /// Λίστα χρηστών (μετά loadFromDatabase). Για dropdown κατόχου σε φόρμες.
  List<UserModel> get users => List.unmodifiable(_users);

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

  /// Αναζήτηση στη μνήμη βάσει ψηφίων τηλεφώνου. Κενά/παύλες αγνοούνται και στα δύο μέρη.
  LookupResult? search(String query) {
    final digits = _digitsOnly(query);
    if (digits.length < 3) return null;
    for (final u in _users) {
      final phoneDigits = _digitsOnly(u.phone ?? '');
      if (phoneDigits.isEmpty) continue;
      if (phoneDigits.contains(digits) || phoneDigits.startsWith(digits)) {
        final equipment = _equipmentByUserId[u.id] ?? [];
        return LookupResult(user: u, equipment: equipment);
      }
    }
    return null;
  }

  /// Επιστρέφει τηλέφωνα (από users) που ταιριάζουν με το prefix (ψηφία), όταν prefix.length >= 2.
  /// Κενά/παύλες αγνοούνται· η σύγκριση γίνεται μόνο σε ψηφία.
  List<String> searchPhonesByPrefix(String prefix) {
    final digits = _digitsOnly(prefix);
    if (digits.length < 2) return [];
    final seen = <String>{};
    final result = <String>[];
    for (final u in _users) {
      final phones = PhoneListParser.splitPhones(u.phone);
      for (final phone in phones) {
        final phoneDigits = _digitsOnly(phone);
        if ((phoneDigits.contains(digits) || phoneDigits.startsWith(digits)) &&
            seen.add(phone)) {
          result.add(phone);
        }
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
  /// Κενά/παύλες αγνοούνται και στο input και στο αποθηκευμένο τηλέφωνο.
  List<UserModel> findUsersByPhone(String phone) {
    final digits = _digitsOnly(phone);
    if (digits.length < 3) return [];
    final list = _users
        .where((u) {
          final phoneDigits = _digitsOnly(u.phone ?? '');
          return phoneDigits.isNotEmpty &&
              (phoneDigits.contains(digits) || phoneDigits.startsWith(digits));
        })
        .toList();
    list.sort((a, b) => (a.name ?? '').compareTo(b.name ?? ''));
    return list;
  }

  /// Εξοπλισμός που ανήκει στον χρήστη (user_id).
  List<EquipmentModel> findEquipmentsForUser(int userId) {
    return _equipmentByUserId[userId] ?? [];
  }

  /// Αναζήτηση εξοπλισμών με βάση κωδικό ή label (case-insensitive/normalized).
  /// Επιστρέφει πολλαπλά αποτελέσματα όταν το query ταιριάζει σε περισσότερες εγγραφές.
  List<EquipmentModel> findEquipmentsByCode(String query) {
    final q = SearchTextNormalizer.normalizeForSearch(query);
    if (q.isEmpty) return [];
    final seen = <String>{};
    final exact = <EquipmentModel>[];
    final prefix = <EquipmentModel>[];
    final contains = <EquipmentModel>[];

    bool addOnce(List<EquipmentModel> target, EquipmentModel equipment) {
      final key = (equipment.code?.trim().isNotEmpty == true)
          ? equipment.code!.trim().toLowerCase()
          : equipment.displayLabel.trim().toLowerCase();
      if (!seen.add(key)) return false;
      target.add(equipment);
      return true;
    }

    for (final equipment in _equipment) {
      final code = equipment.code ?? '';
      final label = equipment.displayLabel;
      final normCode = SearchTextNormalizer.normalizeForSearch(code);
      final normLabel = SearchTextNormalizer.normalizeForSearch(label);
      if (normCode.isEmpty && normLabel.isEmpty) {
        continue;
      }

      final isExact = normCode == q;
      final isPrefix =
          normCode.startsWith(q) || (!isExact && normLabel.startsWith(q));
      final isContains =
          normCode.contains(q) || (!isPrefix && normLabel.contains(q));

      if (isExact) {
        addOnce(exact, equipment);
      } else if (isPrefix) {
        addOnce(prefix, equipment);
      } else if (isContains) {
        addOnce(contains, equipment);
      }
    }

    int compareByCodeThenLabel(EquipmentModel a, EquipmentModel b) {
      final ac = (a.code ?? '').toLowerCase();
      final bc = (b.code ?? '').toLowerCase();
      final byCode = ac.compareTo(bc);
      if (byCode != 0) return byCode;
      return a.displayLabel.toLowerCase().compareTo(b.displayLabel.toLowerCase());
    }

    exact.sort(compareByCodeThenLabel);
    prefix.sort(compareByCodeThenLabel);
    contains.sort(compareByCodeThenLabel);
    return [...exact, ...prefix, ...contains];
  }

  /// Αναζήτηση χρήστη by id μέσα από in-memory λίστα.
  UserModel? findUserById(int? userId) {
    if (userId == null) return null;
    for (final user in _users) {
      if (user.id == userId) return user;
    }
    return null;
  }

  static String _digitsOnly(String s) {
    return s.replaceAll(RegExp(r'[^0-9]'), '');
  }
}
