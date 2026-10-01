import '../../../core/services/settings_service.dart';
import '../models/catalog_accepted_findings.dart';

/// Ανάγνωση και αλλαγή των αποδεκτών ευρημάτων του «Ελέγχου δεδομένων».
///
/// Κάθε αλλαγή εφαρμόζεται πάνω σε ό,τι είναι **τώρα** στη βάση, και
/// επιστρέφει ό,τι όντως αποθηκεύτηκε — μαζί και τις αποφάσεις άλλου σταθμού.
class CatalogFindingAcceptance {
  const CatalogFindingAcceptance._();

  static Future<CatalogAcceptedFindings> load() async =>
      CatalogAcceptedFindings.fromRawJson(
        await SettingsService().catalogs.getCatalogAcceptedFindingsRaw(),
      );

  static Future<CatalogAcceptedFindings> accept(String key) =>
      _update((current) => current.withKey(key));

  static Future<CatalogAcceptedFindings> restore(String key) =>
      _update((current) => current.withoutKey(key));

  static Future<CatalogAcceptedFindings> _update(
    CatalogAcceptedFindings Function(CatalogAcceptedFindings current) change,
  ) async {
    final stored = await SettingsService().catalogs
        .updateCatalogAcceptedFindingsRaw(
          (raw) => change(CatalogAcceptedFindings.fromRawJson(raw)).toRawJson(),
        );
    return CatalogAcceptedFindings.fromRawJson(stored);
  }
}
