# Αντιστοίχιση Λειτουργικών Περιοχών → Ελέγχοι (scope map)

**Ημερομηνία:** 18 Ιουνίου 2026  
**Σκοπός:** Πηγή αλήθειας για **δρομολόγηση ελέγχων** (βλ. `.cursorrules` §7). Μετά από αλλαγή σε `lib/`, εκτέλεσε μόνο τους φακέλους/αρχεία που αναφέρονται στη γραμμή της περιοχής — συν τυχόν διασταυρούμενες εξαρτήσεις.

**Έκδοση σχήματος βάσης (αντιστοιχία `test/core/database/`):** `databaseSchemaVersionV1 = 31` (`lib/core/database/database_v1_schema.dart`). Με bump έκδοσης schema, ενημέρωσε τα tests migration/schema και αυτή τη γραμμή.

**Εξαιρέσεις (πάντα πλήρης σουίτα `flutter test`):**
- `test/test_setup.dart`
- `test/test_reporter.dart`
- `test/call_logger_test_material_app.dart`

**Κοινή υποδομή (όχι feature scope):** `test/helpers/`, `test/widget_test.dart` (smoke).

---

## Πίνακας αντιστοίχισης

| Λειτουργική περιοχή | Διαδρομές `lib/` | Φάκελος / αρχεία `test/` | Διασταυρούμενες εξαρτήσεις (επιπλέον έλεγχοι) |
|---------------------|------------------|---------------------------|-----------------------------------------------|
| **Κλήσεις** | `lib/features/calls/` | `test/features/calls/` (+ `test/features/calls/layout/` για layout engine & field groups) | `test/core/services/lookup_service` (μέσω `test_setup` + `LookupService`), `test/core/database/calls_repository_history_actions_test.dart`, `test/core/utils/user_homonym_finder_test.dart`, `test/core/services/remote_launcher_placeholders_test.dart`, `test/helpers/association_two_step_*.dart` |
| **Εκκρεμότητες** | `lib/features/tasks/` | `test/features/tasks/` | `test/features/calls/` (ροή pending μέσω `call_entry_provider`), `test/core/database/` |
| **Ιστορικό & πίνακας ελέγχου** | `lib/features/history/` | `test/features/history/` | `test/core/database/calls_repository_history_actions_test.dart`, `test/features/audit/`, `test/core/services/lansweeper_ticket_requester_fields_test.dart` |
| **Κατάλογος** | `lib/features/directory/` | `test/features/directory/` | `directory_user_search_test.dart` (αναζήτηση χρήστη)· `screens/widgets/department_form_dialog_test.dart` (μικτή σύγκρουση κοινόχρηστων τμήματος)· `test/core/utils/user_homonym_finder_test.dart`, `natural_string_compare_test.dart`· `LookupService` → `test/features/calls/` (αν αλλάζει lookup cache) |
| **Χάρτης κτιρίου** | `lib/features/directory/building_map/` | *(δεν υπάρχει φάκελος `test/features/directory/building_map/`)* | `test/features/directory/` (κατάλογος τμημάτων — όχι UI χάρτη)· `lib/core/services/building_map_storage.dart` — **δεν έχει** αντίστοιχο αρχείο στο `test/core/services/` (ούτε αλλού στο `test/`) |
| **Λεξικό** | `lib/features/dictionary/` | `test/features/dictionary/` | `test/core/providers/` (`core_lexicon_*`, `greek_dictionary_load`), `test/core/services/core_lexicon_validation_test.dart`, `test/core/utils/lexicon_word_metrics_test.dart`, `test/core/services/lexicon_spell_check_service_test.dart`, `test/core/services/spelling_lookup_gemini_service_test.dart`, `test/core/widgets/lexicon_spell_menu_helper_test.dart` |
| **Audit (εφαρμογής)** | `lib/features/audit/` | `test/features/audit/` | `test/core/database/migrate_v18_audit_test.dart` |
| **Βάση & backup (UI)** | `lib/features/database/` | `test/features/database/` | `test/core/database/` (schema, repositories), `test/core/services/application_reset_unconfigured_test.dart` |
| **Λάμπα (LAMP)** | `lib/features/lamp/` | `test/features/lamp/` | `test/core/database/old_database/` (validator, import, schema, equipment) |
| **Ρυθμίσεις** | `lib/features/settings/` | *(δεν υπάρχει ακόμη)* | `test/core/services/application_reset_unconfigured_test.dart`, `test/core/config/`, `test/features/database/` (πάνελ βάσης) |
| **Χρωματισμός ορόφου** | `lib/features/floor_map/` | *(δεν υπάρχει φάκελος `test/features/floor_map/`)* | `lib/features/directory/building_map/` — επίσης χωρίς dedicated tests (βλ. γραμμή «Χάρτης κτιρίου») |
| **Πυρήνας · config** | `lib/core/config/` | `test/core/config/` | — |
| **Πυρήνας · βάση δεδομένων** | `lib/core/database/` | `test/core/database/` | Όλα τα widget tests που χρησιμοποιούν `test_setup.dart` αν αλλάζει schema/seed |
| **Πυρήνας · providers** | `lib/core/providers/` | `test/core/providers/` | `test/core/services/core_lexicon_*`, `test/features/dictionary/`, `test/features/calls/` (spell check nav) |
| **Πυρήνας · services** | `lib/core/services/` | `test/core/services/` | Βλ. ανά service παρακάτω |
| **Πυρήνας · utils** | `lib/core/utils/` | `test/core/utils/` | Feature που εισάγει το util (π.χ. `linkable_text_parser` → audit, history) |
| **Πυρήνας · widgets** | `lib/core/widgets/` | `test/core/widgets/` | **Με πλήρες κέλυφος** (`MyApp` / `CallLoggerTestMaterialApp` → `AppInitWrapper` → `AppShortcuts` → `main_shell.dart`): `test/widget_test.dart`, `test/features/calls/call_form_test.dart`, `call_validation_test.dart`, `test/features/history/history_search_test.dart`, `test/features/directory/directory_user_search_test.dart`, `test/features/tasks/pending_task_test.dart`. **Χωρίς κέλυφος:** `test/core/widgets/lexicon_spell_menu_helper_test.dart` (μόνο helper)· feature-isolated widgets (`equipment_*_test`, `lamp_result_card_test`) — δεν απαιτούν τα παραπάνω. Αλλαγή σε `main_shell`, `app_shortcuts`, `nav_rail`, `main_nav_destination` → μόνο τα 6 αρχεία της πρώτης ομάδας, όχι ολόκληρη η σουίτα widget. |
| **Πυρήνας · about** | `lib/core/about/` | *(δεν υπάρχει ακόμη)* | — |
| **Πυρήνας · init** | `lib/core/init/` | *(μόνο έμμεσα μέσω widget tests)* | `test/widget_test.dart`, `test/test_setup.dart` |
| **Πυρήνας · errors** | `lib/core/errors/` | *(δεν υπάρχει ακόμη)* | Feature tests που ρίχνουν τα exceptions |
| **Πυρήνας · models** | `lib/core/models/` | *(δεν υπάρχει ακόμη)* | Feature tests που χρησιμοποιούν τα μοντέλα |
| **Εκκίνηση** | `lib/main.dart` | `test/widget_test.dart` | Πλήρης σουίτα αν αλλάζει δομή `MyApp` / providers εκκίνησης |

