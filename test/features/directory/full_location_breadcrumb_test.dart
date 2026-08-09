// Unit tests: η γραμμή «πλήρους θέσης» Κτίριο › Όροφος › Τμήμα › Τοποθεσία.
//
//   flutter test test/features/directory/full_location_breadcrumb_test.dart

import 'package:call_logger/features/directory/models/full_location_breadcrumb.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('και τα τέσσερα κομμάτια, με βέλη ανάμεσα', () {
    expect(
      fullLocationBreadcrumb(
        building: 'Καινούριο',
        floor: '1ος - Γραφεία',
        department: 'Γραμματεία Κίνησης',
        location: 'δίπλα στο ερμάριο',
      ),
      'Καινούριο › 1ος - Γραφεία › Γραμματεία Κίνησης › δίπλα στο ερμάριο',
    );
  });

  test('χωρίς όροφο, τα υπόλοιπα ενώνονται κανονικά', () {
    expect(
      fullLocationBreadcrumb(
        building: 'Καινούριο',
        department: 'Γραμματεία Κίνησης',
        location: 'δίπλα στο ερμάριο',
      ),
      'Καινούριο › Γραμματεία Κίνησης › δίπλα στο ερμάριο',
    );
  });

  test('χωρίς τοποθεσία, η διαδρομή σταματά στο τμήμα', () {
    expect(
      fullLocationBreadcrumb(
        building: 'Καινούριο',
        floor: '1ος - Γραφεία',
        department: 'Γραμματεία Κίνησης',
      ),
      'Καινούριο › 1ος - Γραφεία › Γραμματεία Κίνησης',
    );
  });

  test('μόνο τμήμα', () {
    expect(
      fullLocationBreadcrumb(department: 'Γραμματεία Κίνησης'),
      'Γραμματεία Κίνησης',
    );
  });

  test('κενό ενδιάμεσο δεν αφήνει διπλό βέλος', () {
    expect(
      fullLocationBreadcrumb(
        building: 'Καινούριο',
        floor: '  ',
        department: '',
        location: 'δίπλα στο ερμάριο',
      ),
      'Καινούριο › δίπλα στο ερμάριο',
    );
  });

  test('όλα κενά δίνουν κενό — η γραμμή κρύβεται', () {
    expect(fullLocationBreadcrumb(), '');
    expect(
      fullLocationBreadcrumb(building: '  ', floor: null, department: ''),
      '',
    );
  });

  test('τα κενά στις άκρες κόβονται', () {
    expect(
      fullLocationBreadcrumb(
        building: '  Καινούριο ',
        department: ' Γραμματεία Κίνησης',
      ),
      'Καινούριο › Γραμματεία Κίνησης',
    );
  });
}
