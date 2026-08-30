import 'dart:math';

import 'package:call_logger/core/models/operator.dart';
import 'package:call_logger/features/operators/avatars/operator_avatar_assignment.dart';
import 'package:call_logger/features/operators/avatars/operator_avatar_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

/// Το συμβόλαιο: **δύο ενεργά προφίλ δεν κρατούν ποτέ το ίδιο εικονίδιο**, και
/// όταν τα εικονίδια τελειώσουν το επόμενο προφίλ μένει με το κλασικό
/// ανθρωπάκι αντί να μπλοκάρει.
void main() {
  Operator profile(int id, {String? avatar, bool active = true}) => Operator(
    id: id,
    displayName: 'Χρήστης $id',
    isActive: active,
    avatarKey: avatar,
    createdAt: DateTime(2026, 8, 30),
  );

  group('ποια εικονίδια είναι πιασμένα', () {
    test('μόνο τα ενεργά προφίλ δεσμεύουν', () {
      final taken = takenAvatarKeys([
        profile(1, avatar: 'gorilla'),
        profile(2, avatar: 'angel', active: false),
      ]);

      expect(taken, {'gorilla'});
    });

    test('το ίδιο το προφίλ που επεξεργάζεται εξαιρείται', () {
      final taken = takenAvatarKeys([
        profile(1, avatar: 'gorilla'),
        profile(2, avatar: 'angel'),
      ], excludeId: 2);

      expect(taken, {'gorilla'});
    });

    test('προφίλ χωρίς εικονίδιο δεν δεσμεύει τίποτα', () {
      expect(takenAvatarKeys([profile(1), profile(2)]), isEmpty);
    });
  });

  group('επιλογή εικονιδίου για νέο προφίλ', () {
    test('δεν δίνει ποτέ πιασμένο εικονίδιο', () {
      // Όλα εκτός από ένα είναι πιασμένα: η μόνη σωστή απάντηση είναι εκείνο.
      final taken = {for (final avatar in kOperatorAvatars.skip(1)) avatar.key};

      expect(pickAvatarKey(taken), kOperatorAvatars.first.key);
    });

    test('με όλα πιασμένα επιστρέφει κενό αντί να αποτύχει', () {
      final taken = {for (final avatar in kOperatorAvatars) avatar.key};

      expect(pickAvatarKey(taken), isNull);
    });

    test('η επιλογή είναι τυχαία, όχι πάντα η πρώτη του καταλόγου', () {
      // Με ελεγχόμενο κλήρο, το τρίτο ελεύθερο πρέπει να είναι επιλέξιμο —
      // αλλιώς ο κλήρος αγνοείται και όλοι παίρνουν το ίδιο εικονίδιο.
      final picked = pickAvatarKey(const <String>{}, random: _FixedRandom(2));

      expect(picked, kOperatorAvatars[2].key);
    });
  });

  test('ο κατάλογος δεν έχει διπλά κλειδιά', () {
    final keys = [for (final avatar in kOperatorAvatars) avatar.key];

    expect(keys.toSet().length, keys.length);
  });

  group('αναζήτηση στον κατάλογο', () {
    test('άγνωστο κλειδί δεν σκάει — δίνει κενό', () {
      expect(findAvatar('δεν-υπάρχει'), isNull);
      expect(findAvatar(null), isNull);
      expect(findAvatar(''), isNull);
    });

    test('το κλειδί οδηγεί στο αρχείο του', () {
      expect(findAvatar('gorilla')?.assetPath, 'assets/avatars/gorilla.webp');
    });
  });
}

/// Κλήρος που δίνει πάντα τον ίδιο αριθμό — για να ελεγχθεί ότι ο κλήρος
/// όντως διαβάζεται.
class _FixedRandom implements Random {
  _FixedRandom(this.value);

  final int value;

  @override
  int nextInt(int max) => value % max;

  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0;
}
