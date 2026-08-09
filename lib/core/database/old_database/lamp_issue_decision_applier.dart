import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../utils/name_parser.dart';
import '../../utils/user_identity_normalizer.dart';
import 'lamp_database_provider.dart';
import 'lamp_issue_matching_engine.dart';
import 'lamp_issue_resolution_models.dart';
import 'lamp_issue_resolution_support.dart';
import 'old_database_schema.dart';
import 'old_equipment_repository.dart';
import 'resolution_log_entry.dart';

class LampIssueDecisionApplier {
  LampIssueDecisionApplier(
    this._databaseProvider,
    this._matching,
    this._support,
  );

  final LampDatabaseProvider _databaseProvider;
  final LampIssueMatchingEngine _matching;
  final LampIssueResolutionSupport _support;

  Future<LampIssueResolutionApplyResult> applyDecisions({
    required String databasePath,
    required List<LampIssueResolutionDecision> decisions,
    ResolutionLogSink? onLog,
    ResolutionCancelToken? cancelToken,
    void Function(LampIssueResolutionDecision decision)? onDecisionApplied,
  }) async {
    void emit(ResolutionLogEntry entry) => onLog?.call(entry);

    emit(
      ResolutionLogEntry.info(
        'Έναρξη εφαρμογής ${decisions.length} αποφάσεων επίλυσης.',
      ),
    );
    final db = await _databaseProvider.open(
      databasePath.trim(),
      mode: LampDatabaseMode.write,
    );
    await _ensureIntegrityArtifacts(db);
    var resolved = 0;
    var manualApplied = 0;
    var created = 0;
    var unresolved = 0;
    final errors = <String>[];

    for (final decision in decisions) {
      if (cancelToken?.isCancelled == true) {
        emit(
          ResolutionLogEntry.warning(
            'Η διαδικασία ακυρώθηκε πριν την επόμενη απόφαση.',
          ),
        );
        break;
      }
      try {
        final changed = await db.transaction<_AppliedDecision>((txn) async {
          return _applyDecision(txn, decision, emit: emit);
        });
        if (changed.unresolved) {
          // Μερική εφαρμογή: γράφτηκε το γραφείο, ο υπάλληλος λείπει ακόμη.
          unresolved++;
        } else if (changed.created) {
          created++;
        } else if (decision.option != null) {
          manualApplied++;
        } else {
          resolved++;
        }
        onDecisionApplied?.call(decision);
      } catch (e) {
        unresolved++;
        final p = decision.proposal;
        final errorMessage =
            '${p.issueType.issueType} γραμμή=${p.row ?? '-'} '
            'στήλη=${p.column ?? '-'}: $e';
        emit(
          ResolutionLogEntry.error(
            'Σφάλμα κατά την εφαρμογή απόφασης: $errorMessage',
          ),
        );
        errors.add(errorMessage);
      }
    }

    emit(
      ResolutionLogEntry.success(
        'Ολοκληρώθηκε η εφαρμογή αποφάσεων: '
        'auto=$resolved, manual=$manualApplied, νέες=$created, '
        'ανεπίλυτες=$unresolved.',
      ),
    );

    return LampIssueResolutionApplyResult(
      resolved: resolved,
      manualApplied: manualApplied,
      created: created,
      unresolved: unresolved,
      errors: errors,
    );
  }

  /// Μία απόφαση σε μία συναλλαγή — ίδια διαδρομή με [applyDecisions] (logs, `_applyDecision`).
  Future<LampIssueResolutionApplyResult> applySingleDecision({
    required String databasePath,
    required LampIssueResolutionDecision decision,
    ResolutionLogSink? onLog,
    ResolutionCancelToken? cancelToken,
    void Function(LampIssueResolutionDecision decision)? onDecisionApplied,
  }) {
    return applyDecisions(
      databasePath: databasePath,
      decisions: <LampIssueResolutionDecision>[decision],
      onLog: onLog,
      cancelToken: cancelToken,
      onDecisionApplied: onDecisionApplied,
    );
  }

  Future<void> _ensureIntegrityArtifacts(Database db) async {
    for (final statement in oldDatabaseIntegrityStatements) {
      try {
        await db.execute(statement);
      } catch (_) {
        // Συνεχίζουμε: σε legacy βάσεις κάποια integrity artifacts μπορεί
        // να αποτύχουν, αλλά το κρίσιμο cleanup (π.χ. DROP legacy trigger)
        // πρέπει να έχει ευκαιρία να εφαρμοστεί.
      }
    }
  }

