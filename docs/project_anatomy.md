# Call Logger — Project Anatomy

**Ημερομηνία τροποποίησης εγγράφου:** 14 Μαΐου 2026

Συμπυκνωμένη «ακτινογραφία» για εξωτερικό LLM (Καθοδηγητής): Flutter για Windows 11, δομή ανά features/, Riverpod, SQLite μέσω sqflite_common_ffi.

---

## 1) DIRTREE (lib/)

```
lib/
  main.dart
  core/
    about/
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
        version_display.dart
    config/
        app_config.dart
        audit_retention_config.dart
    database/
      old_database/
          equipment_set_master_cycle.dart
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
        user_delete_phone_policy.dart
    debug/
    directory/
        phone_department_policy.dart
    errors/
        app_error_result.dart
        call_save_exception.dart
        department_exists_exception.dart
        dictionary_export_exception.dart
        task_save_exception.dart
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
        window_placement_mode.dart
    providers/
        app_profile_provider.dart
        application_reset_provider.dart
        core_lexicon_provider.dart
        directory_tab_intent_provider.dart
        equipment_focus_intent_provider.dart
        greek_dictionary_provider.dart
        history_audit_immersive_provider.dart
        lamp_open_settings_intent_provider.dart
        lamp_read_path_health_provider.dart
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
        application_prefs_snapshot.dart
        application_reset_service.dart
        audit_retention_runner.dart
        audit_service.dart
        backup_reset_metadata.dart
        building_map_storage.dart
        core_lexicon_service.dart
        core_lexicon_validation.dart
        default_remote_tool_display.dart
        desktop_window_service.dart
        dictionary_service.dart
        lansweeper_agent_api_probe.dart
        lansweeper_helpdesk_login_probe.dart
        lansweeper_sync_service.dart
        lansweeper_ticket_requester_fields.dart
        lookup_service.dart
        master_dictionary_service.dart
        portable_lamp_storage.dart
        portable_tool_image_storage.dart
        remote_args_service.dart
        remote_connection_service.dart
        remote_launcher_service.dart
        remote_tools_paths_helper.dart
        settings_service.dart
        spell_check_service.dart
    theme/
        .gitkeep
    utils/
        autocomplete_highlight_scroll.dart
        bundled_dictionary_assets.dart
        date_parser_util.dart
        department_display_utils.dart
        department_floor_sync.dart
        file_picker_initial_directory.dart
        file_picker_session.dart
        history_entity_display_utils.dart
        lexicon_word_metrics.dart
        linkable_text_parser.dart
        name_parser.dart
        phone_list_parser.dart
        safe_file_base_name.dart
        search_debouncer.dart
        search_text_normalizer.dart
        spell_check.dart
        user_identity_normalizer.dart
        windows_cli_error_dialog.dart
        windows_file_name_validation.dart
        windows_save_sqlite_database_dialog.dart
    widgets/
        .gitkeep
        app_init_wrapper.dart
        app_shell_with_global_fatal_error.dart
        app_shortcuts.dart
        calendar_range_picker.dart
        database_error_screen.dart
        database_persistence_error_snackbar.dart
        deleted_catalog_entity_text.dart
        ellipsis_tooltip_text.dart
        fatal_error_screen.dart
        global_fatal_error_notifier.dart
        lexicon_spell_menu_helper.dart
        lexicon_spell_text_form_field.dart
        linkable_selectable_text.dart
        main_nav_destination.dart
        main_shell.dart
        nav_rail_attention_badge.dart
        remote_tool_icon.dart
        spell_check_controller.dart
  features/
    audit/
      constants/
          audit_ui_mappings.dart
      models/
          audit_filter_model.dart
          audit_log_model.dart
          audit_page_result.dart
          audit_reference_labels.dart
      providers/
          audit_providers.dart
      services/
          audit_entity_preview_resolver.dart
          audit_formatter_service.dart
          audit_reference_label_resolver.dart
        audit.dart
    calls/
      debug/
      models/
          .gitkeep
          call_model.dart
          equipment_model.dart
          user_model.dart
      provider/
          .gitkeep
          call_entry_provider.dart
          call_header_provider.dart
          calls_dashboard_providers.dart
          lookup_provider.dart
          notes_field_hint_provider.dart
          remote_paths_provider.dart
          smart_entity_selector_provider.dart
      screens/
        widgets/
            call_header_form.dart
            call_status_bar.dart
            category_autocomplete_field.dart
            equipment_recent_calls_panel.dart
            global_recent_calls_list.dart
            mini_map_card.dart
            notes_sticky_field.dart
            recent_calls_list.dart
            remote_connection_buttons.dart
            smart_entity_selector_caller_field.dart
            smart_entity_selector_caller_presentational.dart
            smart_entity_selector_department_field.dart
            smart_entity_selector_equipment_field.dart
            smart_entity_selector_equipment_models.dart
            smart_entity_selector_equipment_suggestion_list.dart
            smart_entity_selector_overlay_utils.dart
            smart_entity_selector_phone_field.dart
            smart_entity_selector_phone_presentational.dart
            smart_entity_selector_phone_suggestion_list.dart
            smart_entity_selector_phone_utils.dart
            smart_entity_selector_widget.dart
            sticky_note_widget.dart
            text_layout_utils.dart
            user_info_card.dart
          .gitkeep
          calls_screen.dart
      utils/
          call_remote_targets.dart
          equipment_remote_param_key.dart
          remote_target_rules.dart
          vnc_remote_target.dart
    database/
      models/
          database_backup_settings.dart
          database_integrity_finding.dart
          database_integrity_report.dart
          database_stats.dart
      providers/
          backup_scheduler_provider.dart
          database_backup_settings_provider.dart
          database_browser_stats_provider.dart
          database_integrity_provider.dart
          database_maintenance_provider.dart
      screens/
          database_browser_screen.dart
      services/
          database_backup_audit.dart
          database_backup_service.dart
          database_exit_backup.dart
          database_integrity_service.dart
          database_maintenance_service.dart
          database_stats_service.dart
      utils/
          backup_destination_folder_validator.dart
          backup_destination_location_warnings.dart
          backup_location_hints.dart
          backup_schedule_status.dart
          backup_schedule_utils.dart
          portable_backup_availability.dart
      widgets/
          backup_folder_missing_dialog.dart
          database_integrity_panel.dart
          database_maintenance_panel.dart
          database_rename_failure_dialog.dart
          database_settings_panel.dart
    dictionary/
      providers/
          lexicon_scroll_provider.dart
      screens/
          dictionary_manager_screen.dart
      widgets/
          core_lexicon_setup_dialog.dart
          dictionary_grid_row.dart
          dictionary_settings_dialog.dart
        dictionary_table_layout.dart
    directory/
      building_map/
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
          views/
              building_map_edit_layout.dart
              building_map_view_layout.dart
            building_map_commit_color_dialog.dart
            building_map_department_search_field.dart
            building_map_edit_toolbar.dart
            building_map_empty_canvas_message.dart
            building_map_fill_color_dialog.dart
            building_map_floor_departments_dialog.dart
            building_map_floor_edit_preview.dart
            building_map_floor_menu_button.dart
            building_map_floors_body.dart
            building_map_omnisearch_field.dart
            building_map_portable_image_copy_dialog.dart
            building_map_sheet_painter.dart
            building_map_sheet_viewport.dart
            department_selection_overlay.dart
            map_rotation_pod.dart
          building_map_geometry.dart
          building_map_label_layout.dart
          building_map_sheet_export_key.dart
      models/
          .gitkeep
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
            department_color_picker_dialog.dart
            department_form_dialog.dart
            department_palette_actions.dart
            department_palette_host.dart
            department_palette_store.dart
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
            shared_asset_disconnect_dialog.dart
            user_form_dialog.dart
            user_form_smart_text_field.dart
            user_name_change_confirm_dialog.dart
            user_phone_department_conflict_dialog.dart
            users_data_table.dart
            users_tab.dart
          .gitkeep
          directory_screen.dart
      services/
          shared_asset_disconnect_apply.dart
      widgets/
    floor_map/
      services/
          floor_color_assignment_service.dart
    history/
      models/
          dashboard_date_preset.dart
          dashboard_filter_model.dart
          dashboard_summary_model.dart
          lansweeper_sync_state.dart
      providers/
          dashboard_provider.dart
          history_application_audit_view_provider.dart
          history_call_actions_provider.dart
          history_provider.dart
          lansweeper_sync_provider.dart
      screens/
          dashboard_cards.dart
          dashboard_charts.dart
          dashboard_filter_pane.dart
          dashboard_palette_colors.dart
          dashboard_screen.dart
          history_screen.dart
      services/
          history_call_actions_service.dart
      widgets/
        audit_entity_previews/
            audit_entity_preview_body.dart
            audit_preview_column.dart
            backup_preview_widget.dart
            call_preview_widget.dart
            equipment_preview_widget.dart
            settings_preview_widget.dart
            task_preview_widget.dart
            user_preview_widget.dart
        lansweeper/
            lansweeper_connection_settings_dialog.dart
            lansweeper_state_badge.dart
            lansweeper_sync_form.dart
            lansweeper_url_rules.dart
            sync_history_list.dart
          application_audit_tab.dart
          audit_before_after_section.dart
          audit_entity_side_panel.dart
          call_delete_dialog.dart
          call_edit_dialog.dart
          history_deleted_entity_text.dart
          lansweeper_report_dialog.dart
    lamp/
      screens/
          lamp_screen.dart
      services/
          lamp_migration_service.dart
      widgets/
          lamp_db_tables_tab.dart
          lamp_issue_manual_review_dialog.dart
          lamp_resolution_progress_dialog.dart
          lamp_result_card.dart
          lamp_transfer_wizard_dialog.dart
          lamp_unresolved_resolution_dialog.dart
    settings/
      screens/
          remote_tools_management_screen.dart
          settings_screen.dart
      widgets/
          create_new_database_dialog.dart
          pending_reset_database_screen.dart
          remote_tool_form_dialog.dart
          start_from_beginning_flow.dart
    tasks/
      models/
          .gitkeep
          task.dart
          task_analytics_date_preset.dart
          task_analytics_filter.dart
          task_analytics_summary.dart
          task_filter.dart
          task_settings_config.dart
      providers/
          pending_task_delete_provider.dart
          task_analytics_date_provider.dart
          task_analytics_provider.dart
          task_service_provider.dart
          task_settings_config_provider.dart
          tasks_provider.dart
      screens/
          .gitkeep
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
  tool/
    main.dart
```

