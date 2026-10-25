// Πότε μια διαγραφή καταλόγου προειδοποιεί: όριο ποσοστού, όριο των 50
// στοιχείων, ολόκληρος κατάλογος και η λέξη «ΔΙΑΓΡΑΦΗ».
//
//   flutter test test/features/directory/services/mass_deletion_guard_test.dart

import 'package:call_logger/features/directory/services/mass_deletion_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  MassDeletionLevel level(int deleting, int total, {int percent = 50}) =>
      massDeletionLevel(
        deleting: deleting,
        catalogTotal: total,
        thresholdPercent: percent,
      );

  group('όριο ποσοστού (κατάλογος 115 υπαλλήλων, 50%)', () {
    test('58 από 115 φτάνουν το μισό: προειδοποίηση', () {
      expect(level(58, 115), MassDeletionLevel.share);
    });

    test('57 από 115 μένουν κάτω από το μισό: τίποτα', () {
      expect(level(57, 115), MassDeletionLevel.none);
    });

    test('το ρυθμισμένο ποσοστό μετακινεί το όριο', () {
      expect(level(35, 115, percent: 30), MassDeletionLevel.share);
      expect(level(34, 115, percent: 30), MassDeletionLevel.none);
    });
  });

  group('όριο των 50 στοιχείων', () {
    test('ακριβώς 50 στοιχεία καλύπτονται: 25 από 50 προειδοποιούν', () {
      expect(level(25, 50), MassDeletionLevel.share);
    });

    test('κάτω από 50 δεν βγαίνει προειδοποίηση ποσοστού', () {
      expect(level(40, 49), MassDeletionLevel.none);
    });
  });

  group('ολόκληρος κατάλογος', () {
    test('προειδοποιεί αυστηρά σε κάθε μέγεθος, και κάτω από 50', () {
      expect(level(115, 115), MassDeletionLevel.whole);
      expect(level(49, 49), MassDeletionLevel.whole);
      expect(level(1, 1), MassDeletionLevel.whole);
    });

    test('η διαγραφή ζητά τη λέξη· τόνοι και κεφαλαία δεν μετρούν', () {
      const whole = MassDeletionLevel.whole;
      expect(massDeletionConfirmAllowed(whole, ''), isFalse);
      expect(massDeletionConfirmAllowed(whole, 'ΔΙΑΓΡΑΦ'), isFalse);
      expect(massDeletionConfirmAllowed(whole, 'ΔΙΑΓΡΑΦΗ'), isTrue);
      expect(massDeletionConfirmAllowed(whole, ' διαγραφή '), isTrue);
    });

    test('κάτω από ολόκληρο κατάλογο δεν ζητείται λέξη', () {
      expect(massDeletionConfirmAllowed(MassDeletionLevel.share, ''), isTrue);
    });
  });

  test('το ποσοστό μένει στα όρια 10–90, με προεπιλογή 50', () {
    expect(normalizeMassDeletionPercent(null), 50);
    expect(normalizeMassDeletionPercent(100), 90);
    expect(normalizeMassDeletionPercent(5), 10);
    expect(normalizeMassDeletionPercent(60), 60);
  });

  test('η ρύθμιση λέει ποιοι κατάλογοι καλύπτονται, από τα πλήθη', () {
    final text = massDeletionCoverageText({
      MassDeletionCatalog.users: 115,
      MassDeletionCatalog.departments: 72,
      MassDeletionCatalog.equipment: 30,
    });

    expect(text, contains('Καλύπτονται: Υπάλληλοι (115), Τμήματα (72).'));
    expect(text, contains('Εξοπλισμός (30)'));
    expect(text, contains('Δεν καλύπτονται'));
  });

  test('η πρόταση της προειδοποίησης λέει «Χ από Υ (Ζ%)»', () {
    expect(
      massDeletionShareText(
        catalog: MassDeletionCatalog.users,
        deleting: 70,
        catalogTotal: 115,
      ),
      'Θα διαγραφούν 70 από τους 115 υπαλλήλους (60%).',
    );
  });
}
