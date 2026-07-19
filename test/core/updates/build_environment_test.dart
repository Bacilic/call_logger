import 'package:call_logger/core/updates/build_environment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BuildEnvironment.isDevelopmentBuild', () {
    test('isDebug true → true', () {
      expect(
        BuildEnvironment.isDevelopmentBuild(
          isDebug: true,
          executablePath: r'C:\Users\me\Documents\Call Logger',
        ),
        isTrue,
      );
    });

    test(r'Debug path with \build\windows\ → true', () {
      expect(
        BuildEnvironment.isDevelopmentBuild(
          isDebug: false,
          executablePath:
              r'F:\flutter_projects\call_logger\build\windows\x64\runner\Debug',
        ),
        isTrue,
      );
    });

    test(r'Release path with \build\windows\ → true', () {
      expect(
        BuildEnvironment.isDevelopmentBuild(
          isDebug: false,
          executablePath:
              r'F:\flutter_projects\call_logger\build\windows\x64\runner\Release',
        ),
        isTrue,
      );
    });

    test('production Documents path → false', () {
      expect(
        BuildEnvironment.isDevelopmentBuild(
          isDebug: false,
          executablePath: r'C:\Users\me\Documents\Call Logger',
        ),
        isFalse,
      );
    });

    test(r'network/other path without \build\windows\ → false', () {
      expect(
        BuildEnvironment.isDevelopmentBuild(
          isDebug: false,
          executablePath: r'\\server\share\Call Logger',
        ),
        isFalse,
      );
    });

    test('forward slashes are normalized before matching', () {
      expect(
        BuildEnvironment.isDevelopmentBuild(
          isDebug: false,
          executablePath:
              'F:/flutter_projects/call_logger/build/windows/x64/runner/Release',
        ),
        isTrue,
      );
    });
  });
}