---

## 2) DATABASE SCHEMA (SQLite)

**Τρέχουσα έκδοση σχήματος (squashed v1):** `databaseSchemaVersionV1` = **27** (`lib/core/database/database_v1_schema.dart`, σταθερά `_kDatabaseSchemaVersion` στο `database_helper.dart`).

**Σημείωση runtime:** η `DatabaseHelper.ensureDepartmentsMapHiddenColumn` προσθέτει idempotent τη στήλη **`departments.map_hidden`** (INTEGER NOT NULL DEFAULT 0) χωρίς αύξηση του αριθμού έκδοσης σχήματος.

### Πίνακες (στήλη → τύπος SQLite)

- **calls** — id INTEGER PK AI, date TEXT, time TEXT, caller_id INTEGER, equipment_id INTEGER, caller_text TEXT, phone_text TEXT, department_text TEXT, equipment_text TEXT, issue TEXT, solution TEXT, category_text TEXT, category_id INTEGER, status TEXT, duration INTEGER, is_priority INTEGER DEFAULT 0, search_index TEXT, lansweeper_state TEXT NOT NULL DEFAULT 'unsent', lansweeper_main_ticket_id TEXT, lansweeper_last_sync_at TEXT, is_deleted INTEGER DEFAULT 0
- **call_external_links** — id INTEGER PK AI, call_id INTEGER NOT NULL, external_id TEXT NOT NULL, provider TEXT NOT NULL, created_at TEXT NOT NULL, metadata TEXT
- **users** — id INTEGER PK AI, last_name TEXT NOT NULL, first_name TEXT NOT NULL, department_id INTEGER, location TEXT, notes TEXT, is_deleted INTEGER DEFAULT 0
- **phones** — id INTEGER PK AI, number TEXT UNIQUE NOT NULL, department_id INTEGER
- **department_phones** — department_id INTEGER NOT NULL, phone_id INTEGER NOT NULL, PRIMARY KEY (department_id, phone_id)
- **user_phones** — user_id INTEGER NOT NULL, phone_id INTEGER NOT NULL, PRIMARY KEY (user_id, phone_id)
- **equipment** — id INTEGER PK AI, code_equipment TEXT, type TEXT, notes TEXT, custom_ip TEXT, anydesk_id TEXT, remote_params TEXT, default_remote_tool TEXT, department_id INTEGER, location TEXT, is_deleted INTEGER DEFAULT 0
- **user_equipment** — user_id INTEGER NOT NULL, equipment_id INTEGER NOT NULL, PRIMARY KEY (user_id, equipment_id)
- **departments** — id INTEGER PK AI, name TEXT NOT NULL, name_key TEXT UNIQUE NOT NULL, building TEXT, color TEXT DEFAULT '#1976D2', notes TEXT, map_floor TEXT, map_x REAL DEFAULT 0.0, map_y REAL DEFAULT 0.0, map_width REAL DEFAULT 0.0, map_height REAL DEFAULT 0.0, map_rotation REAL DEFAULT 0.0, map_label_offset_x REAL, map_label_offset_y REAL, map_anchor_offset_x REAL, map_anchor_offset_y REAL, map_custom_name TEXT, group_name TEXT, floor_id INTEGER, is_deleted INTEGER DEFAULT 0 (+ **map_hidden** INTEGER όπως παραπάνω)
- **building_map_floors** — id INTEGER PK AI, sort_order INTEGER NOT NULL DEFAULT 0, label TEXT NOT NULL, floor_group TEXT, image_path TEXT NOT NULL, rotation_degrees REAL NOT NULL DEFAULT 0
- **categories** — id INTEGER PK AI, name TEXT, is_deleted INTEGER DEFAULT 0
- **tasks** — id INTEGER PK AI, title TEXT, description TEXT, due_date TEXT, snooze_history_json TEXT, status TEXT, call_id INTEGER, priority INTEGER, solution_notes TEXT, snooze_until TEXT, caller_id INTEGER, equipment_id INTEGER, department_id INTEGER, phone_id INTEGER, phone_text TEXT, user_text TEXT, equipment_text TEXT, department_text TEXT, created_at TEXT, updated_at TEXT, origin TEXT DEFAULT 'legacy', search_index TEXT, is_deleted INTEGER DEFAULT 0
- **knowledge_base** — id INTEGER PK AI, topic TEXT, content TEXT, tags TEXT
- **audit_log** — id INTEGER PK AI, action TEXT, timestamp TEXT, user_performing TEXT, details TEXT, entity_type TEXT, entity_id INTEGER, entity_name TEXT, search_text TEXT, old_values_json TEXT, new_values_json TEXT
- **app_settings** — key TEXT PK, value TEXT
- **remote_tools** — id INTEGER PK AI, name TEXT NOT NULL, role TEXT NOT NULL, executable_path TEXT NOT NULL, launch_mode TEXT NOT NULL, sort_order INTEGER NOT NULL DEFAULT 0, is_active INTEGER NOT NULL DEFAULT 1, suggested_values TEXT, icon_asset_key TEXT, arguments_json TEXT, test_target_ip TEXT, is_exclusive INTEGER NOT NULL DEFAULT 0, deleted_at TEXT
- **remote_tool_args** — id INTEGER PK AI, remote_tool_id INTEGER, tool_name TEXT, arg_flag TEXT, description TEXT, is_active INTEGER DEFAULT 0, FOREIGN KEY (remote_tool_id) REFERENCES remote_tools(id)
- **user_dictionary** — word TEXT PK, language TEXT, letters_count INTEGER NOT NULL DEFAULT 0, diacritic_mark_count INTEGER NOT NULL DEFAULT 0
- **full_dictionary** — id INTEGER PK AI, word TEXT NOT NULL UNIQUE, normalized_word TEXT NOT NULL, source TEXT NOT NULL, language TEXT NOT NULL, category TEXT NOT NULL, created_at TEXT NOT NULL DEFAULT (datetime('now')), letters_count INTEGER NOT NULL DEFAULT 0, diacritic_mark_count INTEGER NOT NULL DEFAULT 0

