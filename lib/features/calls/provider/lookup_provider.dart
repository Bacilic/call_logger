import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_init_result.dart';
import '../../../core/services/lookup_service.dart';

/// Αποτέλεσμα φόρτωσης in-memory καταλόγου (χρήστες / εξοπλισμός).
///
/// Σε αποτυχία φόρτωσης το [service] παραμένει χρησιμοποιήσιμο (κενό cache)
/// και το [loadError] περιγράφει το πρόβλημα για UI + επαναδοκιμή.
class LookupLoadResult {
  const LookupLoadResult({required this.service, this.loadError});

  final LookupService service;
  final String? loadError;

  bool get isCatalogReady => loadError == null;
}

/// Provider που φορτώνει το [LookupService] μία φορά κατά το init.
final lookupServiceProvider = FutureProvider<LookupLoadResult>((ref) async {
  final service = LookupService.instance;
  service.resetForReload();
  try {
    await service.loadFromDatabase();
    return LookupLoadResult(service: service);
  } catch (e, st) {
    final mapped = DatabaseInitResult.fromException(e, null, st);
    return LookupLoadResult(
      service: service,
      loadError:
          mapped.message ??
          mapped.details ??
          'Αποτυχία φόρτωσης καταλόγου χρηστών/εξοπλισμού.',
    );
  }
});
