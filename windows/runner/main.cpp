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

// Επιστρέφει τον φάκελο όπου ζει το εκτελέσιμο (χωρίς τελικό backslash), ή
// κενό string σε αποτυχία.
std::wstring ExecutableDirectory() {
  wchar_t path[MAX_PATH];
  DWORD length = ::GetModuleFileNameW(nullptr, path, MAX_PATH);
  if (length == 0 || length >= MAX_PATH) {
    return std::wstring();
  }
  std::wstring full_path(path, length);
  size_t last_separator = full_path.find_last_of(L"\\/");
  if (last_separator == std::wstring::npos) {
    return std::wstring();
  }
  return full_path.substr(0, last_separator);
}

bool PathExists(const std::wstring& path) {
  return ::GetFileAttributesW(path.c_str()) != INVALID_FILE_ATTRIBUTES;
}

// Ο φάκελος «data» δίπλα στο .exe περιέχει τη μηχανή του Flutter
// (flutter_assets, icudtl.dat, app.so) — αν λείπει ή έχει αλλοιωθεί, η εφαρμογή
// κατέρρεε ΣΙΩΠΗΛΑ. Εδώ δείχνουμε native μήνυμα με την ακριβή αιτία και την
// ενέργεια ανάκαμψης, αφού καμία οθόνη σφάλματος της εφαρμογής (που ζει στο
// Dart) δεν προλαβαίνει να εμφανιστεί.
void ShowStartupFailureMessage() {
  const std::wstring exe_dir = ExecutableDirectory();
  const std::wstring data_dir =
      exe_dir.empty() ? L"data" : (exe_dir + L"\\data");

  std::wstring message;
  if (!PathExists(data_dir)) {
    // Ο φάκελος λείπει ολόκληρος.
    message = L"Ο φάκελος:\n\n" + data_dir +
              L"\n\nδεν υπάρχει. Αυτός ο φάκελος περιέχει κρίσιμα αρχεία της "
              L"εφαρμογής. Η επανεγκατάσταση της εφαρμογής θα διορθώσει το "
              L"πρόβλημα.";
  } else if (!PathExists(data_dir + L"\\icudtl.dat") ||
             !PathExists(data_dir + L"\\flutter_assets")) {
    // Ο φάκελος υπάρχει αλλά λείπουν κρίσιμα αρχεία του.
    message = L"Ο φάκελος:\n\n" + data_dir +
              L"\n\nφαίνεται αλλοιωμένος (λείπουν κρίσιμα αρχεία της "
              L"εφαρμογής). Η επανεγκατάσταση της εφαρμογής θα διορθώσει το "
              L"πρόβλημα.";
  } else {
    // Ο φάκελος και τα βασικά αρχεία υπάρχουν, αλλά η μηχανή δεν ξεκίνησε —
    // πιθανή αλλοίωση κάποιου αρχείου μέσα στον φάκελο.
    message = L"Η εφαρμογή δεν μπόρεσε να ξεκινήσει. Ο φάκελος:\n\n" +
              data_dir +
              L"\n\nφαίνεται αλλοιωμένος. Η επανεγκατάσταση της εφαρμογής θα "
              L"διορθώσει το πρόβλημα.";
  }

  ::MessageBoxW(nullptr, message.c_str(), L"Καταγραφή Κλήσεων",
                MB_OK | MB_ICONERROR);
}

