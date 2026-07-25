// Το dropdown διαδρομών βάσης δεν επιτρέπεται να δείχνει ως ενεργή μια βάση
// που δεν είναι ανοιχτή: η ενεργή διαδρομή είναι πάντα μέσα στις επιλογές.
//
//   flutter test test/features/database/utils/database_path_dropdown_options_test.dart

import 'package:call_logger/features/database/utils/database_path_dropdown_options.dart';
import 'package:flutter_test/flutter_test.dart';

const _a = r'C:\Users\Bacilic\Documents\call_logger\DB\call_logger.db';
const _b = r'E:\call logger\data\call_logger.db';
const _c = r'\\server\share\call_logger.db';

void main() {
  group('databasePathDropdownOptions', () {
    test('η ενεργή διαδρομή περιλαμβάνεται πάντα, ακόμη κι αν λείπει από τις '
        'πρόσφατες', () {
      final options = databasePathDropdownOptions(
        currentPath: _c,
        recentPaths: const [_a, _b],
      );

      expect(options, contains(_c));
      expect(options.first, _c, reason: 'η ενεργή μπαίνει πρώτη όταν λείπει');
      expect(options, [_c, _a, _b]);
    });

    test('όταν η ενεργή υπάρχει ήδη, η σειρά των πρόσφατων δεν αλλάζει', () {
      final options = databasePathDropdownOptions(
        currentPath: _b,
        recentPaths: const [_a, _b, _c],
      );

      expect(options, [_a, _b, _c]);
    });

    test('διπλότυπα αφαιρούνται — το DropdownButton απαιτεί μοναδική τιμή', () {
      final options = databasePathDropdownOptions(
        currentPath: _a,
        recentPaths: const [_a, _b, _a],
      );

      expect(options, [_a, _b]);
      expect(options.where((path) => path == _a).length, 1);
    });

    test('χωρίς πρόσφατες διαδρομές, μόνη επιλογή είναι η ενεργή', () {
      final options = databasePathDropdownOptions(
        currentPath: _a,
        recentPaths: const [],
      );

      expect(options, [_a]);
    });

    test('κενή ενεργή διαδρομή (προεπιλογή) παραμένει έγκυρη επιλογή', () {
      final options = databasePathDropdownOptions(
        currentPath: '',
        recentPaths: const [_a],
      );

      expect(options, ['', _a]);
    });
  });
}
