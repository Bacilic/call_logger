import 'package:call_logger/core/utils/user_homonym_finder.dart';
import 'package:call_logger/features/calls/models/user_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  UserModel user({
    int? id,
    String? firstName,
    String? lastName,
    bool isDeleted = false,
  }) {
    return UserModel(
      id: id,
      firstName: firstName,
      lastName: lastName,
      isDeleted: isDeleted,
    );
  }

  group('UserHomonymFinder', () {
    test('πλήρες ονοματεπώνυμο — ταύτιση', () {
      final existing = user(id: 1, firstName: 'Δοκιμή', lastName: 'Ένα');
      final found = UserHomonymFinder.findHomonymUser(
        users: [existing],
        firstName: 'Δοκιμή',
        lastName: 'Ένα',
      );
      expect(found?.id, 1);
    });

    test('πλήρες ονοματεπώνυμο — χωρίς ταύτιση αν υπάρχει μόνο όνομα', () {
      final existing = user(id: 1, firstName: 'Δοκιμή', lastName: '');
      final found = UserHomonymFinder.findHomonymUser(
        users: [existing],
        firstName: 'Δοκιμή',
        lastName: 'Ένα',
      );
      expect(found, isNull);
    });

    test('μόνο όνομα — ταύτιση με χρήστη που έχει μόνο όνομα', () {
      final existing = user(id: 2, firstName: 'Δοκιμή1', lastName: '');
      final found = UserHomonymFinder.findHomonymUser(
        users: [existing],
        firstName: 'Δοκιμή1',
        lastName: '',
      );
      expect(found?.id, 2);
    });

    test('μόνο όνομα — ταύτιση με χρήστη πλήρους ονοματεπώνυμου', () {
      final existing = user(id: 3, firstName: 'Δοκιμή1', lastName: 'Δοκιμη');
      final found = UserHomonymFinder.findHomonymUser(
        users: [existing],
        firstName: 'Δοκιμή1',
        lastName: '',
      );
      expect(found?.id, 3);
    });

    test('μόνο επώνυμο — ταύτιση', () {
      final existing = user(id: 4, firstName: '', lastName: 'Παπαδόπουλος');
      final found = UserHomonymFinder.findHomonymUser(
        users: [existing],
        firstName: '',
        lastName: 'Παπαδόπουλος',
      );
      expect(found?.id, 4);
    });

    test('μόνο επώνυμο — ταύτιση με χρήστη πλήρους ονοματεπώνυμου', () {
      final existing = user(id: 5, firstName: 'Γιάννης', lastName: 'Παπαδόπουλος');
      final found = UserHomonymFinder.findHomonymUser(
        users: [existing],
        firstName: '',
        lastName: 'Παπαδόπουλος',
      );
      expect(found?.id, 5);
    });

    test('findHomonymFromCallerText — μία λέξη ως όνομα', () {
      final existing = user(id: 7, firstName: 'Δοκιμή1', lastName: 'Δοκιμη');
      final found = UserHomonymFinder.findHomonymFromCallerText(
        users: [existing],
        callerDisplayText: 'Δοκιμή1',
      );
      expect(found?.id, 7);
    });

    test('findHomonymFromCallerText — δύο λέξεις ως πλήρες όνομα', () {
      final existing = user(id: 9, firstName: 'Δοκιμή1', lastName: 'Δοκιμη');
      final found = UserHomonymFinder.findHomonymFromCallerText(
        users: [existing],
        callerDisplayText: 'Δοκιμή1 Δοκιμη',
      );
      expect(found?.id, 9);
    });

    test('αποκλείει διαγραμμένους και excludeUserId', () {
      final deleted = user(
        id: 10,
        firstName: 'Άλφα',
        lastName: '',
        isDeleted: true,
      );
      final excluded = user(id: 11, firstName: 'Άλφα', lastName: '');
      final other = user(id: 12, firstName: 'Άλφα', lastName: '');
      final found = UserHomonymFinder.findHomonymUser(
        users: [deleted, excluded, other],
        firstName: 'Άλφα',
        lastName: '',
        excludeUserId: 11,
      );
      expect(found?.id, 12);
    });

    test('χωρίς τόνους — ισοδύναμα', () {
      final existing = user(id: 13, firstName: 'Γιάννης', lastName: '');
      final found = UserHomonymFinder.findHomonymUser(
        users: [existing],
        firstName: 'Γιαννης',
        lastName: '',
      );
      expect(found?.id, 13);
    });
  });
}
