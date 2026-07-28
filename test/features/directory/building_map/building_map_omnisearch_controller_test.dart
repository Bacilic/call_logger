import 'package:call_logger/core/database/omnisearch_service.dart';
import 'package:call_logger/features/directory/building_map/controllers/building_map_omnisearch_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/*
 * Συμβόλαιο: ο καλών ρωτά με ένα κείμενο και παίρνει τα αποτελέσματα ΑΥΤΟΥ του
 * κειμένου. `null` σημαίνει «ξεπεράστηκε από νεότερο αίτημα».
 *
 *   flutter test test/features/directory/building_map/building_map_omnisearch_controller_test.dart
 */

BuildingMapOmnisearchHit _hit(String title) => BuildingMapOmnisearchHit(
  kind: BuildingMapOmnisearchEntityKind.user,
  entityId: title.hashCode,
  title: title,
  departmentIds: const [],
);

void main() {
  const fastDebounce = Duration(milliseconds: 20);

  late List<String> asked;

  BuildingMapOmnisearchController controllerWith({
    Duration searchDuration = Duration.zero,
  }) {
    return BuildingMapOmnisearchController(
      debounce: fastDebounce,
      search: (q) async {
        asked.add(q);
        if (searchDuration > Duration.zero) {
          await Future<void>.delayed(searchDuration);
        }
        return [_hit('αποτέλεσμα:$q')];
      },
    );
  }

  setUp(() => asked = []);

  test('επιστρέφει τα αποτελέσματα του ΕΡΩΤΗΜΑΤΟΣ που δόθηκε', () async {
    final c = controllerWith();
    addTearDown(c.dispose);

    final hits = await c.query('2914');

    expect(asked, ['2914']);
    expect(hits!.single.title, 'αποτέλεσμα:2914');
  });

  test(
    'γρήγορη πληκτρολόγηση: μόνο το τελευταίο ερώτημα φτάνει στη βάση',
    () async {
      final c = controllerWith();
      addTearDown(c.dispose);

      final first = c.query('291');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final second = c.query('2914');

      expect(
        await first,
        isNull,
        reason: 'Το ξεπερασμένο αίτημα δεν επιστρέφει αποτελέσματα',
      );
      expect((await second)!.single.title, 'αποτέλεσμα:2914');
      expect(asked, ['2914'], reason: 'Το debounce έκοψε το ενδιάμεσο ερώτημα');
    },
  );

  test('αργή αναζήτηση που ξεπεράστηκε επιστρέφει null', () async {
    final c = controllerWith(searchDuration: const Duration(milliseconds: 60));
    addTearDown(c.dispose);

    final slow = c.query('291');
    await Future<void>.delayed(const Duration(milliseconds: 40));
    final fresh = c.query('2914');

    expect(await slow, isNull);
    expect((await fresh)!.single.title, 'αποτέλεσμα:2914');
    expect(asked, ['291', '2914'], reason: 'Και τα δύο ξεκίνησαν πραγματικά');
  });

  test('κενό κείμενο: κενή λίστα χωρίς ερώτημα στη βάση', () async {
    final c = controllerWith();
    addTearDown(c.dispose);

    expect(await c.query('   '), isEmpty);
    expect(asked, isEmpty);
  });

  test('queryImmediate δεν περιμένει το debounce', () async {
    final c = BuildingMapOmnisearchController(
      debounce: const Duration(seconds: 5),
      search: (q) async {
        asked.add(q);
        return [_hit('άμεσο:$q')];
      },
    );
    addTearDown(c.dispose);

    final hits = await c
        .queryImmediate('2914')
        .timeout(const Duration(seconds: 1));

    expect(hits!.single.title, 'άμεσο:2914');
  });

  test('ο δείκτης φόρτωσης ανάβει και σβήνει', () async {
    final c = controllerWith(searchDuration: const Duration(milliseconds: 30));
    addTearDown(c.dispose);

    final states = <bool>[];
    c.isSearching.addListener(() => states.add(c.isSearching.value));

    await c.query('2914');

    expect(states, [true, false]);
  });

  test('μετά το dispose δεν εκτελείται τίποτα', () async {
    final c = controllerWith();
    c.dispose();

    expect(await c.query('2914'), isNull);
    expect(asked, isEmpty);
  });
}
