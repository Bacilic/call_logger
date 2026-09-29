import 'package:call_logger/core/widgets/linkable_target_opener.dart';
import 'package:call_logger/core/widgets/linkable_text.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingUrlOpener {
  Uri? launchedUri;

  Future<bool> launch(Uri uri) async {
    launchedUri = uri;
    return true;
  }
}

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: Padding(padding: const EdgeInsets.all(16), child: child),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LinkableText', () {
    testWidgets('URL στο κείμενο καλεί τον opener με το σωστό URL', (
      tester,
    ) async {
      const url = 'https://example.com/ticket/99';
      final urlRecorder = _RecordingUrlOpener();
      final opener = LinkableTargetOpener(launchUrl: urlRecorder.launch);

      await tester.pumpWidget(
        _wrap(
          LinkableText(
            text: 'Σημείωση: $url',
            targetOpener: opener,
            askBeforeOpening: () async => false,
          ),
        ),
      );

      final state = tester.state<LinkableTextState>(find.byType(LinkableText));
      await state.triggerLinkTap(url);
      await tester.pumpAndSettle();

      expect(urlRecorder.launchedUri, Uri.parse(url));
    });

    testWidgets('ο recognizer του χτισμένου span ανοίγει τον σύνδεσμο', (
      tester,
    ) async {
      const url = 'https://example.com/span/7';
      final urlRecorder = _RecordingUrlOpener();
      final opener = LinkableTargetOpener(launchUrl: urlRecorder.launch);

      await tester.pumpWidget(
        _wrap(
          LinkableText(
            text: 'Δες $url εδώ',
            targetOpener: opener,
            askBeforeOpening: () async => false,
          ),
        ),
      );

      final richText = tester.widget<RichText>(find.byType(RichText));
      TapGestureRecognizer? recognizer;
      (richText.text as TextSpan).visitChildren((span) {
        if (span is TextSpan && span.recognizer is TapGestureRecognizer) {
          recognizer = span.recognizer as TapGestureRecognizer;
          return false;
        }
        return true;
      });

      expect(
        recognizer,
        isNotNull,
        reason: 'ο σύνδεσμος πρέπει να έχει recognizer',
      );
      recognizer!.onTap!();
      await tester.pumpAndSettle();

      expect(urlRecorder.launchedUri, Uri.parse(url));
    });

    testWidgets('σέβεται maxLines και ellipsis', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SizedBox(
            width: 120,
            child: LinkableText(
              text:
                  'Πολύ μακρύ κείμενο με https://example.com/x και επιπλέον λέξεις',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      );

      final richText = tester.widget<RichText>(find.byType(RichText));
      expect(richText.maxLines, 2);
      expect(richText.overflow, TextOverflow.ellipsis);
    });
  });

  group('LinkableText — ερώτηση πριν από το άνοιγμα', () {
    testWidgets(
      'διαδρομή δικτύου: η ερώτηση δείχνει τον προορισμό και η Ακύρωση δεν '
      'αγγίζει καθόλου τη διαδρομή',
      (tester) async {
        const path = r'\\XENOS-PC\share\file.txt';
        final probed = <String>[];
        final opener = LinkableTargetOpener(
          fileExists: (p) async {
            probed.add(p);
            return true;
          },
          directoryExists: (p) async {
            probed.add(p);
            return false;
          },
          revealFileInExplorer: (p) async => probed.add('reveal:$p'),
          openFolderInExplorer: (p) async => probed.add('open:$p'),
        );

        await tester.pumpWidget(
          _wrap(
            LinkableText(
              text: 'Δες το $path',
              targetOpener: opener,
              askBeforeOpening: () async => true,
            ),
          ),
        );

        final state = tester.state<LinkableTextState>(
          find.byType(LinkableText),
        );
        final tap = state.triggerLinkTap(path);
        await tester.pumpAndSettle();

        expect(find.text('Σύνδεση σε υπολογιστή του δικτύου;'), findsOneWidget);
        expect(find.text(path), findsOneWidget);
        expect(find.textContaining('«XENOS-PC»'), findsOneWidget);

        await tester.tap(find.text('Ακύρωση'));
        await tester.pumpAndSettle();
        await tap;

        expect(
          probed,
          isEmpty,
          reason:
              'με την Ακύρωση ο υπολογιστής δεν πρέπει να επικοινωνήσει '
              'καθόλου με το ξένο μηχάνημα — ούτε για έλεγχο ύπαρξης',
        );
      },
    );

    testWidgets('ιστοσελίδα: το «Άνοιγμα» ανοίγει τον σύνδεσμο', (
      tester,
    ) async {
      const url = 'https://example.com/ticket/5';
      final urlRecorder = _RecordingUrlOpener();
      final opener = LinkableTargetOpener(launchUrl: urlRecorder.launch);

      await tester.pumpWidget(
        _wrap(
          LinkableText(
            text: 'Σημείωση: $url',
            targetOpener: opener,
            askBeforeOpening: () async => true,
          ),
        ),
      );

      final state = tester.state<LinkableTextState>(find.byType(LinkableText));
      final tap = state.triggerLinkTap(url);
      await tester.pumpAndSettle();

      expect(find.text('Άνοιγμα ιστοσελίδας;'), findsOneWidget);
      expect(urlRecorder.launchedUri, isNull);

      await tester.tap(find.text('Άνοιγμα'));
      await tester.pumpAndSettle();
      await tap;

      expect(urlRecorder.launchedUri, Uri.parse(url));
    });

    testWidgets('με κλειστή την ερώτηση ανοίγει κατευθείαν, χωρίς διάλογο', (
      tester,
    ) async {
      const url = 'https://example.com/direct';
      final urlRecorder = _RecordingUrlOpener();
      final opener = LinkableTargetOpener(launchUrl: urlRecorder.launch);

      await tester.pumpWidget(
        _wrap(
          LinkableText(
            text: 'Σημείωση: $url',
            targetOpener: opener,
            askBeforeOpening: () async => false,
          ),
        ),
      );

      final state = tester.state<LinkableTextState>(find.byType(LinkableText));
      await state.triggerLinkTap(url);
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(urlRecorder.launchedUri, Uri.parse(url));
    });
  });
}
