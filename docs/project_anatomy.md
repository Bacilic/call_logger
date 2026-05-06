# Call Logger — Project Anatomy

**Ημερομηνία τροποποίησης εγγράφου:** 6 Μαΐου 2026

Συμπυκνωμένη «ακτινογραφία» για εξωτερικό LLM (Καθοδηγητής): Flutter για Windows 11, δομή ανά features/, Riverpod, SQLite μέσω sqflite_common_ffi.

---

## 1) DIRTREE (lib/)

lib/
  main.dart
  core/
    about/
      version_display.dart
      models/
        changelog_entry.dart
      providers/
        app_version_provider.dart
        changelog_provider.dart
      services/
        changelog_service.dart
      widgets/
        changelog_dialog.dart
        version_chip.dart
    config/
      app_config.dart
      audit_retention_config.dart
    database/
      calls_repository.dart
      database_access_probe.dart
      database_helper.dart
      database_init_progress_provider.dart
      database_init_result.dart
      database_init_runner.dart
      database_path_pick_flow.dart
      database_path_resolution.dart
      database_v1_schema.dart
      department_floor_migration.dart
      dictionary_repository.dart
      directory_audit_helpers.dart
      directory_repository.dart
      lock_diagnostic_service.dart
      remote_tools_repository.dart
      settings_repository.dart
      old_database/
        lamp_data_issue_type_labels.dart
        lamp_database_provider.dart
        lamp_excel_parse_int.dart
        lamp_issue_resolution_service.dart
        lamp_old_db_validator.dart
        lamp_settings_store.dart
        lamp_table_browser_api.dart
        lamp_table_greek_names.dart
        old_database_schema.dart
        old_equipment_repository.dart
        old_excel_importer.dart
        resolution_log_entry.dart
    errors/
      department_exists_exception.dart
      dictionary_export_exception.dart
    init/
      app_init_provider.dart
      app_initializer.dart
    models/
      building_map_floor.dart
      calls_screen_cards_visibility.dart
      dictionary_import_mode.dart
      remote_tool.dart
      remote_tool_arg.dart
      remote_tool_role.dart
    providers/
      directory_tab_intent_provider.dart
      equipment_focus_intent_provider.dart
      greek_dictionary_provider.dart
      history_audit_immersive_provider.dart
      lamp_open_settings_intent_provider.dart
      lexicon_categories_provider.dart
      lexicon_full_mode_provider.dart
      lexicon_language_recalc_provider.dart
      main_nav_request_provider.dart
      settings_provider.dart
      shell_navigation_intent_provider.dart
      spell_check_provider.dart
      task_focus_intent_provider.dart
      user_form_edit_intent_provider.dart
    services/
      audit_retention_runner.dart
      audit_service.dart
      building_map_storage.dart
      default_remote_tool_display.dart
      dictionary_service.dart
      excel_parser.dart
      import_service.dart
      import_types.dart
      lookup_service.dart
      master_dictionary_service.dart
      remote_args_service.dart
      remote_connection_service.dart
      remote_launcher_service.dart
      remote_tools_paths_helper.dart
      settings_service.dart
      spell_check_service.dart
    theme/
    utils/
      autocomplete_highlight_scroll.dart
      date_parser_util.dart
      department_display_utils.dart
      department_floor_sync.dart
      file_picker_initial_directory.dart
      lexicon_word_metrics.dart
      name_parser.dart
      phone_list_parser.dart
      search_debouncer.dart
      search_text_normalizer.dart
      spell_check.dart
      user_identity_normalizer.dart
    widgets/
      app_init_wrapper.dart
      app_shell_with_global_fatal_error.dart
      app_shortcuts.dart
      calendar_range_picker.dart
      database_error_screen.dart
      database_persistence_error_snackbar.dart
      global_fatal_error_notifier.dart
      lexicon_spell_menu_helper.dart
      lexicon_spell_text_form_field.dart
      main_nav_destination.dart
      main_shell.dart
      spell_check_controller.dart
  features/
    audit/
      audit.dart
      constants/
        audit_ui_mappings.dart
      models/
        audit_filter_model.dart
        audit_log_model.dart
        audit_page_result.dart
      providers/
        audit_providers.dart
      services/
        audit_entity_preview_resolver.dart
        audit_formatter_service.dart
    calls/
      models/
        call_model.dart
        equipment_model.dart
        user_model.dart
      provider/
        call_entry_provider.dart
        call_header_provider.dart
        calls_dashboard_providers.dart
        import_log_provider.dart
        lookup_provider.dart
        notes_field_hint_provider.dart
        remote_paths_provider.dart
        smart_entity_selector_provider.dart
      screens/
        calls_screen.dart
        widgets/
          call_header_form.dart
          call_status_bar.dart
          category_autocomplete_field.dart
          equipment_recent_calls_panel.dart
          global_recent_calls_list.dart
          import_console_widget.dart
          mini_map_card.dart
          notes_sticky_field.dart
          recent_calls_list.dart
          remote_connection_buttons.dart
          smart_entity_selector_caller_presentational.dart
          smart_entity_selector_phone_presentational.dart
          smart_entity_selector_widget.dart
          sticky_note_widget.dart
          user_info_card.dart
      utils/
        call_remote_targets.dart
        equipment_remote_param_key.dart
        remote_target_rules.dart
        vnc_remote_target.dart
    database/
      models/
        database_backup_settings.dart
        database_stats.dart
      providers/
        backup_scheduler_provider.dart
        database_backup_settings_provider.dart
        database_browser_stats_provider.dart
        database_maintenance_provider.dart
      screens/
        database_browser_screen.dart
      services/
        database_backup_service.dart
        database_exit_backup.dart
        database_maintenance_service.dart
        database_stats_service.dart
      utils/
        backup_destination_folder_validator.dart
        backup_destination_location_warnings.dart
        backup_location_hints.dart
        backup_schedule_utils.dart
      widgets/
        database_maintenance_panel.dart
        database_rename_failure_dialog.dart
        database_settings_panel.dart
    dictionary/
      dictionary_table_layout.dart
      providers/
        lexicon_scroll_provider.dart
      screens/
        dictionary_manager_screen.dart
      widgets/
        dictionary_grid_row.dart
        dictionary_settings_dialog.dart
    directory/
      building_map/
        building_map_geometry.dart
        building_map_label_layout.dart
        building_map_sheet_export_key.dart
        controllers/
          building_map_controller.dart
        providers/
          building_map_providers.dart
        screens/
          building_map_dialog.dart
        services/
          building_map_sheet_export.dart
          building_map_sheet_export_save_path.dart
        widgets/
          building_map_commit_color_dialog.dart
          building_map_department_search_field.dart
          building_map_edit_toolbar.dart
          building_map_empty_canvas_message.dart
          building_map_fill_color_dialog.dart
          building_map_floor_departments_dialog.dart
          building_map_floor_menu_button.dart
          building_map_floors_body.dart
          building_map_omnisearch_field.dart
          building_map_sheet_painter.dart
          building_map_sheet_viewport.dart
          department_selection_overlay.dart
          map_rotation_pod.dart
          views/
            building_map_edit_layout.dart
            building_map_view_layout.dart
      models/
        category_directory_column.dart
        category_model.dart
        department_directory_column.dart
        department_floor_display_extension.dart
        department_model.dart
        equipment_column.dart
        non_user_phone_entry.dart
        user_catalog_mode.dart
        user_directory_column.dart
      providers/
        category_directory_provider.dart
        department_directory_provider.dart
        directory_provider.dart
        equipment_directory_provider.dart
      screens/
        directory_screen.dart
        widgets/
          bulk_department_edit_dialog.dart
          bulk_equipment_edit_dialog.dart
          bulk_user_edit_dialog.dart
          catalog_column_selector_shell.dart
          categories_data_table.dart
          categories_tab.dart
          category_form_dialog.dart
          category_undo_snackbar.dart
          department_color_palette.dart
          department_form_dialog.dart
          department_transfer_confirm_dialog.dart
          departments_data_table.dart
          departments_tab.dart
          equipment_data_table.dart
          equipment_form_dialog.dart
          equipment_settings_dialog.dart
          equipment_tab.dart
          homonym_warning_dialog.dart
          miscellaneous_tab.dart
          non_user_phones_data_table.dart
          user_form_dialog.dart
          user_form_smart_text_field.dart
          user_name_change_confirm_dialog.dart
          users_data_table.dart
          users_tab.dart
    floor_map/
      services/
        floor_color_assignment_service.dart
    history/
      models/
        dashboard_filter_model.dart
        dashboard_summary_model.dart
      providers/
        dashboard_provider.dart
        history_application_audit_view_provider.dart
        history_provider.dart
      screens/
        dashboard_screen.dart
        history_screen.dart
      widgets/
        application_audit_tab.dart
        audit_before_after_section.dart
        audit_entity_side_panel.dart
        lansweeper_report_dialog.dart
        audit_entity_previews/
          audit_entity_preview_body.dart
          audit_preview_column.dart
          backup_preview_widget.dart
          call_preview_widget.dart
          equipment_preview_widget.dart
          settings_preview_widget.dart
          task_preview_widget.dart
          user_preview_widget.dart
    lamp/
      screens/
        lamp_screen.dart
      widgets/
        lamp_db_tables_tab.dart
        lamp_issue_manual_review_dialog.dart
        lamp_resolution_progress_dialog.dart
        lamp_result_card.dart
        lamp_unresolved_resolution_dialog.dart
    settings/
      screens/
        remote_tools_management_screen.dart
        settings_screen.dart
      widgets/
        create_new_database_dialog.dart
        remote_tool_form_dialog.dart
    tasks/
      models/
        task.dart
        task_analytics_filter.dart
        task_analytics_summary.dart
        task_filter.dart
        task_settings_config.dart
      providers/
        pending_task_delete_provider.dart
        task_analytics_provider.dart
        task_service_provider.dart
        task_settings_config_provider.dart
        tasks_provider.dart
      screens/
        task_card.dart
        task_close_dialog.dart
        task_filter_bar.dart
        task_form_dialog.dart
        task_settings_dialog.dart
        tasks_screen.dart
      services/
        task_service.dart
      ui/
        task_due_option_tooltips.dart
      widgets/
        task_analytics_bottom_sheet.dart

