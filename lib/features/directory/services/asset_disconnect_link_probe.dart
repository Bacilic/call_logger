// Τι κρατά ένα στοιχείο πριν καταργηθεί: ερωτήματα στη βάση για τις συνδέσεις
// τηλεφώνου/εξοπλισμού, μακριά από τα widgets του διαλόγου.

import '../../../core/database/database_helper.dart';
import '../../../core/database/equipment_repository.dart';
import '../../../core/database/phone_repository.dart';
import 'asset_disconnect_session.dart';

/// Πηγή περιγραφών σύνδεσης — αντικαθίσταται στα τεστ.
typedef AssetReferenceDescriptionsLookup =
    Future<List<String>> Function({
      required bool isPhone,
      required String value,
    });

/// Πηγή ιστορικών συνδέσεων ανά στοιχείο — αντικαθίσταται στα τεστ.
typedef AssetHistoryLinksLookup =
    Future<AssetHistoryLinks> Function(AssetDisconnectItem item);

/// Οι συνδέσεις ενός στοιχείου, σε αναγνώσιμη μορφή για τον χρήστη.
Future<List<String>> assetReferenceDescriptions({
  required bool isPhone,
  required String value,
}) async {
  final db = await DatabaseHelper.instance.database;
  if (isPhone) {
    final phones = PhoneRepository(db);
    final id = await phones.getPhoneIdByNumber(value);
    if (id == null) return const <String>[];
    return phones.phoneReferenceDescriptions(id, value);
  }
  final equipment = EquipmentRepository(db);
  final id = await equipment.getEquipmentIdByCode(value);
  if (id == null) return const <String>[];
  return equipment.equipmentReferenceDescriptions(id);
}

/// Μόνο το ιστορικό ενός στοιχείου: εκκρεμότητες και κλήσεις.
///
/// Ο κάτοχος και το τμήμα δεν μετρώνται — τα έχει σχεδόν κάθε στοιχείο, οπότε
/// μια προειδοποίηση που τα περιλαμβάνει ισχύει πάντα και δεν λέει τίποτα.
Future<AssetHistoryLinks> assetHistoryLinks(AssetDisconnectItem item) async {
  final db = await DatabaseHelper.instance.database;
  if (item.isPhone) {
    final phones = PhoneRepository(db);
    final id = await phones.getPhoneIdByNumber(item.value);
    if (id == null) return const AssetHistoryLinks();
    final counts = await phones.phoneHistoryLinkCounts(id, item.value);
    return AssetHistoryLinks(tasks: counts.tasks, calls: counts.calls);
  }
  final equipment = EquipmentRepository(db);
  final id = await equipment.getEquipmentIdByCode(item.value);
  if (id == null) return const AssetHistoryLinks();
  final counts = await equipment.equipmentHistoryLinkCounts(id);
  return AssetHistoryLinks(tasks: counts.tasks, calls: counts.calls);
}

/// Το ιστορικό κάθε στοιχείου, με σειρά αντίστοιχη της [items].
Future<List<AssetHistoryLinks>> assetHistoryLinksFor(
  List<AssetDisconnectItem> items, {
  AssetHistoryLinksLookup? lookup,
}) async {
  final probe = lookup ?? assetHistoryLinks;
  final out = <AssetHistoryLinks>[];
  for (final item in items) {
    out.add(await probe(item));
  }
  return out;
}
