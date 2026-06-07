import 'package:call_logger/core/utils/windows_file_name_validation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('validateWindowsFileName', () {
    test('rejects empty name', () {
      expect(validateWindowsFileName(''), isNotNull);
      expect(validateWindowsFileName('   '), isNotNull);
    });

    test('rejects forbidden characters', () {
      expect(validateWindowsFileName('bad:name.png'), isNotNull);
      expect(validateWindowsFileName(r'path\file.png'), isNotNull);
    });

    test('rejects reserved base names', () {
      expect(validateWindowsFileName('CON.png'), isNotNull);
      expect(validateWindowsFileName('lpt1.jpg'), isNotNull);
    });

    test('accepts normal image names', () {
      expect(validateWindowsFileName('plan_1st_floor.png'), isNull);
      expect(validateWindowsFileName('Κάτοψη 2ος.jpg'), isNull);
    });
  });

  group('resolveImageTargetFileName', () {
    test('adds original extension when missing', () {
      expect(
        resolveImageTargetFileName(
          userInput: 'my_plan',
          originalExtension: '.PNG',
        ),
        'my_plan.png',
      );
    });

    test('keeps user extension when provided', () {
      expect(
        resolveImageTargetFileName(
          userInput: 'my_plan.webp',
          originalExtension: '.jpg',
        ),
        'my_plan.webp',
      );
    });
  });
}
