import 'package:call_logger/core/database/database_switch_success_notice.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('topDatabaseBanner', () {
    test(
      'κίτρινη υπερισχύει όταν πρέπει να φανεί ΚΑΙ υπάρχει μήνυμα επιτυχίας',
      () {
        expect(
          topDatabaseBanner(showStateNotice: true, hasSwitchSuccess: true),
          TopDatabaseBanner.warning,
        );
      },
    );

    test(
      'μόνο επιτυχία → success, μόνο κίτρινη → warning, κανένα → none',
      () {
        expect(
          topDatabaseBanner(showStateNotice: false, hasSwitchSuccess: true),
          TopDatabaseBanner.success,
        );
        expect(
          topDatabaseBanner(showStateNotice: true, hasSwitchSuccess: false),
          TopDatabaseBanner.warning,
        );
        expect(
          topDatabaseBanner(showStateNotice: false, hasSwitchSuccess: false),
          TopDatabaseBanner.none,
        );
      },
    );
  });

  group('databaseSwitchSuccessNoticeProvider', () {
    test('ξεκινά null· show θέτει μήνυμα με φράση και διαδρομή· clear μηδενίζει',
        () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(databaseSwitchSuccessNoticeProvider), isNull);

      const path = r'C:\data\call_logger.db';
      container
          .read(databaseSwitchSuccessNoticeProvider.notifier)
          .show(path);

      final message = container.read(databaseSwitchSuccessNoticeProvider);
      expect(message, isNotNull);
      expect(message, contains('Έγινε με επιτυχία η αλλαγή βάσης'));
      expect(message, contains(path));

      container.read(databaseSwitchSuccessNoticeProvider.notifier).clear();
      expect(container.read(databaseSwitchSuccessNoticeProvider), isNull);
    });

    test('δεύτερη show αντικαθιστά το προηγούμενο μήνυμα', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      const first =
          r'F:\flutter_projects\call_logger\Data Base\Δοκιμές\μόνο_κλήσεις.db';
      const second =
          r'C:\Users\Bacilic\Documents\call_logger\DB\call_logger.db';

      final notifier =
          container.read(databaseSwitchSuccessNoticeProvider.notifier);
      notifier.show(first);
      expect(
        container.read(databaseSwitchSuccessNoticeProvider),
        databaseSwitchSuccessMessage(first),
      );

      notifier.show(second);
      final message = container.read(databaseSwitchSuccessNoticeProvider);
      expect(message, databaseSwitchSuccessMessage(second));
      expect(message, isNot(contains(first)));
      expect(message, contains(second));
    });
  });
}