---

## 3) MODELS

### Βήμα Α — `lib/features/audit/models/`
- **AuditFilterModel** — keyword, action, entityType, dateFrom, dateTo
- **AuditLogModel** — id, action, timestamp, userPerforming, details, entityType, entityId, entityName, oldValuesJson, newValuesJson
- **AuditPageResult** — items (λίστα AuditLogModel), totalCount

### `lib/features/calls/models/`
- **CallModel** — id, date, time, callerId, equipmentId, callerText, phoneText, departmentText, equipmentText, issue, solution, category, categoryId, status, duration, isPriority, lansweeperState, lansweeperMainTicketId, lansweeperLastSyncAt, isDeleted
- **EquipmentModel** — id, code, type, notes, customIp, anydeskId, remoteParams (Map), defaultRemoteTool, departmentId, location, isDeleted
- **UserModel** — id, firstName, lastName, phones, departmentId, location, notes, isDeleted

### `lib/features/database/models/`
- **DatabaseStats** — fileSizeBytes, dbPath, lastBackupTime, rowCountsByTable
- **DatabaseBackupSettings** — destinationDirectory, namingFormat (enum), zipOutput, backupOnExit, interval (enum), backupDays, backupTime, lastBackupAttempt, lastBackupStatus, retention flags/αριθμοί