## 2) DATABASE SCHEMA (SQLite)

Πηγή: core/database/database_v1_schema.dart και core/database/database_helper.dart.

Τρέχουσα schema version: 26.

Πίνακες / στήλες (όνομα -> τύπος SQLite):

- calls: id INTEGER, date TEXT, time TEXT, caller_id INTEGER, equipment_id INTEGER, caller_text TEXT, phone_text TEXT, department_text TEXT, equipment_text TEXT, issue TEXT, solution TEXT, category_text TEXT, category_id INTEGER, status TEXT, duration INTEGER, is_priority INTEGER, search_index TEXT, is_deleted INTEGER
- users: id INTEGER, last_name TEXT, first_name TEXT, department_id INTEGER, location TEXT, notes TEXT, is_deleted INTEGER
- phones: id INTEGER, number TEXT, department_id INTEGER
- department_phones: department_id INTEGER, phone_id INTEGER
- user_phones: user_id INTEGER, phone_id INTEGER
- equipment: id INTEGER, code_equipment TEXT, type TEXT, notes TEXT, custom_ip TEXT, anydesk_id TEXT, remote_params TEXT, default_remote_tool TEXT, department_id INTEGER, location TEXT, is_deleted INTEGER
- user_equipment: user_id INTEGER, equipment_id INTEGER
- departments: id INTEGER, name TEXT, name_key TEXT, building TEXT, color TEXT, notes TEXT, map_floor TEXT, map_x REAL, map_y REAL, map_width REAL, map_height REAL, map_rotation REAL, map_label_offset_x REAL, map_label_offset_y REAL, map_anchor_offset_x REAL, map_anchor_offset_y REAL, map_custom_name TEXT, group_name TEXT, floor_id INTEGER, is_deleted INTEGER, map_hidden INTEGER
- building_map_floors: id INTEGER, sort_order INTEGER, label TEXT, floor_group TEXT, image_path TEXT, rotation_degrees REAL
- categories: id INTEGER, name TEXT, is_deleted INTEGER
- tasks: id INTEGER, title TEXT, description TEXT, due_date TEXT, snooze_history_json TEXT, status TEXT, call_id INTEGER, priority INTEGER, solution_notes TEXT, snooze_until TEXT, caller_id INTEGER, equipment_id INTEGER, department_id INTEGER, phone_id INTEGER, phone_text TEXT, user_text TEXT, equipment_text TEXT, department_text TEXT, created_at TEXT, updated_at TEXT, origin TEXT, search_index TEXT, is_deleted INTEGER
- knowledge_base: id INTEGER, topic TEXT, content TEXT, tags TEXT
- audit_log: id INTEGER, action TEXT, timestamp TEXT, user_performing TEXT, details TEXT, entity_type TEXT, entity_id INTEGER, entity_name TEXT, search_text TEXT, old_values_json TEXT, new_values_json TEXT
- app_settings: key TEXT, value TEXT
- remote_tools: id INTEGER, name TEXT, role TEXT, executable_path TEXT, launch_mode TEXT, sort_order INTEGER, is_active INTEGER, suggested_values TEXT, icon_asset_key TEXT, arguments_json TEXT, test_target_ip TEXT, is_exclusive INTEGER, deleted_at TEXT
- remote_tool_args: id INTEGER, remote_tool_id INTEGER, tool_name TEXT, arg_flag TEXT, description TEXT, is_active INTEGER
- user_dictionary: word TEXT, language TEXT, letters_count INTEGER, diacritic_mark_count INTEGER
- full_dictionary: id INTEGER, word TEXT, normalized_word TEXT, source TEXT, language TEXT, category TEXT, created_at TEXT, letters_count INTEGER, diacritic_mark_count INTEGER

