import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_error_advice.dart';
import '../../../core/database/database_init_result.dart';
import '../../../core/services/lookup_service.dart';

/// Αποτέλεσμα φόρτωσης in-memory καταλόγου (χρήστες / εξοπλισμός).
///
/// Σε αποτυχία φόρτωσης το [service] παραμένει χρησιμοποιήσιμο (κενό cache)
/// και το [loadError] περιγράφει το πρόβλημα για UI + επαναδοκιμή.
/// Το [loadErrorDetails] (λεπτομέρειες / αρχικό μήνυμα) εμφανίζεται κάτω από το banner.
class LookupLoadResult {
  const LookupLoadResult({
    required this.service,
    this.loadError,
    this.loadErrorDetails,
  });

  /// Μεταφράζει την αποτυχία φόρτωσης σε κείμενο για τη λωρίδα.
  ///
  /// Ζει εδώ και όχι μέσα στο σώμα του provider ώστε να ελέγχεται: ό,τι
  /// διαβάζει ο χειριστής στην κόκκινη λωρίδα της φόρμας κλήσης βγαίνει από
  /// αυτή τη συνάρτηση, και μόνο από αυτήν.
  factory LookupLoadResult.fromError(
    LookupService service,
    Object error,
    StackTrace stackTrace,
  ) {
    final mapped = DatabaseInitResult.fromException(error, null, stackTrace);
    return LookupLoadResult(
      service: service,
      loadError:
          mapped.message ??
          mapped.details ??
          'Αποτυχία φόρτωσης καταλόγου χρηστών/εξοπλισμού.',
      // Ο χειριστής δεν διάλεξε αρχείο — άνοιξε την εφαρμογή και πήγε να
      // δουλέψει. Η συμβουλή πρέπει να μιλά γι' αυτό.
      loadErrorDetails: databaseErrorAdvice(
        result: mapped,
        moment: DatabaseErrorMoment.usingTheApp,
      ),
    );
  }

  final LookupService service;
  final String? loadError;
  final String? loadErrorDetails;

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
    return LookupLoadResult.fromError(service, e, st);
  }
});
