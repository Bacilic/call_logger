import 'package:call_logger/features/directory/models/user_form_field_changes.dart';
import 'package:flutter_test/flutter_test.dart';

const UserFormFields _base = (
  lastName: 'Σουλιώτη',
  firstName: 'Σούλα',
  phone: '2975',
  department: 'Αξονικός',
  location: 'δίπλα στο ερμάριο',
  notes: 'Προϊσταμένη',
);

void main() {
  group('Ποια πεδία άλλαξαν', () {
    test('χωρίς αλλαγή δεν επιστρέφει τίποτα', () {
      expect(changedUserFieldLabels(_base, _base), isEmpty);
    });

    test('επιστρέφει τις ετικέτες με τη σειρά της φόρμας', () {
      final now = (
        lastName: 'Σουλιώτου',
        firstName: _base.firstName,
        phone: '2976',
        department: _base.department,
        location: _base.location,
        notes: 'Άλλο',
      );

      expect(changedUserFieldLabels(_base, now), [
        'Επώνυμο',
        'Τηλέφωνο',
        'Σημειώσεις',
      ]);
    });
  });

  group('Αλλαγές που φαίνονται στην καρτέλα εξοπλισμού', () {
    test('το τηλέφωνο δεν εμποδίζει το άνοιγμα', () {
      final now = (
        lastName: _base.lastName,
        firstName: _base.firstName,
        phone: '2976',
        department: _base.department,
        location: _base.location,
        notes: _base.notes,
      );

      expect(ownerFacingChangedLabels(_base, now), isEmpty);
    });

    test('οι σημειώσεις δεν εμποδίζουν το άνοιγμα', () {
      final now = (
        lastName: _base.lastName,
        firstName: _base.firstName,
        phone: _base.phone,
        department: _base.department,
        location: _base.location,
        notes: 'Νέα σημείωση',
      );

      expect(ownerFacingChangedLabels(_base, now), isEmpty);
    });

    test('τηλέφωνο και σημειώσεις μαζί δεν εμποδίζουν', () {
      final now = (
        lastName: _base.lastName,
        firstName: _base.firstName,
        phone: '2976, 2977',
        department: _base.department,
        location: _base.location,
        notes: 'Νέα σημείωση',
      );

      expect(ownerFacingChangedLabels(_base, now), isEmpty);
      expect(changedUserFieldLabels(_base, now), isNotEmpty);
    });

    test('το τμήμα εμποδίζει — το βλέπει η καρτέλα ως κλειδωμένο πεδίο', () {
      final now = (
        lastName: _base.lastName,
        firstName: _base.firstName,
        phone: _base.phone,
        department: 'Ακτινολογικό',
        location: _base.location,
        notes: _base.notes,
      );

      expect(ownerFacingChangedLabels(_base, now), ['Τμήμα']);
    });

    test('η τοποθεσία εμποδίζει — την κληρονομεί ο εξοπλισμός', () {
      final now = (
        lastName: _base.lastName,
        firstName: _base.firstName,
        phone: _base.phone,
        department: _base.department,
        location: 'απέναντι από τον διοικητή',
        notes: _base.notes,
      );

      expect(ownerFacingChangedLabels(_base, now), ['Τοποθεσία']);
    });

    test('το ονοματεπώνυμο εμποδίζει — δείχνεται στο πεδίο «Κάτοχος»', () {
      final now = (
        lastName: 'Σουλιώτου',
        firstName: 'Σουλτάνα',
        phone: _base.phone,
        department: _base.department,
        location: _base.location,
        notes: _base.notes,
      );

      expect(ownerFacingChangedLabels(_base, now), ['Επώνυμο', 'Όνομα']);
    });

    test('από ανάμεικτες αλλαγές κρατά μόνο όσες φαίνονται στην καρτέλα', () {
      final now = (
        lastName: _base.lastName,
        firstName: _base.firstName,
        phone: '2976',
        department: 'Ακτινολογικό',
        location: _base.location,
        notes: 'Νέα σημείωση',
      );

      expect(ownerFacingChangedLabels(_base, now), ['Τμήμα']);
    });
  });
}
