import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Το εργαλείο δημοσίευσης δεν επιτρέπεται να φτάσει στο `package:flutter`.
///
/// Το `tool/publish.dart` τρέχει με σκέτο `dart run`, **έξω από τη μηχανή
/// Flutter** — και εκεί το `dart:ui` δεν υπάρχει. Ένα και μόνο import που
/// οδηγεί στο `package:flutter` (ή σε πακέτο που το φέρνει, όπως το
/// `path_provider`) σταματά τη δημοσίευση με **εκατοντάδες σφάλματα μέσα στο
/// ίδιο το Flutter** — «'Size' isn't a type», «'Rect' isn't a type» — που δεν
/// δείχνουν πουθενά προς την πραγματική αιτία.
///
/// **Γιατί χρειάζεται τεστ και δεν αρκεί το `flutter analyze`:** η ανάλυση
/// βγάζει καθαρό αποτέλεσμα, γιατί μέσα στην εφαρμογή τα imports είναι
/// απολύτως έγκυρα. Σπάει μόνο η εκτέλεση από τερματικό, και μόνο τη στιγμή
/// που κάποιος πάει να δημοσιεύσει έκδοση.
void main() {
  final projectRoot = Directory.current.path;

  /// Πακέτα που φέρνουν `dart:ui` μαζί τους. Το `path_provider` το έκανε στην
  /// πράξη, μέσω του `path_provider_platform_interface`.
  const forbiddenPackages = <String>[
    'package:flutter/',
    'package:flutter_riverpod/',
    'package:path_provider/',
    'package:file_picker/',
    'package:shared_preferences/',
  ];

  final importPattern = RegExp('''import\\s+['"]([^'"]+)['"]''');

  /// Επιστρέφει τα project-local imports ενός αρχείου, ως απόλυτες διαδρομές.
  ({List<String> local, List<String> packages}) importsOf(String filePath) {
    final source = File(filePath).readAsStringSync();
    final local = <String>[];
    final packages = <String>[];
    for (final m in importPattern.allMatches(source)) {
      final uri = m.group(1)!;
      if (uri.startsWith('dart:')) continue;
      if (uri.startsWith('package:call_logger/')) {
        local.add(
          p.normalize(
            p.join(
              projectRoot,
              'lib',
              uri.substring('package:call_logger/'.length),
            ),
          ),
        );
      } else if (uri.startsWith('package:')) {
        packages.add(uri);
      } else {
        local.add(p.normalize(p.join(p.dirname(filePath), uri)));
      }
    }
    return (local: local, packages: packages);
  }

  test('η αλυσίδα του tool/publish.dart δεν φτάνει στο package:flutter', () {
    final entry = p.join(projectRoot, 'tool', 'publish.dart');
    expect(
      File(entry).existsSync(),
      isTrue,
      reason: 'Το σημείο εισόδου της δημοσίευσης δεν βρέθηκε.',
    );

    // Πλάτος-πρώτα, κρατώντας τη διαδρομή που οδήγησε σε κάθε αρχείο, ώστε το
    // μήνυμα αποτυχίας να δείχνει ΠΟΥ μπήκε το import και όχι μόνο ότι μπήκε.
    final visited = <String>{};
    final queue = <({String path, List<String> trail})>[
      (path: entry, trail: const []),
    ];

    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      if (!visited.add(current.path)) continue;
      if (!File(current.path).existsSync()) continue;

      final imports = importsOf(current.path);
      final trail = [
        ...current.trail,
        p.relative(current.path, from: projectRoot),
      ];

      for (final pkg in imports.packages) {
        for (final forbidden in forbiddenPackages) {
          expect(
            pkg.startsWith(forbidden),
            isFalse,
            reason:
                'Το εργαλείο δημοσίευσης έφτασε στο «$pkg», που φέρνει μαζί '
                'του το dart:ui.\n'
                'Διαδρομή: ${trail.join(' → ')}\n'
                'Το `dart run tool/publish.dart` θα σκάσει με σφάλματα μέσα '
                'στο ίδιο το Flutter. Κόψε την αλυσίδα: κράτησε στο εργαλείο '
                'μόνο ό,τι είναι καθαρό Dart (δες '
                'lib/core/database/database_schema_version.dart).',
          );
        }
      }

      for (final localPath in imports.local) {
        queue.add((path: localPath, trail: trail));
      }
    }
  });

  test('το αρχείο της έκδοσης σχήματος δεν έχει κανένα import', () {
    // Ο μοναδικός λόγος ύπαρξής του: να μπορεί να διαβαστεί έξω από το
    // Flutter. Ένα import αρκεί για να το ακυρώσει.
    final file = File(
      p.join(
        projectRoot,
        'lib',
        'core',
        'database',
        'database_schema_version.dart',
      ),
    );
    expect(file.existsSync(), isTrue);
    expect(
      importPattern.hasMatch(file.readAsStringSync()),
      isFalse,
      reason:
          'Το database_schema_version.dart πρέπει να μείνει χωρίς imports — '
          'αλλιώς το εργαλείο δημοσίευσης ξανασέρνει ολόκληρο το Flutter.',
    );
  });
}
