#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <string>
#include <vector>

#include "flutter_window.h"
#include "utils.h"

namespace {

std::wstring Utf16FromUtf8(const std::string& utf8_string) {
  if (utf8_string.empty()) {
    return std::wstring();
  }
  const int input_length = static_cast<int>(utf8_string.size());
  const int target_length = ::MultiByteToWideChar(
      CP_UTF8, MB_ERR_INVALID_CHARS, utf8_string.data(), input_length, nullptr,
      0);
  if (target_length <= 0) {
    return std::wstring();
  }
  std::wstring utf16_string(static_cast<size_t>(target_length), L'\0');
  const int converted_length = ::MultiByteToWideChar(
      CP_UTF8, MB_ERR_INVALID_CHARS, utf8_string.data(), input_length,
      utf16_string.data(), target_length);
  if (converted_length <= 0) {
    return std::wstring();
  }
  return utf16_string;
}

void RegisterCrashRestart(const std::vector<std::string>& command_line_arguments) {
  std::vector<std::string> restart_arguments = command_line_arguments;
  auto has_restart_flag = [&restart_arguments]() {
    for (const auto& argument : restart_arguments) {
      if (argument == "--restarted-after-crash") {
        return true;
      }
    }
    return false;
  };
  if (!has_restart_flag()) {
    restart_arguments.push_back("--restarted-after-crash");
  }

  std::wstring restart_command_line;
  for (size_t i = 0; i < restart_arguments.size(); ++i) {
    if (i > 0) {
      restart_command_line += L' ';
    }
    restart_command_line += Utf16FromUtf8(restart_arguments[i]);
  }

  // Τα Windows ενεργοποιούν την επανεκκίνηση μόνο αν η εφαρμογή έτρεχε
  // τουλάχιστον 60 δευτερόλεπτα (προστασία από βρόχο επανεκκινήσεων).
  ::RegisterApplicationRestart(
      restart_command_line.c_str(),
      RESTART_NO_PATCH | RESTART_NO_REBOOT);
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  // Αρχικό μέγεθος ώστε η γραμμή πεδίων Κλήσεων + κουμπί + να χωράει (rail ~280 + row 750 + padding 32 ≈ 1062).
  Win32Window::Size size(1200, 600);
  if (!window.Create(L"Καταγραφή Κλήσεων", origin, size)) {
    return EXIT_FAILURE;
  }
  RegisterCrashRestart(GetCommandLineArguments());
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