### `lib/features/directory/models/`
- **CategoryModel** — id, name
- **CategoryDirectoryColumn** — key, label, sortKey (σταθερές στηλών καταλόγου)
- **DepartmentDirectoryColumn** — key, label, sortKey
- **DepartmentModel** — id, name, building, color, notes, groupName, floorId, mapFloor, mapX/Y/Width/Height, mapRotation, mapLabelOffsetX/Y, mapAnchorOffsetX/Y, mapCustomName, directPhones, isDeleted, isHiddenOnMap
- **EquipmentColumn** — key, label, displayValue (callback), sortValue (callback)· typedef **EquipmentRow** = (EquipmentModel, UserModel?)
- **NonUserPhoneEntry** — phoneId, number, departmentNamesDisplay, primaryDepartmentId
- **UserCatalogMode** — enum: personal, shared
- **UserDirectoryColumn** — key, label, sortKey
- **department_floor_display_extension** — extension επί DepartmentModel (όχι νέα κλάση)

### `lib/features/history/models/`
- **DashboardFilterModel** — keyword, dateFrom, dateTo, department, userName, equipmentCode, topN
- **DepartmentStat** / **IssueStat** / **DailyTrendPoint** / **CallerStat** / **LongestCallEntry** / **HourlyBucket** — βοηθητικά στατιστικών
- **DashboardSummaryModel** — totalCalls, totalDurationSeconds, avgDurationSeconds, KPIs προηγούμενης περιόδου, λίστες dailyTrend, sparklineLast7Days, topCallers, longestCalls, hourlyDistribution, byDepartment, byIssue
- **LansweeperSyncState** — abstract constants: unsent, sent, excluded, failed

