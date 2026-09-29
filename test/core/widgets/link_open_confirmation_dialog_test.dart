import 'package:call_logger/core/widgets/link_open_confirmation_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('uncServerName', () {
    test('βγάζει το όνομα του υπολογιστή από πλήρη διαδρομή', () {
      expect(uncServerName(r'\\XENOS-PC\share\file.txt'), 'XENOS-PC');
    });

    test('δέχεται και διαδρομή με κάθετους', () {
      expect(uncServerName('//192.168.1.83/logs'), '192.168.1.83');
    });

    test('σκέτο όνομα υπολογιστή χωρίς κοινόχρηστο', () {
      expect(uncServerName(r'\\SERVER'), 'SERVER');
    });

    test('χωρίς όνομα υπολογιστή δίνει null', () {
      expect(uncServerName(r'\\'), isNull);
    });
  });
}