## 3) MODELS

Βήμα Α — Κατάλογοι models/

- features/audit/models: AuditFilterModel, AuditLogModel, AuditPageResult
- features/calls/models: CallModel, EquipmentModel, UserModel
- features/database/models: DatabaseBackupSettings, DatabaseStats, DatabaseBackupNamingFormat(enum), DatabaseBackupInterval(enum)
- features/directory/models: CategoryModel, DepartmentModel, CategoryDirectoryColumn, DepartmentDirectoryColumn, EquipmentColumn, UserDirectoryColumn, NonUserPhoneEntry, UserCatalogMode(enum), EquipmentRow(typedef)
- features/history/models: DashboardFilterModel, DashboardSummaryModel, DepartmentStat, IssueStat, DailyTrendPoint, CallerStat, LongestCallEntry, HourlyBucket
- features/tasks/models: Task, TaskSnoozeEntry, TaskStatus(enum), TaskFilter, TaskSortOption(enum), TaskSettingsConfig, TaskAnalyticsFilter, TaskAnalyticsSummary, TaskAnalyticsOriginSlice, TaskAnalyticsBacklogPoint
- core/models: BuildingMapFloor, CallsScreenCardsVisibility, RemoteToolArgument, RemoteTool, RemoteToolArg, DictionaryImportMode(enum), ToolRole(enum)

