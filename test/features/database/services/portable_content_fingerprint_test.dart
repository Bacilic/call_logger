// Το αποτύπωμα των φορητών (Φάση 5): ντετερμινιστικό, ευαίσθητο σε κάθε
// αλλαγή ονόματος/μεγέθους/ώρας/είδους, αναίσθητο στη σειρά ανάγνωσης.
//
//   flutter test test/features/database/services/portable_content_fingerprint_test.dart

import 'package:call_logger/features/database/services/portable_content_fingerprint.dart';
import 'package:flutter_test/flutter_test.dart';

PortableFingerprintEntry _entry(
  String kind,
  String name, {
  int size = 100,
  int mtime = 1000,
}) => PortableFingerprintEntry(
  kind: kind,
  name: name,
  sizeBytes: size,
  modifiedMs: mtime,
);

void main() {
  test('ίδιο περιεχόμενο, άλλη σειρά ανάγνωσης → ίδιο αποτύπωμα', () {
    final a = PortableContentFingerprint.digestOf([
      _entry('maps', 'a.png'),
      _entry('images', 'b.png'),
    ]);
    final b = PortableContentFingerprint.digestOf([
      _entry('images', 'b.png'),
      _entry('maps', 'a.png'),
    ]);
    expect(a, b, reason: 'Η σειρά του δίσκου δεν είναι εγγύηση.');
  });

  test('αλλαγή μεγέθους, ώρας ή ονόματος αλλάζει το αποτύπωμα', () {
    final base = PortableContentFingerprint.digestOf([_entry('maps', 'a.png')]);
    expect(
      PortableContentFingerprint.digestOf([_entry('maps', 'a.png', size: 101)]),
      isNot(base),
    );
    expect(
      PortableContentFingerprint.digestOf([
        _entry('maps', 'a.png', mtime: 2000),
      ]),
      isNot(base),
    );
    expect(
      PortableContentFingerprint.digestOf([_entry('maps', 'b.png')]),
      isNot(base),
    );
  });

  test('προσθήκη ή αφαίρεση αρχείου αλλάζει το αποτύπωμα', () {
    final one = PortableContentFingerprint.digestOf([_entry('maps', 'a.png')]);
    final two = PortableContentFingerprint.digestOf([
      _entry('maps', 'a.png'),
      _entry('maps', 'b.png'),
    ]);
    expect(one, isNot(two));
  });

  test('ίδιο αρχείο σε άλλο είδος = άλλο αποτύπωμα — μετρά και η επιλογή '
      'των διακοπτών', () {
    expect(
      PortableContentFingerprint.digestOf([_entry('maps', 'a.png')]),
      isNot(PortableContentFingerprint.digestOf([_entry('images', 'a.png')])),
    );
  });

  test('κενό περιεχόμενο έχει σταθερό, μη κενό αποτύπωμα', () {
    final empty = PortableContentFingerprint.digestOf(const []);
    expect(empty, isNotEmpty);
    expect(PortableContentFingerprint.digestOf(const []), empty);
  });
}
