import 'package:call_logger/core/utils/windows1253_encoder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Windows1253Encoder', () {
    test('maps Greek and guillemets to official CP1253 bytes', () {
      expect(Windows1253Encoder.encode('Α'), [0xC1]);
      expect(Windows1253Encoder.encode('Ω'), [0xD9]);
      expect(Windows1253Encoder.encode('α'), [0xE1]);
      expect(Windows1253Encoder.encode('ω'), [0xF9]);
      expect(Windows1253Encoder.encode('ό'), [0xFC]);
      expect(Windows1253Encoder.encode('ή'), [0xDE]);
      expect(Windows1253Encoder.encode('«'), [0xAB]);
      expect(Windows1253Encoder.encode('»'), [0xBB]);
    });

    test('ASCII characters remain byte-identical', () {
      const ascii = r'''@echo off
chcp 1253 >nul
set /p "X=ok"''';
      final bytes = Windows1253Encoder.encode(ascii);
      expect(bytes, ascii.codeUnits);
    });

    test('rejects characters outside Windows-1253', () {
      expect(
        () => Windows1253Encoder.encode('🙂'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
