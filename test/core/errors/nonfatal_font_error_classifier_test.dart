import 'package:call_logger/core/errors/nonfatal_font_error_classifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isNonFatalFontLoadError', () {
    test(
      'Περίπτωση Α: Unable to load Inter-Regular.ttf + google_fonts stack → true',
      () {
        final error = Exception(
          'Unable to load asset: "assets/fonts/Inter-Regular.ttf".',
        );
        final stack = StackTrace.fromString(
          '#0      loadFontIfNecessary '
          '(package:google_fonts/src/google_fonts_base.dart:123:5)\n'
          '#1      main (file:///app/lib/main.dart:224:5)\n',
        );

        expect(isNonFatalFontLoadError(error, stack), isTrue);
      },
    );

    test(
      'Περίπτωση Β: Unable to load NativeAssetsManifest.json χωρίς font → false',
      () {
        final error = StateError(
          'Unable to load asset: NativeAssetsManifest.json',
        );
        final stack = StackTrace.fromString(
          '#0      AssetBundle.load (package:flutter/src/services/asset_bundle.dart:1:1)\n',
        );

        expect(isNonFatalFontLoadError(error, stack), isFalse);
      },
    );

    test('Περίπτωση Γ: άσχετο StateError → false', () {
      final error = StateError('No element');

      expect(isNonFatalFontLoadError(error), isFalse);
    });
  });
}
