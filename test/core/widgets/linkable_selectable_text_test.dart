import 'package:call_logger/core/widgets/linkable_selectable_text.dart';
import 'package:call_logger/core/widgets/linkable_target_opener.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingFilesystemOpener {
  final List<String> revealedFiles = [];
  final List<String> openedFolders = [];

  Future<void> revealFile(String path) async {
    revealedFiles.add(path);
  }

  Future<void> openFolder(String path) async {
    openedFolders.add(path);
  }
}

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

  group('LinkableSelectableText', () {
    testWidgets(
      'URL στο κείμενο καλεί τον opener με το σωστό URL',
      (tester) async {
        const url = 'https://example.com/ticket/42';
        final urlRecorder = _RecordingUrlOpener();
        final opener = LinkableTargetOpener(
          launchUrl: urlRecorder.launch,
        );

        await tester.pumpWidget(
          _wrap(
            LinkableSelectableText(
              text: 'Δες το $url εδώ',
              targetOpener: opener,
            ),
          ),
        );

        final state = tester.state<LinkableSelectableTextState>(
          find.byType(LinkableSelectableText),
        );
        await state.triggerLinkTap(url);
        await tester.pumpAndSettle();

        expect(urlRecorder.launchedUri, Uri.parse(url));
      },
    );

    testWidgets(
      'ανύπαρκτη τοπική διαδρομή εμφανίζει SnackBar και δεν καλεί opener',
      (tester) async {
        const missingPath = r'E:\Missing\Folder';
        final fsRecorder = _RecordingFilesystemOpener();
        final opener = LinkableTargetOpener(
          fileExists: (_) async => false,
          directoryExists: (_) async => false,
          revealFileInExplorer: fsRecorder.revealFile,
          openFolderInExplorer: fsRecorder.openFolder,
          launchUrl: (_) async => true,
        );

        await tester.pumpWidget(
          _wrap(
            LinkableSelectableText(
              text: 'Άνοιξε $missingPath τώρα',
              targetOpener: opener,
            ),
          ),
        );

        final state = tester.state<LinkableSelectableTextState>(
          find.byType(LinkableSelectableText),
        );
        await state.triggerLinkTap(missingPath);
        await tester.pumpAndSettle();

        expect(
          find.text('Η διαδρομή δεν βρέθηκε: $missingPath'),
          findsOneWidget,
        );
        expect(fsRecorder.revealedFiles, isEmpty);
        expect(fsRecorder.openedFolders, isEmpty);
      },
    );
  });
}
