import 'dart:io';

import 'package:call_logger/core/services/core_lexicon_validation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('validateCoreDictionaryFile rejects non-txt', () async {
    final dir = await Directory.systemTemp.createTemp('lexicon_val_');
    final f = File('${dir.path}/words.dat');
    await f.writeAsString('hello\n');
    addTearDown(() => dir.delete(recursive: true));

    final err = await validateCoreDictionaryFile(f.path);
    expect(err, isNotNull);
    expect(err, contains('.txt'));
  });

  test('validateCoreDictionaryFile accepts one valid line', () async {
    final dir = await Directory.systemTemp.createTemp('lexicon_val_');
    final f = File('${dir.path}/words.txt');
    await f.writeAsString('# comment\nαβ\n');
    addTearDown(() => dir.delete(recursive: true));

    final err = await validateCoreDictionaryFile(f.path);
    expect(err, isNull);
  });

  test('validateCoreDictionaryFile rejects empty file', () async {
    final dir = await Directory.systemTemp.createTemp('lexicon_val_');
    final f = File('${dir.path}/empty.txt');
    await f.writeAsString('');
    addTearDown(() => dir.delete(recursive: true));

    final err = await validateCoreDictionaryFile(f.path);
    expect(err, isNotNull);
  });
}
