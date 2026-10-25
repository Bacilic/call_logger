import '../../../core/services/settings_service.dart';
import 'mass_deletion_guard.dart';

/// Το πλαίσιο της προειδοποίησης για έναν διάλογο διαγραφής: ο κατάλογος, τα
/// ενεργά του στοιχεία και το κοινό ποσοστό της βάσης.
///
/// Μία ανάγνωση για τις τρεις καρτέλες, ώστε καμία να μη διαβάζει τη ρύθμιση
/// με δικό της τρόπο.
Future<MassDeletionContext> loadMassDeletionContext({
  required MassDeletionCatalog catalog,
  required int catalogTotal,
}) async {
  final percent = await SettingsService().catalogs
      .getMassDeletionWarningPercent();
  return MassDeletionContext(
    catalog: catalog,
    catalogTotal: catalogTotal,
    thresholdPercent: percent,
  );
}