### `lib/features/tasks/models/`
- **TaskStatus** — enum: open, snoozed, closed
- **Task** — id, callId, callerId, equipmentId, departmentId, phoneId, phoneText, userText, equipmentText, departmentText, title, description, dueDate, snoozeUntil, snoozeHistoryJson, status, priority, solutionNotes, createdAt, updatedAt, origin, isDeleted
- **TaskSnoozeEntry** — snoozedAt, dueAt
- **TaskSortOption** — enum (createdAt, dueAt, priority, department, user, equipment)
- **TaskFilter** — searchQuery, statuses, startDate, endDate, sortBy, sortAscending
- **TaskAnalyticsFilter** — startDate, endDate
- **TaskAnalyticsOriginSlice** / **TaskAnalyticsBacklogPoint** — βοηθητικά analytics
- **TaskAnalyticsSummary** — εύρος ημερομηνιών, μετρήσεις active/created/closed/cancelled/overdue, rates, μέσοι χρόνοι, originDistribution, backlogGrowth, sparkline arrays
- **TaskSettingsConfig** — dayEndTime, nextBusinessHour, skipWeekends, defaultSnoozeOption, maxSnoozeDays, autoCloseQuickAdds

### `lib/core/models/`
- **BuildingMapFloor** — id, sortOrder, label, floorGroup, imagePath, rotationDegrees
- **CallsScreenCardsVisibility** — showUserCard, showEquipmentCard, showEmployeeRecentCard, showEquipmentRecentPanel, showGlobalRecentCard
- **DictionaryImportMode** — enum: enrich, replace
- **RemoteToolArgument** — value, description, isActive
- **RemoteTool** — id, name, role, executablePath, launchMode, sortOrder, isActive, deletedAt, suggestedValuesJson, iconAssetKey, arguments, testTargetIp, isExclusive
- **ToolRole** — enum: vnc, rdp, anydesk, generic