  Future<_AppliedDecision> _applyDecision(
    Transaction txn,
    LampIssueResolutionDecision decision, {
    required ResolutionLogSink emit,
  }) async {
    final proposal = decision.proposal;
    final option = decision.option;
    final metadata = option?.metadata ?? proposal.metadata;
    final operation = metadata['operation']?.toString();
    var created = false;

    if (proposal.proposedAction == LampIssueResolutionAction.createNew &&
        option == null) {
      created = await _createReferenceAndUpdateEquipment(
        txn,
        proposal,
        emit: emit,
      );
      await _deleteIssues(txn, proposal.issueIds, emit: emit);
      return _AppliedDecision(created: created);
    }

    switch (operation) {
      case 'close_resolved_fk_issue':
        // Καμία εγγραφή δεν αλλάζει: το πεδίο είναι ήδη σωστό και μόνο η
        // εκκρεμότητα είχε ξεμείνει.
        final code = proposal.row;
        final column = metadata['fkColumn']?.toString();
        if (code == null || column == null) {
          throw StateError('Λείπουν στοιχεία για κλείσιμο λυμένου FK.');
        }
        await _closeIssuesForField(txn, code, column, emit: emit);
        return const _AppliedDecision(created: false);
      case 'number_serial_series':
        final model = metadata['model'] as int?;
        final serial = _support.text(metadata['serialNo']);
        if (model == null || serial == null) {
          throw StateError('Λείπουν στοιχεία για αρίθμηση σειράς.');
        }
        final codes = <int>[
          for (final value in (metadata['codes'] as List<Object?>? ?? const []))
            ?_support.toInt(value),
        ];
        final taken = <String>[
          for (final value
              in (metadata['takenSerials'] as List<Object?>? ?? const []))
            ?_support.text(value),
        ];
        final template =
            decision.serialSeriesTemplate?.trim() ??
            _support.text(metadata['suggestedTemplate']) ??
            '$serial-$kLampSeriesCounterToken';
        if (!lampSeriesTemplateIsValid(template)) {
          throw StateError(
            'Το πρότυπο αρίθμησης πρέπει να περιέχει τον τελεστή '
            '$kLampSeriesCounterToken· αλλιώς όλες οι εγγραφές θα έπαιρναν '
            'την ίδια τιμή.',
          );
        }
        final plan = lampBuildSerialSeries(
          template: template,
          equipmentCodes: codes,
          takenSerials: taken,
        );
        if (plan.isEmpty) {
          throw StateError('Η αρίθμηση δεν παρήγαγε καμία τιμή.');
        }
        // Όλα σε μία συναλλαγή: μερική αρίθμηση θα άφηνε τη σειρά σπασμένη
        // και το πρόβλημα ανοιχτό με χειρότερα δεδομένα από πριν.
        for (final assignment in plan.assignments) {
          await _assertSerialNoAvailable(
            txn,
            model: model,
            serialNo: assignment.serial,
            exceptCode: assignment.code,
          );
          await txn.update(
            'equipment',
            <String, Object?>{'serial_no': assignment.serial},
            where: 'code = ?',
            whereArgs: <Object?>[assignment.code],
          );
        }
        emit(
          ResolutionLogEntry.success(
            'Αριθμήθηκε η σειρά «${plan.root}»: '
            '${plan.assignments.length} εγγραφές, από '
            '${plan.assignments.first.serial} έως '
            '${plan.assignments.last.serial}.',
          ),
        );
      case 'accept_duplicate_serial':
        // Καμία αλλαγή δεδομένων: η επανάληψη είναι νόμιμη (κοινή άδεια).
        //
        // Η εκκρεμότητα **σημειώνεται**, δεν σβήνεται. Τα διπλότυπα μένουν
        // επίτηδες, οπότε ο επόμενος έλεγχος θα τα ξαναβρεί· η σημειωμένη
        // εγγραφή είναι το μόνο ίχνος ότι κάποιος τα ενέκρινε, και ο έλεγχος
        // τη σέβεται γιατί συγκρίνει με όλες τις εγγραφές, όχι μόνο τις
        // ανοιχτές.
        await _markIssuesAccepted(
          txn,
          proposal.issueIds,
          note:
              'Αποδεκτός διπλότυπος σειριακός: η τιμή μοιάζει με κλειδί '
              'άδειας λογισμικού και επαναλαμβάνεται νόμιμα.',
          emit: emit,
        );
        return const _AppliedDecision(created: false);
      case 'create_contract_and_update_equipment':
        final code = proposal.row;
        final input = decision.contractInput;
        if (code == null || input == null || input.name.trim().isEmpty) {
          throw StateError('Η δημιουργία σύμβασης απαιτεί όνομα.');
        }
        final contractId = await _createContract(txn, input, emit: emit);
        await txn.update(
          'equipment',
          <String, Object?>{
            'contract': contractId,
            'contract_original_text': null,
          },
          where: 'code = ?',
          whereArgs: <Object?>[code],
        );
        emit(
          ResolutionLogEntry.success(
            'Ο εξοπλισμός $code συνδέθηκε με τη σύμβαση $contractId.',
          ),
        );
        await _closeIssuesForField(txn, code, 'contract', emit: emit);
        return const _AppliedDecision(created: true);
      case 'set_equipment_placement':
        final code = proposal.row;
        final placement = decision.placementInput;
        if (code == null || placement == null) {
          throw StateError('Ο ορισμός τοποθέτησης απαιτεί γραφείο.');
        }
        await _applyEquipmentPlacement(
          txn,
          code: code,
          placement: placement,
          emit: emit,
        );
        // Ο υπάλληλος είναι προαιρετικός: όταν λείπει, το γραφείο γράφτηκε
        // αλλά το πρόβλημα του υπαλλήλου παραμένει ανοιχτό για αργότερα.
        if (placement.ownerId == null) {
          await _closeIssuesForField(txn, code, 'office', emit: emit);
          return const _AppliedDecision(created: false, unresolved: true);
        }
        await _closeIssuesForField(txn, code, 'owner', emit: emit);
        await _closeIssuesForField(txn, code, 'office', emit: emit);
        return const _AppliedDecision(created: false);
      case 'update_equipment_fk':
        final code = proposal.row;
        final fkColumn = metadata['fkColumn']?.toString();
        final proposedId = metadata['proposedId'] as int?;
        if (code == null || fkColumn == null) {
          throw StateError('Λείπουν στοιχεία FK update.');
        }
        final fkSpec = _support.fkSpec(fkColumn);
        if (fkColumn == 'owner' && proposedId != null) {
          await _updateEquipmentOwner(
            txn,
            code: code,
            ownerId: proposedId,
            clearOriginalText: true,
            emit: emit,
          );
        } else {
          final values = <String, Object?>{fkColumn: proposedId};
          if (fkSpec != null && proposedId != null) {
            values[fkSpec.originalColumn] = null;
          }
          await txn.update(
            'equipment',
            values,
            where: 'code = ?',
            whereArgs: <Object?>[code],
          );
          final targetDisplay = proposedId == null
              ? '(κενό)'
              : await _support.fkTargetDisplay(txn, fkColumn, proposedId);
          emit(
            ResolutionLogEntry.success(
              'Ενημερώθηκε η στήλη $fkColumn του εξοπλισμού $code σε $targetDisplay.',
            ),
          );
        }
      case 'create_owner_and_update_equipment':
        final code = proposal.row;
        if (code == null) throw StateError('Λείπει κωδικός εξοπλισμού.');
        var lastName = _support.text(metadata['createOwnerLastName']);
        var firstName = _support.text(metadata['createOwnerFirstName']);
        final allowsManualNameInput = metadata['allowManualNameInput'] == true;
        if (allowsManualNameInput) {
          final parsed = _parseOwnerNameInput(decision.textInput);
          if (parsed == null) {
            throw StateError(
              'Η "Τροποποίηση" απαιτεί μορφή: επώνυμο, μικρό όνομα.',
            );
          }
          lastName = parsed.lastName;
          firstName = parsed.firstName;
        }
        final equipmentOfficeRows = await txn.query(
          'equipment',
          columns: <String>['office'],
          where: 'code = ?',
          whereArgs: <Object?>[code],
          limit: 1,
        );
        final equipmentOffice = equipmentOfficeRows.isEmpty
            ? null
            : _support.toInt(equipmentOfficeRows.first['office']);
        var officeLogDisplay = equipmentOffice?.toString() ?? '(κενό)';
        if (equipmentOffice != null) {
          final officeRows = await txn.query(
            'offices',
            columns: <String>['office_name'],
            where: 'office = ?',
            whereArgs: <Object?>[equipmentOffice],
            limit: 1,
          );
          if (officeRows.isNotEmpty) {
            final officeName = _support.text(officeRows.first['office_name']);
            if (officeName != null) {
              officeLogDisplay = '$officeName ($equipmentOffice)';
            }
          }
        }

        var ownerId = await _existingOwnerIdByIdentity(
          txn,
          lastName: lastName,
          firstName: firstName,
        );
        if (ownerId != null) {
          emit(
            ResolutionLogEntry.success(
              'Βρέθηκε ισοδύναμος υπάρχων υπάλληλος: id=$ownerId. '
              'Θα γίνει σύνδεση χωρίς νέα δημιουργία.',
            ),
          );
        } else {
          ownerId = await _nextId(txn, 'owners', 'owner');
          await txn.insert('owners', <String, Object?>{
            'owner': ownerId,
            'last_name': lastName,
            'first_name': firstName,
            'office': equipmentOffice,
          });
          emit(
            ResolutionLogEntry.success(
              'Δημιουργήθηκε νέος υπάλληλος: id=$ownerId, '
              'επώνυμο=${lastName ?? '(κενό)'}, '
              'μικρό όνομα=${firstName ?? '(χωρίς μικρό όνομα)'}, '
              'γραφείο=$officeLogDisplay.',
            ),
          );
          created = true;
        }
        await _updateEquipmentOwner(
          txn,
          code: code,
          ownerId: ownerId,
          clearOriginalText: true,
          emit: emit,
        );
      case 'update_equipment_owner_null_clear_original':
        final code = proposal.row;
        if (code == null) throw StateError('Λείπει κωδικός εξοπλισμού.');
        await txn.update(
          'equipment',
          <String, Object?>{'owner': null, 'owner_original_text': null},
          where: 'code = ?',
          whereArgs: <Object?>[code],
        );
        emit(
          ResolutionLogEntry.success(
            'Αποσυνδέθηκε ο υπάλληλος και εκκαθαρίστηκε το αρχικό κείμενο για τον εξοπλισμό $code.',
          ),
        );
      case 'clear_set_master':
        final code = metadata['code'];
        await txn.update(
          'equipment',
          <String, Object?>{'set_master': null},
          where: 'code = ?',
          whereArgs: <Object?>[code],
        );
        emit(
          ResolutionLogEntry.success(
            'Εκκαθαρίστηκε ο δείκτης κύριου εξοπλισμού για τον κωδικό $code.',
          ),
        );
        await txn.delete(
          'data_issues',
          where: 'issue_type = ? AND row_number = ? AND column_name = ?',
          whereArgs: <Object?>['set_master_cycle', code, 'set_master'],
        );
        emit(
          ResolutionLogEntry.success(
            'Αφαιρέθηκε η εγγραφή κύκλου κύριου εξοπλισμού για τον κωδικό $code.',
          ),
        );
      case 'clear_duplicate_asset_others':
        await txn.update(
          'equipment',
          <String, Object?>{'asset_no': null},
          where: 'asset_no = ? AND code <> ?',
          whereArgs: <Object?>[metadata['value'], metadata['keepCode']],
        );
        emit(
          ResolutionLogEntry.success(
            'Εκκαθαρίστηκαν διπλότυποι αριθμοί παγίου ${metadata['value']} εκτός από τον εξοπλισμό ${metadata['keepCode']}.',
          ),
        );
      case 'delete_duplicate_asset_others':
        await _deleteDuplicateEquipmentOthers(
          txn,
          keepCode: metadata['keepCode'] as int?,
          where: 'asset_no = ? AND code <> ?',
          whereArgs: <Object?>[metadata['value'], metadata['keepCode']],
          emit: emit,
        );
      case 'reassign_asset':
        final value = decision.textInput?.trim();
        if (value == null || value.isEmpty) {
          throw StateError('Δεν δόθηκε νέο asset_no.');
        }
        final targetCode = metadata['targetCode'] as int?;
        if (targetCode == null) {
          throw StateError('Λείπει κωδικός εξοπλισμού για reassign asset_no.');
        }
        await _assertAssetNoAvailable(
          txn,
          assetNo: value,
          exceptCode: targetCode,
        );
        await txn.update(
          'equipment',
          <String, Object?>{'asset_no': value},
          where: 'code = ?',
          whereArgs: <Object?>[targetCode],
        );
        emit(
          ResolutionLogEntry.success(
            'Ενημερώθηκε ο αριθμός παγίου του εξοπλισμού $targetCode σε $value.',
          ),
        );
      case 'clear_duplicate_serial_others':
        await txn.update(
          'equipment',
          <String, Object?>{'serial_no': null},
          where: 'model = ? AND serial_no = ? AND code <> ?',
          whereArgs: <Object?>[
            metadata['model'],
            metadata['serialNo'],
            metadata['keepCode'],
          ],
        );
        emit(
          ResolutionLogEntry.success(
            'Εκκαθαρίστηκαν διπλότυπα serial_no ${metadata['serialNo']} για μοντέλο ${metadata['model']} εκτός από τον εξοπλισμό ${metadata['keepCode']}.',
          ),
        );
      case 'delete_duplicate_serial_others':
        await _deleteDuplicateEquipmentOthers(
          txn,
          keepCode: metadata['keepCode'] as int?,
          where: 'model = ? AND serial_no = ? AND code <> ?',
          whereArgs: <Object?>[
            metadata['model'],
            metadata['serialNo'],
            metadata['keepCode'],
          ],
          emit: emit,
        );
      case 'reassign_serial':
        final value = decision.textInput?.trim();
        if (value == null || value.isEmpty) {
          throw StateError('Δεν δόθηκε νέο serial_no.');
        }
        final targetCode = metadata['targetCode'] as int?;
        if (targetCode == null) {
          throw StateError('Λείπει κωδικός εξοπλισμού για reassign serial_no.');
        }
        final modelRows = await txn.query(
          'equipment',
          columns: <String>['model'],
          where: 'code = ?',
          whereArgs: <Object?>[targetCode],
          limit: 1,
        );
        if (modelRows.isEmpty) {
          throw StateError(
            'Δεν βρέθηκε εξοπλισμός $targetCode για έλεγχο μοναδικότητας σειριακού.',
          );
        }
        final model = _support.toInt(modelRows.first['model']);
        if (model == null) {
          throw StateError(
            'Ο εξοπλισμός $targetCode δεν έχει μοντέλο για έλεγχο μοναδικότητας σειριακού.',
          );
        }
        await _assertSerialNoAvailable(
          txn,
          model: model,
          serialNo: value,
          exceptCode: targetCode,
        );
        await txn.update(
          'equipment',
          <String, Object?>{'serial_no': value},
          where: 'code = ?',
          whereArgs: <Object?>[targetCode],
        );
        emit(
          ResolutionLogEntry.success(
            'Ενημερώθηκε το serial_no του εξοπλισμού $targetCode σε $value.',
          ),
        );
      case 'reassign_scientific_serial':
        final scientificValue = decision.textInput?.trim();
        if (scientificValue == null || scientificValue.isEmpty) {
          throw StateError('Δεν δόθηκε νέος σειριακός.');
        }
        final scientificTargetCode = metadata['targetCode'] as int?;
        if (scientificTargetCode == null) {
          throw StateError(
            'Λείπει κωδικός εξοπλισμού για reassign επιστημονικού σειριακού.',
          );
        }
        await txn.update(
          'equipment',
          <String, Object?>{'serial_no': scientificValue},
          where: 'code = ?',
          whereArgs: <Object?>[scientificTargetCode],
        );
        emit(
          ResolutionLogEntry.success(
            'Ενημερώθηκε το serial_no του εξοπλισμού $scientificTargetCode '
            'σε $scientificValue (καταχώρηση νέου σειριακού).',
          ),
        );
      case LampIssueResolutionOperations.setFieldManual:
        final manualCode = _support.toInt(metadata['code'] ?? proposal.row);
        final manualFkColumn =
            metadata['fkColumn']?.toString() ?? proposal.column;
        final manualInput = decision.textInput?.trim();
        final manualTargetId = _support.toInt(manualInput);
        if (manualCode == null || manualFkColumn == null) {
          throw StateError('Λείπουν στοιχεία χειροκίνητης σύνδεσης κωδικού.');
        }
        if (manualTargetId == null) {
          throw StateError('Ο κωδικός πρέπει να είναι αριθμός.');
        }
        await _assertManualFkTargetExists(
          txn,
          fkColumn: manualFkColumn,
          targetId: manualTargetId,
        );
        if (manualFkColumn == 'owner') {
          await _updateEquipmentOwner(
            txn,
            code: manualCode,
            ownerId: manualTargetId,
            clearOriginalText: true,
            emit: emit,
          );
        } else if (manualFkColumn == 'set_master') {
          await txn.update(
            'equipment',
            <String, Object?>{
              'set_master': manualTargetId,
              'set_master_original_text': null,
            },
            where: 'code = ?',
            whereArgs: <Object?>[manualCode],
          );
          emit(
            ResolutionLogEntry.success(
              'Ο κύριος εξοπλισμός του $manualCode ορίστηκε σε $manualTargetId.',
            ),
          );
        } else {
          final fkSpec = _support.fkSpec(manualFkColumn);
          final values = <String, Object?>{manualFkColumn: manualTargetId};
          if (fkSpec != null) {
            values[fkSpec.originalColumn] = null;
          }
          await txn.update(
            'equipment',
            values,
            where: 'code = ?',
            whereArgs: <Object?>[manualCode],
          );
          final manualTargetDisplay = await _support.fkTargetDisplay(
            txn,
            manualFkColumn,
            manualTargetId,
          );
          emit(
            ResolutionLogEntry.success(
              'Ενημερώθηκε η στήλη $manualFkColumn του εξοπλισμού $manualCode σε $manualTargetDisplay.',
            ),
          );
        }
      case LampIssueResolutionOperations.clearField:
        final clearCode = _support.toInt(metadata['code'] ?? proposal.row);
        final clearFkColumn =
            metadata['fkColumn']?.toString() ?? proposal.column;
        if (clearCode == null || clearFkColumn == null) {
          throw StateError('Λείπουν στοιχεία εκκαθάρισης πεδίου.');
        }
        final clearValues = <String, Object?>{clearFkColumn: null};
        final clearFkSpec = _support.fkSpec(clearFkColumn);
        if (clearFkSpec != null) {
          clearValues[clearFkSpec.originalColumn] = null;
        } else if (clearFkColumn == 'set_master') {
          clearValues['set_master_original_text'] = null;
        }
        await txn.update(
          'equipment',
          clearValues,
          where: 'code = ?',
          whereArgs: <Object?>[clearCode],
        );
        emit(
          ResolutionLogEntry.success(
            'Εκκαθαρίστηκε το πεδίο $clearFkColumn του εξοπλισμού $clearCode.',
          ),
        );
      case LampIssueResolutionOperations.deferIssue:
        if (proposal.issueIds.isEmpty) {
          throw StateError('Δεν υπάρχουν εγγραφές προβλήματος για αναβολή.');
        }
        final deferPlaceholders = List<String>.filled(
          proposal.issueIds.length,
          '?',
        ).join(',');
        await txn.update(
          'data_issues',
          <String, Object?>{'status': kDataIssueStatusDeferred},
          where: 'id IN ($deferPlaceholders)',
          whereArgs: proposal.issueIds,
        );
        emit(
          ResolutionLogEntry.success(
            'Αναβλήθηκαν ${proposal.issueIds.length} εγγραφές προβλήματος.',
          ),
        );
        return _AppliedDecision(created: created);
      default:
        if (proposal.proposedAction == LampIssueResolutionAction.autoFix) {
          final fkColumn = proposal.metadata['fkColumn']?.toString();
          if (fkColumn != null && proposal.row != null) {
            final rowCode = proposal.row!;
            final pid = proposal.proposedId;
            final fallbackFkSpec = _support.fkSpec(fkColumn);
            if (fkColumn == 'owner' && pid != null) {
              await _updateEquipmentOwner(
                txn,
                code: rowCode,
                ownerId: pid,
                clearOriginalText: true,
                emit: emit,
              );
            } else {
              final values = <String, Object?>{fkColumn: pid};
              if (fallbackFkSpec != null && pid != null) {
                values[fallbackFkSpec.originalColumn] = null;
              }
              await txn.update(
                'equipment',
                values,
                where: 'code = ?',
                whereArgs: <Object?>[rowCode],
              );
              final targetDisplay = pid == null
                  ? '(κενό)'
                  : await _support.fkTargetDisplay(txn, fkColumn, pid);
              emit(
                ResolutionLogEntry.success(
                  'Ενημερώθηκε η στήλη $fkColumn του εξοπλισμού $rowCode σε $targetDisplay.',
                ),
              );
            }
          } else {
            throw StateError(
              'Δεν υπάρχει εφαρμόσιμη ενέργεια για την πρόταση.',
            );
          }
        } else {
          throw StateError('Δεν υπάρχει εφαρμόσιμη ενέργεια για την πρόταση.');
        }
    }

    if (operation == 'reassign_asset') {
      final oldValue = proposal.originalValue?.trim();
      if (oldValue != null &&
          oldValue.isNotEmpty &&
          await _duplicateAssetNoRemains(txn, oldValue)) {
        emit(
          ResolutionLogEntry.warning(
            'Η ομάδα διπλότυπων αριθμών παγίου «$oldValue» παραμένει ανοικτή '
            '— υπάρχουν ακόμη εγγραφές με την ίδια τιμή.',
          ),
        );
        return _AppliedDecision(created: created);
      }
    } else if (operation == 'reassign_serial') {
      final model = _support.toInt(metadata['model']);
      final oldSerial = _support.text(metadata['serialNo']);
      if (model != null &&
          oldSerial != null &&
          await _duplicateModelSerialRemains(txn, model, oldSerial)) {
        emit(
          ResolutionLogEntry.warning(
            'Η ομάδα διπλότυπου συνδυασμού μοντέλου/σειριακού '
            '($model / $oldSerial) παραμένει ανοικτή — υπάρχουν ακόμη εγγραφές.',
          ),
        );
        return _AppliedDecision(created: created);
      }
    }

    final issueIdsToDelete = await _filterResolvableDuplicateIssueIds(
      txn,
      proposal.issueIds,
    );
    await _deleteIssues(txn, issueIdsToDelete, emit: emit);
    await _closeIssuesOfResolvedFk(txn, proposal, emit: emit);
    return _AppliedDecision(created: created);
  }

