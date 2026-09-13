// Ποια καρτέλα ανοίγει όταν μια οθόνη ζητά τις «Ρυθμίσεις βάσης».
//
// Ο δείκτης ταξιδεύει ως αριθμός από τον καλούντα ως τον διάλογο. Αν κάποτε
// αναδιαταχθούν οι καρτέλες, ο χειριστής θα κατέληγε σιωπηλά σε λάθος οθόνη —
// καμία εξαίρεση, κανένα κόκκινο, απλώς λάθος μέρος.
//
//   flutter test test/core/providers/database_settings_tab_routing_test.dart

import 'package:call_logger/core/providers/database_settings_route_intent_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('η σειρά των καρτελών', () {
    test('είναι αυτή που βλέπει ο χειριστής', () {
      expect(DatabaseSettingsTab.values.map((t) => t.label).toList(), [
        'Βάση',
        'Αντίγραφα ασφαλείας',
        'Επαναφορά',
        'Συντήρηση',
      ]);
    });

    test('κάθε καρτέλα κρατά τη θέση της', () {
      expect(DatabaseSettingsTab.database.index, 0);
      expect(DatabaseSettingsTab.backups.index, 1);
      expect(DatabaseSettingsTab.restore.index, 2);
      expect(DatabaseSettingsTab.maintenance.index, 3);
    });
  });

  group('το αίτημα φτάνει στο κέλυφος', () {
    test('ζητώντας καρτέλα με το όνομά της, στέλνεται η θέση της', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container
          .read(databaseSettingsRouteIntentProvider.notifier)
          .open(DatabaseSettingsTab.backups);

      expect(
        container.read(databaseSettingsRouteIntentProvider)?.tabIndex,
        DatabaseSettingsTab.backups.index,
      );
    });

    test('δύο αιτήματα για την ΙΔΙΑ καρτέλα ξεχωρίζουν', () {
      // Χωρίς αυτό, το δεύτερο πάτημα δεν θα άνοιγε τίποτα: το κέλυφος ακούει
      // αλλαγές κατάστασης, και δύο ίδια αιτήματα θα φαίνονταν ένα.
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(
        databaseSettingsRouteIntentProvider.notifier,
      );

      notifier.open(DatabaseSettingsTab.database);
      final first = container.read(databaseSettingsRouteIntentProvider);
      notifier.open(DatabaseSettingsTab.database);
      final second = container.read(databaseSettingsRouteIntentProvider);

      expect(first?.tabIndex, second?.tabIndex);
      expect(first?.sequence, isNot(second?.sequence));
    });
  });
}
