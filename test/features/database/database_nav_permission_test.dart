import 'package:call_logger/core/models/app_permission.dart';
import 'package:call_logger/core/models/operator.dart';
import 'package:call_logger/core/providers/settings_provider.dart';
import 'package:call_logger/core/services/current_operator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ορατότητα της Περιήγησης Βάσης: **προτίμηση ΚΑΙ δικαίωμα**.
///
/// Και οι τρεις πύλες που οδηγούν εκεί —η πλευρική μπάρα, το μενού πλοήγησης
/// του Ιστορικού και του Λεξικού— διαβάζουν αυτόν τον έναν υπολογισμό. Ό,τι
/// φυλάει εδώ, τις φυλάει όλες· κάθε νέα πύλη κληρονομεί τον έλεγχο μόνη της.
Operator _operator(
  int id, {
  bool isAdmin = false,
  Map<String, bool> overrides = const <String, bool>{},
}) => Operator(
  id: id,
  displayName: 'Χρήστης $id',
  isAdmin: isAdmin,
  permissionOverrides: overrides,
  createdAt: DateTime(2026, 8, 21),
);

/// Στήνει δοχείο με **καθορισμένη** την προτίμηση, ώστε ο έλεγχος να μιλά μόνο
/// για το δικαίωμα και να μην εξαρτάται από αποθηκευμένη ρύθμιση.
Future<ProviderContainer> _containerWith({required bool preference}) async {
  final container = ProviderContainer(
    overrides: [
      showDatabaseNavProvider.overrideWith((ref) async => preference),
    ],
  );
  // Όσο η προτίμηση φορτώνει, ο προορισμός φαίνεται· περιμένουμε να καθίσει
  // ώστε να ελέγχουμε την τελική απάντηση και όχι την ενδιάμεση.
  await container.read(showDatabaseNavProvider.future);
  return container;
}

void main() {
  setUp(CurrentOperator.reset);
  tearDown(CurrentOperator.reset);

  test('χωρίς συνδεδεμένο χρήστη ο προορισμός φαίνεται', () async {
    final container = await _containerWith(preference: true);
    addTearDown(container.dispose);

    expect(
      container.read(databaseNavVisibleProvider),
      isTrue,
      reason:
          'Ζώνη ασφαλείας από λάθη, όχι κλειδαριά: χωρίς ταυτότητα τίποτα δεν '
          'κρύβεται.',
    );
  });

  test('με το δικαίωμα ανοιχτό ο προορισμός φαίνεται', () async {
    CurrentOperator.activate(_operator(2));
    final container = await _containerWith(preference: true);
    addTearDown(container.dispose);

    expect(container.read(databaseNavVisibleProvider), isTrue);
  });

  test(
    'χωρίς το δικαίωμα ο προορισμός κρύβεται, ό,τι κι αν λέει η προτίμηση',
    () async {
      CurrentOperator.activate(
        _operator(2, overrides: {AppPermission.browseDatabase.key: false}),
      );
      final container = await _containerWith(preference: true);
      addTearDown(container.dispose);

      expect(
        container.read(databaseNavVisibleProvider),
        isFalse,
        reason:
            'Η Περιήγηση δείχνει τους ωμούς πίνακες — και τα προσωπικά κλειδιά '
            'ΤΝ σε απλό κείμενο. Το δικαίωμα πρέπει να κερδίζει την προτίμηση.',
      );
    },
  );

  test(
    'ο διαχειριστής τη βλέπει ακόμη και με ρητή άρνηση στη λίστα του',
    () async {
      CurrentOperator.activate(
        _operator(
          1,
          isAdmin: true,
          overrides: {AppPermission.browseDatabase.key: false},
        ),
      );
      final container = await _containerWith(preference: true);
      addTearDown(container.dispose);

      expect(container.read(databaseNavVisibleProvider), isTrue);
    },
  );

  test(
    'κλειστή προτίμηση κρύβει τον προορισμό και με το δικαίωμα ανοιχτό',
    () async {
      CurrentOperator.activate(_operator(2));
      final container = await _containerWith(preference: false);
      addTearDown(container.dispose);

      expect(
        container.read(databaseNavVisibleProvider),
        isFalse,
        reason:
            'Ο διακόπτης των Ρυθμίσεων παραμένει σεβαστός — το δικαίωμα προσθέτει '
            'περιορισμό, δεν ακυρώνει την επιλογή του χρήστη.',
      );
    },
  );
}