// Προληπτικός έλεγχος ΠΡΙΝ την κατασκευή της μηχανής Flutter. ΚΡΙΣΙΜΟ: με
// ελλιπή φάκελο data η μηχανή ΔΕΝ επιστρέφει αποτυχία — κρεμάει αόρατα μέσα
// στην κατασκευή του FlutterViewController (διεργασία χωρίς παράθυρο,
// επαληθευμένο 24/07/2026). Άρα ο έλεγχος στην αποτυχία του Create δεν αρκεί·
// πρέπει να προλάβουμε τη μηχανή.
bool FlutterDataLooksPresent() {
  const std::wstring exe_dir = ExecutableDirectory();
  const std::wstring data_dir =
      exe_dir.empty() ? L"data" : (exe_dir + L"\\data");
  if (!PathExists(data_dir) || !PathExists(data_dir + L"\\icudtl.dat") ||
      !PathExists(data_dir + L"\\flutter_assets")) {
    return false;
  }
  // Ο μεταγλωττισμένος κώδικας Dart: σε release/profile build είναι το app.so
  // (χωρίς αυτό η μηχανή καταρρέει σιωπηλά — επαληθευμένο 24/07/2026)· σε debug
  // build ΔΕΝ υπάρχει app.so — ο κώδικας ζει στο flutter_assets\kernel_blob.bin.
  // Δεχόμαστε όποιο από τα δύο υπάρχει, αλλιώς και τα δύο builds θα έσπαγαν.
  return PathExists(data_dir + L"\\app.so") ||
         PathExists(data_dir + L"\\flutter_assets\\kernel_blob.bin");
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

  // Ο έλεγχος γίνεται ΠΡΙΝ το DartProject/FlutterWindow: αν λείπει ο φάκελος
  // data, η μηχανή Flutter κρεμάει αόρατα αντί να αποτύχει καθαρά.
  if (!FlutterDataLooksPresent()) {
    ShowStartupFailureMessage();
    ::CoUninitialize();
    return EXIT_FAILURE;
  }

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  // Αρχικό μέγεθος ώστε η γραμμή πεδίων Κλήσεων + κουμπί + να χωράει (rail ~280 + row 750 + padding 32 ≈ 1062).
  Win32Window::Size size(1200, 600);
  if (!window.Create(L"Καταγραφή Κλήσεων", origin, size)) {
    // Η μηχανή Flutter δεν ξεκίνησε (π.χ. ελλιπής/αλλοιωμένος φάκελος data).
    // Δείξε σαφές μήνυμα αντί για σιωπηλή έξοδο.
    ShowStartupFailureMessage();
    return EXIT_FAILURE;
  }
  RegisterCrashRestart(GetCommandLineArguments());
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  // ΓΙΑΤΙ: Ζευγάρι με το RegisterCrashRestart (γρ. 91). Η μηχανή του Flutter
  // καταρρέει κατά την αποδόμησή της στα Windows (access violation 0xc0000005
  // στο FlutterWindowsView::OnHighContrastChanged — γνωστό bug του engine, όχι
  // δικό μας). Χωρίς αυτό, το Windows Error Reporting έβλεπε την κατάρρευση στο
  // κλείσιμο ως πραγματικό crash και ΞΑΝΑΝΟΙΓΕ την εφαρμογή με
  // --restarted-after-crash — εξ ου ο διάλογος «Αυτόματη επανεκκίνηση» που
  // εμφανιζόταν στους χρήστες όταν πατούσαν το Χ.
  //
  // Ηθελημένο κλείσιμο: απενεργοποιούμε την αυτόματη επανεκκίνηση ΕΔΩ, ώστε
  // ακόμη κι αν η μηχανή καταρρεύσει στο τελικό teardown, το Windows να μην
  // αναστήσει την εφαρμογή. Οι γνήσιες καταρρεύσεις ΕΝ ΛΕΙΤΟΥΡΓΙΑ (πριν φτάσουμε
  // εδώ) συνεχίζουν κανονικά να ενεργοποιούν την επανεκκίνηση — αυτό το θέλουμε.
  //
  // ΠΡΟΣΟΧΗ: Στην κανονική ροή κλεισίματος από το Dart, ο ShutdownCoordinator
  // τερματίζει με exit(0) και ο βρόχος μηνυμάτων ΔΕΝ επιστρέφει ποτέ εδώ — γι'
  // αυτό το UnregisterApplicationRestart καλείται ΚΑΙ από το Dart μέσω FFI (δες
  // ShutdownCoordinator._defaultTerminate). Η κλήση εδώ καλύπτει τις native
  // διαδρομές εξόδου (π.χ. WM_QUIT χωρίς να περάσει από τον συντονιστή).
  ::UnregisterApplicationRestart();

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