### Διασταυρούμενα core services (πολλαπλά features)

| Module `lib/core/services/` | Features που το χρησιμοποιούν | `test/` |
|-----------------------------|------------------------------|---------|
| `lookup_service.dart` | calls, directory, history, tasks | `test/features/calls/`, `test/features/directory/`, `test_setup.dart` |
| `core_lexicon_service.dart`, `core_lexicon_validation.dart` | dictionary, calls, history (ορθογραφία) | `test/core/providers/`, `test/core/services/core_lexicon_validation_test.dart`, `test/features/dictionary/` |
| `dictionary_service.dart` | dictionary, spell check | `test/core/providers/greek_dictionary_load_test.dart` |
| `lexicon_spell_check_service.dart`, `spelling_lookup_gemini_service.dart` | dictionary, calls, history (Lansweeper) | `test/core/services/lexicon_spell_check_service_test.dart`, `spelling_lookup_gemini_service_test.dart` |
| `remote_launcher_service.dart`, `remote_args_service.dart` | calls, settings | `test/core/services/remote_launcher_placeholders_test.dart`, `test/features/calls/call_remote_targets_test.dart` |
| `lansweeper_ticket_requester_fields.dart` | history (Lansweeper) | `test/core/services/lansweeper_ticket_requester_fields_test.dart` |
| `application_reset_service.dart`, `settings_service.dart` | settings, database init | `test/core/services/application_reset_unconfigured_test.dart` |
| `audit_service.dart`, `audit_formatter_service.dart` | audit, history | `test/features/audit/` |

---

## Εντολές στοχευμένης εκτέλεσης (παραδείγματα)