### `lib/core/about/models/`
- **ChangelogEntry** — version, date, added, changed, fixed

### Βήμα Β — *Model εκτός φακέλων models/
- **HistoryFilterModel** (`history_provider.dart`) — keyword, dateFrom, dateTo, category
- **EquipmentViewModel** (`lamp_result_card.dart`) — προβολή γραμμής παλιού LAMP (όχι domain entity της κύριας βάσης)

### Βήμα Γ — σημαντικοί τύποι χωρίς επίθημα Model
| Περιοχή | Αρχείο | Τύποι |
|----------|--------|--------|
| Αρχικοποίηση βάσης | database_init_result.dart | DatabaseStatus, DatabaseInitResult, DatabaseInitException |
| | database_init_runner.dart | DatabaseInitRunnerResult |
| | database_init_progress_provider.dart | DatabaseInitProgressState |
| | database_helper.dart | ConnectionCheckResult, TablePreviewResult |
| Εφαρμογή | app_initializer.dart | AppInitResult |
| Ρυθμίσεις | audit_retention_config.dart | AuditRetentionConfig |
| Υπηρεσίες | excel_parser.dart | ImportResult |
| | lookup_service.dart | LookupResult, PhoneUsageCheck, EquipmentUsageCheck |
| | import_types.dart | ImportLogLevel (enum) |
| Κλήσεις | call_entry_provider.dart | CallEntryState |
| | import_log_provider.dart | ImportLogEntry |
| | lookup_provider.dart | LookupLoadResult |
| | smart_entity_selector_provider.dart | SmartEntitySelectorState, OrphanQuickAddResult |
| Κατάλογος | directory_provider.dart | DirectoryState |
| | category_directory_provider.dart | CategoryDirectoryState |
| | department_directory_provider.dart | DepartmentDirectoryState |
| | equipment_directory_provider.dart | EquipmentDirectoryState, EquipmentDeleteUndoEntry |
| Χάρτης κτιρίου | building_map_controller.dart | BuildingMapFloorDeleteChoice |
| Βάση | database_maintenance_service.dart | MaintenanceBackupPrecheck (enum), ReplaceDatabaseResult |
| | database_backup_service.dart | DatabaseBackupResult |
| | backup_destination_folder_validator.dart | BackupDestinationValidationKind (enum), BackupDestinationValidationResult |

---

## 4) STATE MANAGEMENT — PROVIDERS (Riverpod)

