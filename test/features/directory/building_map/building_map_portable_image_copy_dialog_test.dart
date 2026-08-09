import 'package:call_logger/features/directory/building_map/widgets/building_map_portable_image_copy_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _sourcePath = r'C:\Users\Bacilic\Desktop\Χάρτες\2 - Γραφεία.png';

/// Στήνει κουμπί που ανοίγει τον διάλογο και τον ανοίγει· το μελλοντικό
/// αποτέλεσμα του διαλόγου παραδίδεται στο [onOpened] χωρίς να αναμένεται.
Future<void> _pumpAndOpenDialog(
  WidgetTester tester, {
  void Function(Future<PortableImageCopyDialogResult?> resultFuture)? onOpened,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () {
              final future = showBuildingMapPortableImageCopyDialog(
                context,
                sourceImagePath: _sourcePath,
              );
              onOpened?.call(future);
            },
            child: const Text('Άνοιγμα'),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('Άνοιγμα'));
  await tester.pumpAndSettle();
}

TextButton _noTransferButton(WidgetTester tester) {
  return tester.widget<TextButton>(
    find.ancestor(
      of: find.text('Χωρίς μεταφορά'),
      matching: find.byType(TextButton),
    ),
  );
}

Future<void> _closeDialog(WidgetTester tester) async {
  Navigator.of(tester.element(find.text('Χωρίς μεταφορά'))).pop();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('ο διάλογος δείχνει την πλήρη διαδρομή της εικόνας', (
    tester,
  ) async {
    await _pumpAndOpenDialog(tester);

    expect(
      find.text(_sourcePath),
      findsOneWidget,
      reason:
          'Ο διάλογος πρέπει να δείχνει πού ακριβώς βρίσκεται η εικόνα, '
          'όχι μόνο «εκτός του φακέλου της εφαρμογής».',
    );

    await _closeDialog(tester);
  });

  testWidgets('με ενεργή μετονομασία το «Χωρίς μεταφορά» απενεργοποιείται και '
      'εξηγείται ο λόγος', (tester) async {
    await _pumpAndOpenDialog(tester);

    expect(_noTransferButton(tester).onPressed, isNotNull);

    await tester.tap(find.text('Μετονομασία σε:'));
    await tester.pumpAndSettle();

    expect(
      _noTransferButton(tester).onPressed,
      isNull,
      reason:
          'Η μετονομασία ισχύει μόνο με μεταφορά — το «Χωρίς μεταφορά» '
          'δεν επιτρέπεται να αγνοήσει σιωπηλά την ενεργή επιλογή.',
    );
    expect(
      find.textContaining('Η μετονομασία ισχύει μόνο με μεταφορά'),
      findsOneWidget,
    );

    // Η επιστροφή στη «Διατήρηση ονόματος» ξανανοίγει τον δρόμο.
    await tester.tap(find.text('Διατήρηση ονόματος «2 - Γραφεία.png»'));
    await tester.pumpAndSettle();
    expect(_noTransferButton(tester).onPressed, isNotNull);

    await _closeDialog(tester);
  });

  testWidgets(
    'με διατήρηση ονόματος το «Χωρίς μεταφορά» επιστρέφει χρήση από την '
    'τρέχουσα θέση',
    (tester) async {
      Future<PortableImageCopyDialogResult?>? resultFuture;
      await _pumpAndOpenDialog(tester, onOpened: (f) => resultFuture = f);

      await tester.tap(find.text('Χωρίς μεταφορά'));
      await tester.pumpAndSettle();

      final result = await resultFuture!;
      expect(result, isNotNull);
      expect(result!.copyToPortable, isFalse);
      expect(result.fileName, isNull);
    },
  );
}