Βήμα Β — Μοντέλα εκτός models/

- features/history/providers/history_provider.dart: HistoryFilterModel

Βήμα Γ — Σημαντικοί data/result τύποι

- DatabaseStatus, DatabaseInitResult, DatabaseInitException
- DatabaseInitRunnerResult
- DatabaseInitProgressState
- ConnectionCheckResult, TablePreviewResult
- AppInitResult
- AuditRetentionConfig
- ImportResult
- LookupResult
- ImportLogLevel(enum)
- CallEntryState
- ImportLogEntry
- LookupLoadResult
- SmartEntitySelectorState, OrphanQuickAddResult
- DirectoryState
- CategoryDirectoryState
- DepartmentDirectoryState
- EquipmentDirectoryState, EquipmentDeleteUndoEntry
- BuildingMapFloorDeleteChoice
- ReplaceDatabaseResult
- DatabaseBackupResult
- BackupDestinationValidationResult
- TaskStatus(enum), TaskSnoozeEntry

Βήμα Δ — Συσχετισμένοι τύποι στο ίδιο αρχείο

- dashboard_summary_model.dart: DepartmentStat, IssueStat, DailyTrendPoint, CallerStat, LongestCallEntry, HourlyBucket
- task.dart: TaskSnoozeEntry, TaskStatus
- task_analytics_summary.dart: TaskAnalyticsOriginSlice, TaskAnalyticsBacklogPoint
- equipment_column.dart: EquipmentRow(typedef)

