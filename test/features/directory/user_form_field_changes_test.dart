import 'package:call_logger/features/directory/models/user_form_field_changes.dart';
import 'package:flutter_test/flutter_test.dart';

const UserFormFields _base = (
  lastName: 'Σουλιώτη',
  firstName: 'Σούλα',
  phone: '2975',
  department: 'Αξονικός',
  location: 'δίπλα στο ερμάριο',
  notes: 'Προϊσταμένη',
  lansweeper: r'gnk\s.soulioti',
);

/// Αντίγραφο του [_base] με επιλεκτικές αλλαγές — τα records δεν έχουν copyWith.
UserFormFields _with({
  String? lastName,
  String? firstName,
  String? phone,
  String? department,
  String? location,
  String? notes,
  String? lansweeper,
}) {
  return (
    lastName: lastName ?? _base.lastName,
    firstName: firstName ?? _base.firstName,
    phone: phone ?? _base.phone,
    department: department ?? _base.department,
    location: location ?? _base.location,
    notes: notes ?? _base.notes,
    lansweeper: lansweeper ?? _base.lansweeper,
  );
}

void main() {
  group('Ποια πεδία άλλαξαν', () {
    test('χωρίς αλλαγή δεν επιστρέφει τίποτα', () {
      expect(changedUserFieldLabels(_base, _base), isEmpty);
    });

    test('επιστρέφει τις ετικέτες με τη σειρά της φόρμας', () {
      final now = _with(lastName: 'Σουλιώτου', phone: '2976', notes: 'Άλλο');

      expect(changedUserFieldLabels(_base, now), [
        'Επώνυμο',
        'Τηλέφωνο',
        'Σημειώσεις',
      ]);
    });

    test('η αλλαγή αναγνωριστικού Lansweeper αναφέρεται ονομαστικά', () {
      final now = _with(lansweeper: r'gnk\s.souliotou');

      expect(changedUserFieldLabels(_base, now), ['Αναγνωριστικό Lansweeper']);
    });
  });

  group('Αλλαγές που φαίνονται στην καρτέλα εξοπλισμού', () {
    test('το τηλέφωνο δεν εμποδίζει το άνοιγμα', () {
      expect(ownerFacingChangedLabels(_base, _with(phone: '2976')), isEmpty);
    });

    test('οι σημειώσεις δεν εμποδίζουν το άνοιγμα', () {
      expect(
        ownerFacingChangedLabels(_base, _with(notes: 'Νέα σημείωση')),
        isEmpty,
      );
    });

    test('το αναγνωριστικό Lansweeper δεν εμποδίζει το άνοιγμα', () {
      expect(
        ownerFacingChangedLabels(_base, _with(lansweeper: r'gnk\allos')),
        isEmpty,
      );
    });

    test('τηλέφωνο και σημειώσεις μαζί δεν εμποδίζουν', () {
      final now = _with(phone: '2976, 2977', notes: 'Νέα σημείωση');

      expect(ownerFacingChangedLabels(_base, now), isEmpty);
      expect(changedUserFieldLabels(_base, now), isNotEmpty);
    });

    test('το τμήμα εμποδίζει — το βλέπει η καρτέλα ως κλειδωμένο πεδίο', () {
      expect(ownerFacingChangedLabels(_base, _with(department: 'Ακτινολογικό')), [
        'Τμήμα',
      ]);
    });

    test('η τοποθεσία εμποδίζει — την κληρονομεί ο εξοπλισμός', () {
      expect(
        ownerFacingChangedLabels(
          _base,
          _with(location: 'απέναντι από τον διοικητή'),
        ),
        ['Τοποθεσία'],
      );
    });

    test('το ονοματεπώνυμο εμποδίζει — δείχνεται στο πεδίο «Κάτοχος»', () {
      final now = _with(lastName: 'Σουλιώτου', firstName: 'Σουλτάνα');

      expect(ownerFacingChangedLabels(_base, now), ['Επώνυμο', 'Όνομα']);
    });

    test('από ανάμεικτες αλλαγές κρατά μόνο όσες φαίνονται στην καρτέλα', () {
      final now = _with(
        phone: '2976',
        department: 'Ακτινολογικό',
        notes: 'Νέα σημείωση',
      );

      expect(ownerFacingChangedLabels(_base, now), ['Τμήμα']);
    });
  });
}
