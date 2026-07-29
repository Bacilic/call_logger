import 'dart:io';

import 'package:call_logger/core/utils/picker_location_memory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('picker_memory_test_');
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('PickerLocationMemory.initialDirectory', () {
    test('ρητό hint πεδίου κερδίζει τον αποθηκευμένο φάκελο', () async {
      const memory = PickerLocationMemory('demo');
      final hintFile = File(p.join(tempDir.path, 'hospital.db'));
      await hintFile.writeAsString('x');
      await memory.remember(p.join(tempDir.path, 'άσχετο', 'παλιό.txt'));

      final dir = await memory.initialDirectory(pathHint: hintFile.path);

      expect(dir, p.normalize(tempDir.path));
    });

    test(
      'χωρίς hint επιστρέφεται ο αποθηκευμένος φάκελος αν υπάρχει',
      () async {
        const memory = PickerLocationMemory('demo');
        final picked = File(p.join(tempDir.path, 'κάτοψη.png'));
        await picked.writeAsString('x');
        await memory.remember(picked.path);

        final dir = await memory.initialDirectory();

        expect(dir, p.normalize(tempDir.path));
      },
    );

    test('αποθηκευμένος φάκελος που δεν υπάρχει πια δίνει null '
        '(προεπιλογή Windows)', () async {
      const memory = PickerLocationMemory('demo');
      final ghost = Directory(p.join(tempDir.path, 'ghost'));
      await ghost.create();
      await memory.remember(p.join(ghost.path, 'αρχείο.txt'));
      await ghost.delete();

      expect(await memory.initialDirectory(), isNull);
    });

    test('χωρίς hint και χωρίς μνήμη δίνει null', () async {
      const memory = PickerLocationMemory('demo');
      expect(await memory.initialDirectory(), isNull);
    });

    test(
      'κάθε λειτουργία έχει δική της μνήμη — δεν μολύνει τις άλλες',
      () async {
        const imageMemory = PickerLocationMemory('building_map_image');
        const lexiconMemory = PickerLocationMemory('lexicon_txt');
        final picked = File(p.join(tempDir.path, 'κάτοψη.png'));
        await picked.writeAsString('x');
        await imageMemory.remember(picked.path);

        expect(await imageMemory.initialDirectory(), p.normalize(tempDir.path));
        expect(await lexiconMemory.initialDirectory(), isNull);
      },
    );
  });

  group('PickerLocationMemory.remember', () {
    test('κενή διαδρομή αγνοείται σιωπηλά', () async {
      const memory = PickerLocationMemory('demo');
      await memory.remember('   ');
      expect(await memory.initialDirectory(), isNull);
    });
  });
}