## 4) STATE MANAGEMENT — PROVIDERS (Riverpod)

- appInitProvider: αρχικοποίηση εφαρμογής και post-init βήματα.
- databaseInitProgressProvider: πρόοδος/διαγνωστικά ανοίγματος βάσης.
- lookupServiceProvider: in-memory κατάλογος για lookups.
- directoryProvider, categoryDirectoryProvider, departmentDirectoryProvider, equipmentDirectoryProvider: state/CRUD καταλόγου.
- callEntryProvider, callSmartEntityProvider, taskSmartEntityProvider: state φόρμας κλήσης και smart επιλογές.
- tasksProvider, taskFilterProvider, taskStatusCountsProvider, globalPendingTasksCountProvider, orphanCallsProvider: state εκκρεμοτήτων.
- historyFilterProvider, historyCallsProvider, historyCategoriesProvider, historyCategoryEntriesProvider: ιστορικό κλήσεων.
- dashboardFilterProvider, dashboardStatsProvider, dashboardCallsForReportProvider, dashboardDepartmentsProvider, lansweeperUrlProvider: dashboard/αναφορές.
- audit providers (audit_providers.dart): φίλτρα, λίστα, side panel, preview.
- databaseBackupSettingsProvider, backupSchedulerProvider, databaseBrowserStatsProvider, databaseMaintenanceServiceProvider: backup/maintenance.
- buildingMap providers: selected floor/department, tool mode, draft shape, undo, viewport requests.
- remote providers (remote_paths_provider.dart): catalog εργαλείων, valid paths, launcher status, remote services.
- navigation/intent providers: mainNavRequestProvider, shellNavigationIntentProvider, directoryTabIntentProvider, taskFocusIntentProvider, equipmentFocusIntentProvider, userFormEditIntentProvider.

## 5) DEPENDENCIES (pubspec.yaml)

dependencies:
- flutter (sdk)
- flutter_localizations (sdk)
- cupertino_icons: ^1.0.9
- flutter_riverpod: ^3.3.1
- sqflite_common: ^2.5.6
- sqflite_common_ffi: ^2.4.0+2
- sqlite3_flutter_libs: ^0.6.0+eol
- path_provider: ^2.1.2
- path: ^1.9.0
- google_fonts: ^8.0.2
- intl: ^0.20.2
- characters: ^1.4.0
- window_manager: ^0.5.1
- screen_retriever: ^0.2.0
- shared_preferences: ^2.5.5
- url_launcher: ^6.3.0
- excel: ^4.0.6
- file_picker: 11.0.2
- fl_chart: ^1.2.0
- archive: ^3.6.1
- win32: ^5.15.0
- ffi: ^2.2.0
- custom_mouse_cursor: ^1.1.3
- package_info_plus: ^8.3.0
- image: 4.3.0

dev_dependencies:
- flutter_test (sdk)
- integration_test (sdk)
- riverpod: ^3.2.1
- flutter_lints: ^6.0.0

*Τέλος εγγράφου — ενημερώστε την ημερομηνία όταν αλλάζει ουσιαστικά το σχήμα ή η δομή.*
