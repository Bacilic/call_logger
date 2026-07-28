import 'package:call_logger/core/utils/user_similarity_finder.dart';
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

  group('UserSimilarityFinder', () {
    test('πλήρες ονοματεπώνυμο — ταύτιση', () {
      final existing = user(id: 1, firstName: 'Δοκιμή', lastName: 'Ένα');
      final found = UserSimilarityFinder.findSimilarUsers(
        users: [existing],
        firstName: 'Δοκιμή',
        lastName: 'Ένα',
      );
      expect(found, hasLength(1));
      expect(found.single.user.id, 1);
      expect(found.single.score, UserSimilarityFinder.kIdenticalScore);
    });

    test('πλήρες ονοματεπώνυμο — χωρίς ταύτιση αν υπάρχει μόνο όνομα', () {
      final existing = user(id: 1, firstName: 'Δοκιμή', lastName: '');
      final found = UserSimilarityFinder.findSimilarUsers(
        users: [existing],
        firstName: 'Δοκιμή',
        lastName: 'Ένα',
      );
      expect(found, isEmpty);
    });

    test('μόνο όνομα — ταύτιση με χρήστη που έχει μόνο όνομα', () {
      final existing = user(id: 2, firstName: 'Δοκιμή1', lastName: '');
      final found = UserSimilarityFinder.findSimilarUsers(
        users: [existing],
        firstName: 'Δοκιμή1',
        lastName: '',
      );
      expect(found, hasLength(1));
      expect(found.single.user.id, 2);
      expect(found.single.score, UserSimilarityFinder.kIdenticalScore);
    });

    test('μόνο όνομα — ταύτιση με χρήστη πλήρους ονοματεπώνυμου', () {
      final existing = user(id: 3, firstName: 'Δοκιμή1', lastName: 'Δοκιμη');
      final found = UserSimilarityFinder.findSimilarUsers(
        users: [existing],
        firstName: 'Δοκιμή1',
        lastName: '',
      );
      expect(found, isEmpty);
    });

    test('μόνο επώνυμο — ταύτιση', () {
      final existing = user(id: 4, firstName: '', lastName: 'Παπαδόπουλος');
      final found = UserSimilarityFinder.findSimilarUsers(
        users: [existing],
        firstName: '',
        lastName: 'Παπαδόπουλος',
      );
      expect(found, hasLength(1));
      expect(found.single.user.id, 4);
      expect(found.single.score, UserSimilarityFinder.kIdenticalScore);
    });

    test('μόνο επώνυμο — ταύτιση με χρήστη πλήρους ονοματεπώνυμου', () {
      final existing = user(
        id: 5,
        firstName: 'Γιάννης',
        lastName: 'Παπαδόπουλος',
      );
      final found = UserSimilarityFinder.findSimilarUsers(
        users: [existing],
        firstName: '',
        lastName: 'Παπαδόπουλος',
      );
      expect(found, isEmpty);
    });

    test('findSimilarUsersFromCallerText — μία λέξη ως όνομα', () {
      final existing = user(id: 7, firstName: 'Δοκιμή1', lastName: 'Δοκιμη');
      final found = UserSimilarityFinder.findSimilarUsersFromCallerText(
        users: [existing],
        callerDisplayText: 'Δοκιμή1',
      );
      expect(found, isEmpty);
    });

    test('findSimilarUsersFromCallerText — δύο λέξεις ως πλήρες όνομα', () {
      final existing = user(id: 9, firstName: 'Δοκιμή1', lastName: 'Δοκιμη');
      final found = UserSimilarityFinder.findSimilarUsersFromCallerText(
        users: [existing],
        callerDisplayText: 'Δοκιμή1 Δοκιμη',
      );
      expect(found, hasLength(1));
      expect(found.single.user.id, 9);
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
      final found = UserSimilarityFinder.findSimilarUsers(
        users: [deleted, excluded, other],
        firstName: 'Άλφα',
        lastName: '',
        excludeUserId: 11,
      );
      expect(found, hasLength(1));
      expect(found.single.user.id, 12);
    });

    test('χωρίς τόνους — ισοδύναμα', () {
      final existing = user(id: 13, firstName: 'Γιάννης', lastName: '');
      final found = UserSimilarityFinder.findSimilarUsers(
        users: [existing],
        firstName: 'Γιαννης',
        lastName: '',
      );
      expect(found, hasLength(1));
      expect(found.single.user.id, 13);
      expect(found.single.score, UserSimilarityFinder.kIdenticalScore);
    });

    test(
      'Αναστασία — μόνο μικρό όνομα δεν είναι ούτε ταυτοπροσωπία ούτε πρόταση',
      () {
        final users = [
          user(id: 1, firstName: 'Αναστασία', lastName: 'Αναστασιάδη'),
          user(id: 2, firstName: 'Αναστασία', lastName: 'Φούφα'),
        ];
        final found = UserSimilarityFinder.findSimilarUsers(
          users: users,
          firstName: 'Αναστασία',
          lastName: '',
        );
        expect(found, isEmpty);
      },
    );

    test('δύο σκέτες Αναστασία → score 100', () {
      final existing = user(id: 1, firstName: 'Αναστασία', lastName: '');
      final found = UserSimilarityFinder.findSimilarUsers(
        users: [existing],
        firstName: 'Αναστασία',
        lastName: '',
      );
      expect(found, hasLength(1));
      expect(found.single.score, UserSimilarityFinder.kIdenticalScore);
    });

    test('δύο πλήρη ταιριάσματα → επιστρέφονται και τα δύο', () {
      final users = [
        user(id: 1, firstName: 'Γιάννης', lastName: 'Παπαδόπουλος'),
        user(id: 2, firstName: 'Γιάννης', lastName: 'Παπαδόπουλος'),
      ];
      final found = UserSimilarityFinder.findSimilarUsers(
        users: users,
        firstName: 'Γιάννης',
        lastName: 'Παπαδόπουλος',
      );
      expect(found, hasLength(2));
      expect(found.map((m) => m.user.id), containsAll([1, 2]));
      expect(
        found.every((m) => m.score == UserSimilarityFinder.kIdenticalScore),
        isTrue,
      );
    });

    test(
      'ανάστροφο ονοματεπώνυμο — πρόταση κάτω από 100 και πάνω από κατώφλι',
      () {
        final existing = user(id: 1, firstName: 'Δρόσος', lastName: 'Βασίλης');
        final found = UserSimilarityFinder.findSimilarUsers(
          users: [existing],
          firstName: 'Βασίλης',
          lastName: 'Δρόσος',
        );
        expect(found, hasLength(1));
        expect(found.single.score, lessThan(100));
        expect(
          found.single.score,
          greaterThanOrEqualTo(UserSimilarityFinder.kSuggestionMinScore),
        );
      },
    );

    test('ανορθογραφία — πρόταση για παρόμοιο ονοματεπώνυμο', () {
      final existing = user(id: 1, firstName: 'Βασιλσ', lastName: 'Δροσος');
      final found = UserSimilarityFinder.findSimilarUsers(
        users: [existing],
        firstName: 'Βασιλης',
        lastName: 'Δροσος',
      );
      expect(found, hasLength(1));
      expect(found.single.score, lessThan(100));
      expect(
        found.single.score,
        greaterThanOrEqualTo(UserSimilarityFinder.kSuggestionMinScore),
      );
    });

    test(
      'δικλείδα: ονόματα κάτω των 5 χαρακτήρων δεν παράγουν πρόταση',
      () {
        final existing = user(id: 1, firstName: 'Άννα', lastName: '');
        final found = UserSimilarityFinder.findSimilarUsers(
          users: [existing],
          firstName: 'Άννη',
          lastName: '',
        );
        expect(found, isEmpty);

        final exact = UserSimilarityFinder.findSimilarUsers(
          users: [existing],
          firstName: 'Αννα',
          lastName: '',
        );
        expect(exact, hasLength(1));
        expect(exact.single.score, UserSimilarityFinder.kIdenticalScore);
      },
    );
  });
}
