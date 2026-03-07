# Εισαγωγή δεδομένων από Excel – αντίγραφα αρχείων

Αυτά τα αρχεία υλοποιούν τη διαδικασία εισαγωγής δεδομένων από αρχείο Excel (.xlsx) στην εφαρμογή Call Logger.

## Αρχεία (προέλευση)

| Αρχείο στο `grok/` | Πρωτότυπο path |
|--------------------|----------------|
| `import_service.dart` | `lib/core/services/import_service.dart` |
| `import_console_widget.dart` | `lib/features/calls/screens/widgets/import_console_widget.dart` |
| `import_log_provider.dart` | `lib/features/calls/provider/import_log_provider.dart` |
| `main_shell_import_excerpt.dart` | Απόσπασμα από `lib/core/widgets/main_shell.dart` (κλήση Import + UI) |

## Ροή λειτουργίας

1. **main_shell.dart**: Πλήκτρο FAB (upload) → `_onImportExcel()` → ανοίγει modal με `ImportConsoleWidget` και καλεί `ImportService().importFromExcel(onLog: ...)`.
2. **ImportService** (`import_service.dart`): FilePicker για .xlsx → `Excel.decodeBytes()` → διαβάζει φύλλα `offices`, `owners`, `equipment` και καλεί `onLog` για κάθε γραμμή.
3. **import_log_provider.dart**: Κρατά τη λίστα λογών (strings) για το Live Console.
4. **ImportConsoleWidget**: Εμφανίζει τα logs σε μαύρο φόντο με πράσινο κείμενο και auto-scroll.

## Εξαρτήσεις (pubspec)

- `excel: ^4.0.6`
- `file_picker`
- `flutter_riverpod`
- `google_fonts`

## Σημείωση

Τα imports στα αντίγραφα `import_console_widget.dart` και `main_shell_import_excerpt.dart` έχουν προσαρμοστεί για το flat structure του `grok/` (π.χ. `import_log_provider.dart` αντί για `../../provider/import_log_provider.dart`). Το `main_shell_import_excerpt.dart` είναι excerpt/σχολιασμένο για αναφορά, όχι executable as-is.
