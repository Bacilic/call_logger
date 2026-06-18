import 'package:call_logger/core/providers/core_lexicon_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dictionary nav hidden when spell check off', () {
    expect(
      isDictionaryNavVisible(
        enableSpellCheck: false,
        showDictionaryNav: true,
        coreLexiconLoaded: false,
      ),
      isFalse,
    );
  });

  test('dictionary nav visible with warning when core missing', () {
    expect(
      isDictionaryNavVisible(
        enableSpellCheck: true,
        showDictionaryNav: false,
        coreLexiconLoaded: false,
      ),
      isTrue,
    );
  });

  test('dictionary nav respects hide when core loaded', () {
    expect(
      isDictionaryNavVisible(
        enableSpellCheck: true,
        showDictionaryNav: false,
        coreLexiconLoaded: true,
      ),
      isFalse,
    );
  });
}