  /// Αν η ενέργεια άφησε τη στήλη FK με έγκυρη τιμή, κλείνει ό,τι άλλο είχε
  /// μείνει ανοιχτό για το ίδιο πεδίο.
  ///
  /// Το κριτήριο είναι η **βάση**, όχι ο τύπος της ενέργειας: το ίδιο ερώτημα
  /// που κάνει και ο έλεγχος ακεραιότητας — «δείχνει η στήλη σε υπαρκτή
  /// εγγραφή;». Ένα συμβόλαιο, ένας τρόπος να απαντηθεί.
  Future<void> _closeIssuesOfResolvedFk(
    Transaction txn,
    LampIssueResolutionProposal proposal, {
    required ResolutionLogSink emit,
  }) async {
    final code = proposal.row;
    final column = proposal.column?.toLowerCase();
    if (code == null || column == null) return;
    final spec = _support.fkSpec(column);
    if (spec == null) return;

    final rows = await txn.query(
      'equipment',
      columns: <String>[column],
      where: 'code = ?',
      whereArgs: <Object?>[code],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final resolvedId = _support.toInt(rows.first[column]);
    if (resolvedId == null) return;

    final table = switch (column) {
      'office' => 'offices',
      'owner' => 'owners',
      'contract' => 'contracts',
      'model' => 'model',
      _ => null,
    };
    if (table == null) return;
    final target = await txn.query(
      table,
      columns: <String>[column],
      where: '$column = ?',
      whereArgs: <Object?>[resolvedId],
      limit: 1,
    );
    if (target.isEmpty) return;

    await _closeIssuesForField(txn, code, column, emit: emit);
  }

  Future<bool> _createReferenceAndUpdateEquipment(
    Transaction txn,
    LampIssueResolutionProposal proposal, {
    required ResolutionLogSink emit,
  }) async {
    final metadata = proposal.metadata;
    final table = metadata['referenceTable']?.toString();
    final idColumn = metadata['idColumn']?.toString();
    final labelColumn = metadata['labelColumn']?.toString();
    final fkColumn = metadata['fkColumn']?.toString();
    final code = proposal.row;
    final createValue = metadata['createValue'];
    if (table == null ||
        idColumn == null ||
        labelColumn == null ||
        fkColumn == null ||
        code == null) {
      throw StateError('Λείπουν στοιχεία για create_new.');
    }
    final createText = createValue?.toString().trim() ?? '';
    final normalizedCreate = _matching.normalizeReferenceText(createText);
    final existingId = await _findExistingReferenceId(
      txn,
      table: table,
      idColumn: idColumn,
      labelColumn: labelColumn,
      normalizedCreateValue: normalizedCreate,
    );

    final int id;
    var actuallyCreated = false;
    if (existingId != null) {
      id = existingId;
      emit(
        ResolutionLogEntry.success(
          'Βρέθηκε υπάρχουσα εγγραφή στον πίνακα $table: '
          '$idColumn=$id — έγινε σύνδεση χωρίς νέα δημιουργία.',
        ),
      );
    } else {
      id = await _nextId(txn, table, idColumn);
      await txn.insert(table, <String, Object?>{
        idColumn: id,
        labelColumn: createValue,
      });
      emit(
        ResolutionLogEntry.success(
          'Δημιουργήθηκε νέα εγγραφή στον πίνακα $table: '
          '$idColumn=$id, $labelColumn=${createValue ?? '(κενό)'}.',
        ),
      );
      actuallyCreated = true;
    }

    await txn.update(
      'equipment',
      <String, Object?>{
        fkColumn: id,
        if (_support.fkSpec(fkColumn) != null)
          _support.fkSpec(fkColumn)!.originalColumn: null,
      },
      where: 'code = ?',
      whereArgs: <Object?>[code],
    );
    emit(
      ResolutionLogEntry.success(
        'Ενημερώθηκε η στήλη $fkColumn του εξοπλισμού $code σε $id.',
      ),
    );
    return actuallyCreated;
  }

  Future<int?> _findExistingReferenceId(
    DatabaseExecutor db, {
    required String table,
    required String idColumn,
    required String labelColumn,
    required String normalizedCreateValue,
  }) async {
    if (normalizedCreateValue.isEmpty) return null;
    final rows = await db.query(
      table,
      columns: <String>[idColumn, labelColumn],
    );
    for (final row in rows) {
      final id = _support.toInt(row[idColumn]);
      final label = _support.text(row[labelColumn]);
      if (id == null || label == null) continue;
      if (_matching.normalizeReferenceText(label) == normalizedCreateValue) {
        return id;
      }
    }
    return null;
  }

  Future<void> _assertAssetNoAvailable(
    DatabaseExecutor db, {
    required String assetNo,
    required int exceptCode,
  }) async {
    final rows = await db.query(
      'equipment',
      columns: <String>['code'],
      where: 'asset_no = ? AND code <> ?',
      whereArgs: <Object?>[assetNo, exceptCode],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final ownerCode = _support.toInt(rows.first['code']);
    throw StateError(
      'Ο αριθμός παγίου $assetNo χρησιμοποιείται ήδη στον εξοπλισμό $ownerCode.',
    );
  }

  Future<void> _assertManualFkTargetExists(
    DatabaseExecutor db, {
    required String fkColumn,
    required int targetId,
  }) async {
    final spec = ManualFkTargetSpec.forColumn(fkColumn);
    if (spec == null) {
      throw StateError(
        'Μη υποστηριζόμενο πεδίο για χειροκίνητη σύνδεση: $fkColumn.',
      );
    }
    final rows = await db.query(
      spec.table,
      columns: <String>[spec.idColumn],
      where: '${spec.idColumn} = ?',
      whereArgs: <Object?>[targetId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError(
        'Ο κωδικός $targetId δεν υπάρχει στον πίνακα ${spec.table}.',
      );
    }
  }

  Future<void> _assertSerialNoAvailable(
    DatabaseExecutor db, {
    required int model,
    required String serialNo,
    required int exceptCode,
  }) async {
    final rows = await db.query(
      'equipment',
      columns: <String>['code'],
      where: 'model = ? AND serial_no = ? AND code <> ?',
      whereArgs: <Object?>[model, serialNo, exceptCode],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final ownerCode = _support.toInt(rows.first['code']);
    throw StateError(
      'Ο σειριακός αριθμός $serialNo χρησιμοποιείται ήδη στον εξοπλισμό '
      '$ownerCode (μοντέλο $model).',
    );
  }

  Future<bool> _duplicateAssetNoRemains(
    DatabaseExecutor db,
    String assetNo,
  ) async {
    final rows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS count
      FROM equipment
      WHERE asset_no IS NOT NULL AND TRIM(asset_no) <> '' AND asset_no = ?
      ''',
      <Object?>[assetNo],
    );
    return (_support.toInt(rows.first['count']) ?? 0) > 1;
  }

  Future<bool> _duplicateModelSerialRemains(
    DatabaseExecutor db,
    int model,
    String serialNo,
  ) async {
    final rows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS count
      FROM equipment
      WHERE model = ? AND serial_no IS NOT NULL AND TRIM(serial_no) <> ''
        AND serial_no = ?
      ''',
      <Object?>[model, serialNo],
    );
    return (_support.toInt(rows.first['count']) ?? 0) > 1;
  }

  Future<int> _countDuplicateModelSerialGroups(
    DatabaseExecutor db,
    String serialNo,
  ) async {
    final rows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS count
      FROM (
        SELECT model
        FROM equipment
        WHERE serial_no IS NOT NULL AND TRIM(serial_no) <> '' AND serial_no = ?
        GROUP BY model, serial_no
        HAVING COUNT(*) > 1
      )
      ''',
      <Object?>[serialNo],
    );
    return _support.toInt(rows.first['count']) ?? 0;
  }

  Future<List<int>> _filterResolvableDuplicateIssueIds(
    DatabaseExecutor db,
    List<int> issueIds,
  ) async {
    if (issueIds.isEmpty) return const <int>[];
    final placeholders = List<String>.filled(issueIds.length, '?').join(',');
    final rows = await db.rawQuery(
      'SELECT id, issue_type, raw_value FROM data_issues WHERE id IN ($placeholders)',
      issueIds,
    );
    final resolved = <int>[];
    final serialToCandidateIds = <String, List<int>>{};

    for (final row in rows) {
      final id = _support.toInt(row['id']);
      if (id == null) continue;
      final issueType = _support.text(row['issue_type']);
      final rawValue = _support.text(row['raw_value']);
      switch (issueType) {
        case 'duplicate_asset_no':
          if (rawValue != null &&
              !await _duplicateAssetNoRemains(db, rawValue)) {
            resolved.add(id);
          }
        case 'duplicate_model_serial':
          if (rawValue != null) {
            serialToCandidateIds.putIfAbsent(rawValue, () => <int>[]).add(id);
          }
        default:
          resolved.add(id);
      }
    }

    for (final entry in serialToCandidateIds.entries) {
      final ids = List<int>.from(entry.value)..sort();
      final remainingGroups = await _countDuplicateModelSerialGroups(
        db,
        entry.key,
      );
      final deletableCount = ids.length - remainingGroups;
      if (deletableCount > 0) {
        resolved.addAll(ids.take(deletableCount));
      }
    }

    return resolved;
  }

  Future<void> _deleteDuplicateEquipmentOthers(
    Transaction txn, {
    required int? keepCode,
    required String where,
    required List<Object?> whereArgs,
    required ResolutionLogSink emit,
  }) async {
    if (keepCode == null) throw StateError('Λείπει κύρια εγγραφή.');
    final rows = await txn.query(
      'equipment',
      columns: <String>['code'],
      where: where,
      whereArgs: whereArgs,
    );
    for (final row in rows) {
      final code = _support.toInt(row['code']);
      if (code == null) continue;
      await txn.update(
        'equipment',
        <String, Object?>{'set_master': keepCode},
        where: 'set_master = ?',
        whereArgs: <Object?>[code],
      );
      emit(
        ResolutionLogEntry.success(
          'Μεταφέρθηκαν οι παιδικές εγγραφές του εξοπλισμού $code στον κύριο εξοπλισμό $keepCode.',
        ),
      );
      await txn.delete(
        'equipment',
        where: 'code = ?',
        whereArgs: <Object?>[code],
      );
      emit(
        ResolutionLogEntry.success(
          'Διαγράφηκε διπλότυπη εγγραφή εξοπλισμού με κωδικό $code.',
        ),
      );
    }
  }

  /// Γράφει γραφείο και υπάλληλο μαζί, μέσα στην ίδια συναλλαγή.
  ///
  /// Το αρχικό κείμενο κάθε πεδίου καθαρίζεται μόνο όταν το πεδίο πάρει τιμή:
  /// αν ο χρήστης ξέρει το γραφείο αλλά όχι τον κάτοχο, το «Γιατροί
  /// Μαιευτικής» μένει γραμμένο στη στήλη του υπαλλήλου ως ένδειξη.
  Future<void> _applyEquipmentPlacement(
    Transaction txn, {
    required int code,
    required LampPlacementInput placement,
    required ResolutionLogSink emit,
  }) async {
    await txn.update(
      'equipment',
      <String, Object?>{'office': placement.officeId, 'office_original_text': null},
      where: 'code = ?',
      whereArgs: <Object?>[code],
    );
    final officeDisplay = await _support.fkTargetDisplay(
      txn,
      'office',
      placement.officeId,
    );
    emit(
      ResolutionLogEntry.success(
        'Ορίστηκε γραφείο $officeDisplay στον εξοπλισμό $code.',
      ),
    );

    final ownerId = placement.ownerId;
    if (ownerId == null) {
      emit(
        ResolutionLogEntry.info(
          'Δεν δόθηκε υπάλληλος για τον εξοπλισμό $code· το πρόβλημα '
          'παραμένει ανοιχτό και το αρχικό κείμενο διατηρείται.',
        ),
      );
      return;
    }
    await _updateEquipmentOwner(
      txn,
      code: code,
      ownerId: ownerId,
      clearOriginalText: true,
      emit: emit,
    );
  }

  /// Δημιουργεί σύμβαση και επιστρέφει το αναγνωριστικό της.
  ///
  /// Ο προμηθευτής και η κατηγορία γράφονται **και ως αναγνωριστικό και ως
  /// όνομα**: η Λάμπα δεν έχει χωριστούς πίνακες γι' αυτούς, κρατά και τα δύο
  /// μέσα στη σύμβαση. Το όνομα διαβάζεται από τα υπάρχοντα ζεύγη, ώστε ο
  /// ίδιος προμηθευτής να μη γραφτεί με δύο διαφορετικές ορθογραφίες.
  Future<int> _createContract(
    Transaction txn,
    LampContractInput input, {
    required ResolutionLogSink emit,
  }) async {
    Future<String?> nameFor(String column, int? id) async {
      if (id == null) return null;
      final rows = await txn.query(
        'contracts',
        columns: <String>['${column}_name'],
        where: '$column = ? AND ${column}_name IS NOT NULL',
        whereArgs: <Object?>[id],
        limit: 1,
      );
      return rows.isEmpty ? null : _support.text(rows.first['${column}_name']);
    }

    final contractId = await _nextId(txn, 'contracts', 'contract');
    final supplierName = await nameFor('supplier', input.supplierId);
    final categoryName = await nameFor('category', input.categoryId);
    await txn.insert('contracts', <String, Object?>{
      'contract': contractId,
      'contract_name': input.name.trim(),
      'supplier': input.supplierId,
      'supplier_name': supplierName,
      'category': input.categoryId,
      'category_name': categoryName,
    });
    emit(
      ResolutionLogEntry.success(
        'Δημιουργήθηκε σύμβαση: id=$contractId, όνομα=${input.name.trim()}, '
        'προμηθευτής=${supplierName ?? '(κενό)'}, '
        'κατηγορία=${categoryName ?? '(κενή)'}.',
      ),
    );
    return contractId;
  }

  /// Κλείνει **όλα** τα ανοιχτά προβλήματα ενός (εξοπλισμού, στήλης).
  ///
  /// Ένα FK λύνεται μία φορά· κάθε άλλο ανοιχτό πρόβλημα για το ίδιο πεδίο
  /// αφορά πλέον κάτι που δεν υπάρχει. Χωρίς αυτό έμεναν πίσω ορφανά —
  /// είκοσι «unknown_id» σε εξοπλισμούς με σωστό κάτοχο — και για το γραφείο
  /// ο οδηγός θα ξαναρωτούσε λίγα βήματα μετά, με την απάντηση εκεί να
  /// αντικαθιστά αυτό που μόλις όρισε ο χρήστης.
  Future<void> _closeIssuesForField(
    Transaction txn,
    int code,
    String column, {
    required ResolutionLogSink emit,
  }) async {
    final rows = await txn.query(
      'data_issues',
      columns: <String>['id'],
      where:
          "row_number = ? AND lower(column_name) = ? AND status = 'open'",
      whereArgs: <Object?>[code, column.toLowerCase()],
    );
    final ids = <int>[
      for (final row in rows)
        if (_support.toInt(row['id']) != null) _support.toInt(row['id'])!,
    ];
    if (ids.isEmpty) return;
    await _deleteIssues(txn, ids, emit: emit);
    emit(
      ResolutionLogEntry.info(
        'Έκλεισαν ${ids.length} ανοιχτά προβλήματα «$column» του εξοπλισμού '
        '$code, γιατί το πεδίο ορίστηκε ρητά.',
      ),
    );
  }

  /// Σημειώνει εκκρεμότητες ως αποδεκτές, με αιτιολογία.
  ///
  /// Χρησιμοποιείται όταν η κατάσταση που εντόπισε ο έλεγχος είναι **σωστή**
  /// και θα ξαναεντοπιστεί: η διαγραφή δεν αφήνει ίχνος, οπότε το πρόβλημα
  /// θα επέστρεφε στην επόμενη σάρωση.
  Future<void> _markIssuesAccepted(
    Transaction txn,
    List<int> ids, {
    required String note,
    required ResolutionLogSink emit,
  }) async {
    if (ids.isEmpty) return;
    // Η στήλη λείπει από τις παλιές βάσεις· προστίθεται όπως και στην
    // αποδοχή προβλημάτων δικτύου.
    final columns = await txn.rawQuery('PRAGMA table_info(data_issues)');
    final hasNote = columns.any(
      (row) => row['name']?.toString() == 'resolution_note',
    );
    if (!hasNote) {
      await txn.execute(
        'ALTER TABLE data_issues ADD COLUMN resolution_note TEXT',
      );
    }

    final placeholders = List<String>.filled(ids.length, '?').join(',');
    await txn.update(
      'data_issues',
      <String, Object?>{
        'status': kDataIssueStatusAccepted,
        'resolution_note': note,
      },
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
    emit(
      ResolutionLogEntry.success(
        'Σημειώθηκαν ${ids.length} εγγραφές ως αποδεκτές· δεν άλλαξε κανένα '
        'δεδομένο και ο επόμενος έλεγχος δεν θα τις ξαναφέρει.',
      ),
    );
  }

  Future<void> _deleteIssues(
    Transaction txn,
    List<int> ids, {
    required ResolutionLogSink emit,
  }) async {
    if (ids.isEmpty) return;
    final placeholders = List<String>.filled(ids.length, '?').join(',');
    await txn.delete(
      'data_issues',
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
    emit(
      ResolutionLogEntry.success(
        'Αφαιρέθηκαν ${ids.length} εγγραφές από τον πίνακα data_issues.',
      ),
    );
  }

  Future<int> _nextId(
    DatabaseExecutor db,
    String table,
    String idColumn,
  ) async {
    final rows = await db.rawQuery(
      'SELECT COALESCE(MAX($idColumn), 0) + 1 AS next_id FROM $table',
    );
    return _support.toInt(rows.first['next_id']) ?? 1;
  }

  Future<void> _updateEquipmentOwner(
    Transaction txn, {
    required int code,
    required int ownerId,
    // Ρητό και υποχρεωτικό: η σιωπηλή προεπιλογή `false` έκανε τη δημιουργία
    // υπαλλήλου να αφήνει το ωμό κείμενο πίσω της, και ο επόμενος έλεγχος
    // ακεραιότητας το ξαναδιάβαζε ως πρόβλημα.
    required bool clearOriginalText,
    required ResolutionLogSink emit,
  }) async {
    final values = <String, Object?>{
      'owner': ownerId,
      if (clearOriginalText) 'owner_original_text': null,
    };
    await txn.update(
      'equipment',
      values,
      where: 'code = ?',
      whereArgs: <Object?>[code],
    );
    final ownerDisplay = await _support.fkTargetDisplay(txn, 'owner', ownerId);
    emit(
      ResolutionLogEntry.success(
        'Ενημερώθηκε ο υπάλληλος του εξοπλισμού $code σε $ownerDisplay.',
      ),
    );
  }

  Future<int?> _existingOwnerIdByIdentity(
    DatabaseExecutor db, {
    required String? lastName,
    required String? firstName,
  }) async {
    final target = UserIdentityNormalizer.identityKeyForPerson(
      firstName,
      lastName,
    );
    if (target.isEmpty) return null;
    final rows = await db.query(
      'owners',
      columns: <String>['owner', 'last_name', 'first_name'],
    );
    for (final row in rows) {
      final ownerId = _support.toInt(row['owner']);
      if (ownerId == null) continue;
      if (_support.ownerIdentityKeyFromRow(row) == target) return ownerId;
    }
    return null;
  }

  ({String lastName, String firstName})? _parseOwnerNameInput(String? raw) {
    final input = raw?.trim() ?? '';
    if (input.isEmpty) return null;

    final commaParts = input
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (commaParts.length >= 2) {
      final lastName = commaParts.first;
      final firstName = commaParts.sublist(1).join(' ').trim();
      if (lastName.isEmpty || firstName.isEmpty) return null;
      return (lastName: lastName, firstName: firstName);
    }

    final parsed = NameParserUtility.parse(input);
    if (parsed.firstName.isEmpty && parsed.lastName.isEmpty) return null;
    if (parsed.lastName.isEmpty) {
      return (lastName: parsed.firstName, firstName: '');
    }
    return (lastName: parsed.lastName, firstName: parsed.firstName);
  }
}

class _AppliedDecision {
  const _AppliedDecision({required this.created, this.unresolved = false});

  final bool created;

  /// Η ενέργεια εφαρμόστηκε εν μέρει και το πρόβλημα μένει ανοιχτό — ορισμός
  /// γραφείου χωρίς υπάλληλο.
  final bool unresolved;
}
