import 'package:call_logger/core/widgets/linkable_target_opener.dart';
import 'package:call_logger/core/widgets/linkable_text.dart';
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
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LinkableText', () {
    testWidgets(
      'URL στο κείμενο καλεί τον opener με το σωστό URL',
      (tester) async {
        const url = 'https://example.com/ticket/99';
        final urlRecorder = _RecordingUrlOpener();
        final opener = LinkableTargetOpener(
          launchUrl: urlRecorder.launch,
        );

        await tester.pumpWidget(
          _wrap(
            LinkableText(
              text: 'Σημείωση: $url',
              targetOpener: opener,
            ),
          ),
        );

        final state = tester.state<LinkableTextState>(
          find.byType(LinkableText),
        );
        await state.triggerLinkTap(url);
        await tester.pumpAndSettle();

        expect(urlRecorder.launchedUri, Uri.parse(url));
      },
    );

    testWidgets(
      'σέβεται maxLines και ellipsis',
      (tester) async {
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
      },
    );
  });
}