```bash
# Αλλαγή μόνο σε lib/features/calls/
flutter test test/features/calls/

# Αλλαγή σε lookup_service — και calls και directory
flutter test test/features/calls/ test/features/directory/

# Αλλαγή σε test_setup — πλήρης σουίτα
flutter test
```

---

## Ελλείψεις Κάλυψης Ελέγχων

Λειτουργικές περιοχές του `lib/` **χωρίς** αντίστοιχο αρχείο στο `test/` (μετά την αναδιάρθρωση Ιουνίου 2026). Λίστα υπενθύμισης για σταδιακή συμπλήρωση — **όχι** άμεση εργασία.

### `lib/core/`

| Περιοχή | Σημειώσεις |
|---------|------------|
| `core/about/` | Changelog, έκδοση εφαρμογής — χωρίς unit tests |
| `core/directory/phone_department_policy.dart` | Πολιτική τηλεφώνων τμήματος |
| `core/errors/` | Τύποι εξαιρέσεων αποθήκευσης |
| `core/init/` | `app_initializer`, `app_init_provider` — μόνο έμμεσα μέσω widget tests |
| `core/models/` | Remote tools, building map floor, window placement |
| `core/providers/` (πληθώρα) | `settings_provider`, `spell_check_provider`, navigation intents, `greek_dictionary_provider`, κ.λπ. — καλύπτονται μόνο μερικώς (`core_lexicon_nav_visibility`) |
| `core/services/` (πολλά) | `audit_service`, `audit_retention_runner`, `building_map_storage`, `desktop_window_service`, `gemini_ticket_service`, `lansweeper_sync_service`, `lansweeper_*_probe`, `master_dictionary_service`, `remote_connection_service`, `settings_service` (πέρα από reset), `spell_check_service` (άμεσα), `backup_reset_metadata` |
| `core/theme/` | — |
| `core/widgets/` (πληθώρα) | `main_shell`, `app_shortcuts`, `calendar_range_picker`, `fatal_error_screen`, `spell_check_controller`, κ.λπ. — μόνο `lexicon_spell_menu_helper` |

### `lib/features/`

| Περιοχή | Σημειώσεις / πρόσφατα στο CHANGELOG |
|---------|--------------------------------------|
| `features/settings/` | Οθόνη ρυθμίσεων, remote tools management, «Ξεκίνα από την αρχή» |
| `features/floor_map/` | `floor_color_assignment_service` |
| `features/directory/building_map/` | Χάρτης κτιρίου — ετικέτες, resize, omnisearch, export (CHANGELOG Unreleased 0.14+) |
| `features/directory/` (μερική κάλυψη) | Υπάρχει `directory_user_search_test.dart` (αναζήτηση χρήστη)· `department_form_dialog_test.dart` (μικτή σύγκρουση κοινόχρηστων)· `equipment_data_table_test`, `equipment_tab_test`· λείπουν departments/users tabs, building map, υπόλοιπες φόρμες |
| `features/history/` (μερική κάλυψη) | Υπάρχει `history_search_test.dart` (αναζήτηση ιστορικού)· λείπουν dashboard, επεξεργασία κλήσης, Lansweeper UI/sync, application audit tab |
| `features/dictionary/` (μερική κάλυψη) | Μόνο `dictionary_table_layout`· λείπουν οθόνη διαχείρισης, πάνελ ορθογραφίας, φίλτρα λίστας (CHANGELOG Unreleased) |
| `features/tasks/` (μερική κάλυψη) | Μόνο ροή pending μέσω κλήσης· λείπουν οθόνη εκκρεμοτήτων, analytics, φόρμα κλεισίματος |
| `features/database/debug/` | Integrity debug seeder / error scenarios |
| `features/calls/screens/widgets/` (μερική) | Smart entity selector καλύπτεται· λείπουν mini map, remote buttons, recent calls panels |
| `features/lamp/` (μερική) | Μόνο `lamp_result_card` golden· λείπουν controllers, import, integrity, settings |

### Άλλα

| Στοιχείο | Σημειώσεις |
|----------|------------|
| `integration_test/` | Υπάρχει `call_logger_integration_test.dart` — ξεχωριστό από `test/` αλλά όχι ανά feature |
| End-to-end ροές | Πλήρης καταγραφή κλήσης &lt; 2 s, global hotkeys, custom titlebar — χωρίς dedicated tests |

---

*Ενημερώστε αυτό το έγγραφο όταν προστίθενται νέα test αρχεία ή αλλάζει ουσιαστικά η δομή `lib/`.*