- **appInitProvider** — αποτέλεσμα εκκίνησης (βάση + spell check readiness).
- **databaseInitProgressProvider** — βήματα/μηνύματα κατά το άνοιγμα βάσης.
- **lookupServiceProvider** — `LookupLoadResult` + singleton `LookupService` (cache καταλόγου).
- **callHeaderProvider** — ίδιο instance με **callSmartEntityProvider** (κεφαλίδα κλήσης / έξυπνος επιλογέας).
- **callSmartEntityProvider** / **taskSmartEntityProvider** — κατάσταση επιλογής τηλεφώνου, καλούντα, τμήματος, εξοπλισμού.
- **callEntryProvider** — φόρμα κλήσης, χρονόμετρο, σημειώσεις, κατηγορία, εκκρεμότητα.
- **importLogProvider** — γραμμές live console εισαγωγής.
- **recentCallsProvider** / **recentCallsByEquipmentProvider** / **globalRecentCallsProvider** / **showGlobalCallsToggleProvider** — πρόσφατες κλήσεις και toggle καθολικής λίστας.
- **directoryProvider** / **categoryDirectoryProvider** / **departmentDirectoryProvider** / **equipmentDirectoryProvider** — κατάσταση πινάκων καταλόγου, φίλτρα, στήλες, undo.
- **buildingMapControllerProvider** — λογική χάρτη κτιρίου (φύλλα, εικόνες, CRUD τμημάτων στο χάρτη).
- **building_map_providers** — δεδομένα φύλλων/επιλογής (`building_map_providers.dart`).
- **tasksProvider** / **taskFilterProvider** / **taskStatusCountsProvider** / **orphanCallsProvider** — λίστα εκκρεμοτήτων και φίλτρα.
- **taskServiceProvider** — υπηρεσία CRUD/snooze εκκρεμοτήτων.
- **taskSettingsConfigProvider** — ρυθμίσεις snooze/ωραρίου.
- **taskAnalyticsProvider** / **taskAnalyticsFilterProvider** — σύνοψη analytics εκκρεμοτήτων.
- **pendingTaskDeleteProvider** — ροή διαγραφής εκκρεμότητας από κλήση.
- **historyFilterProvider** / **historyCallsProvider** / **historyCategoriesProvider** / **historyCategoryEntriesProvider** — ιστορικό κλήσεων.
- **dashboardFilterProvider** / **dashboardStatsProvider** / **dashboardCallsForReportProvider** / **dashboardDepartmentsProvider** — πίνακας ελέγχου· σειρά providers ρυθμίσεων Lansweeper (API URL, κλειδιά, auto-login, κ.λπ.).
- **lansweeperSyncProvider** / **callExternalLinksProvider** — συγχρονισμός κλήσεων με Lansweeper και εξωτερικά tickets.
- **historyApplicationAuditViewProvider** — εναλλαγή προβολής audit εφαρμογής στο ιστορικό.
- **auditFilterProvider** / **auditListProvider** / **auditServiceAsyncProvider** / **auditEntityPreviewProvider** — ιστορικό εφαρμογής (audit).
- **databaseBackupSettingsProvider** / **backupSchedulerProvider** / **databaseMaintenanceServiceProvider** / **databaseBrowserStatsProvider** — backup, συντήρηση, στατιστικά αρχείου βάσης.
- **settingsProvider** (και σχετικά) — εμφάνιση χρονομέτρου, badge εργασιών, ορθογραφία, ορατότητα καρτών κλήσεων, κ.λπ.
- **greekDictionaryProvider** / **spellCheckServiceProvider** / **lexiconCategoriesProvider** / **lexiconFullModeProvider** / **lexiconLanguageRecalcProvider** — λεξικά και ορθογραφία.
- **mainNavRequestProvider** / **shellNavigationIntentProvider** / **directoryTabIntentProvider** — πλοήγηση κελύφους και καρτελών.
- **changelogProvider** / **appVersionProvider** — έκδοση εφαρμογής και changelog.
- **notesFieldHintTickProvider** — ένδειξη υποχρεωτικών σημειώσεων για εκκρεμότητα.

---

## 5) DEPENDENCIES (pubspec.yaml)

**dependencies:** flutter (sdk), flutter_localizations (sdk), cupertino_icons ^1.0.9, flutter_riverpod ^3.3.1, sqflite_common ^2.5.6, sqflite_common_ffi ^2.4.0+2, sqlite3_flutter_libs ^0.6.0+eol, path_provider ^2.1.2, path ^1.9.0, google_fonts ^8.0.2, intl ^0.20.2, characters ^1.4.0, window_manager ^0.5.1, screen_retriever ^0.2.0, shared_preferences ^2.5.5, url_launcher ^6.3.0, excel ^4.0.6, file_picker 11.0.2, fl_chart ^1.2.0, archive ^3.6.1, win32 ^5.15.0, ffi ^2.2.0, custom_mouse_cursor ^1.1.3, package_info_plus ^8.3.0, image 4.3.0

**dev_dependencies:** flutter_test (sdk), integration_test (sdk), riverpod ^3.2.1, flutter_lints ^6.0.0

---

*Τέλος εγγράφου — ενημερώστε την ημερομηνία όταν αλλάζει ουσιαστικά το σχήμα ή η δομή.*
