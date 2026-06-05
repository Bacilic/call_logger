import 'package:call_logger/core/widgets/lexicon_spell_menu_helper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LexiconSpellMenuHelper.googleSpellSearchUri', () {
    test('ορθογραφία + λέξη στο query', () {
      final uri = LexiconSpellMenuHelper.googleSpellSearchUri('Επιλιμένος');
      expect(uri.host, 'www.google.com');
      expect(uri.path, '/search');
      expect(uri.queryParameters['q'], 'ορθογραφία "Επιλιμένος"');
    });
  });
}
