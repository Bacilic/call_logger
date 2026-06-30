#!/usr/bin/env python3
"""Split directory_repository.dart into mixin-based part files."""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "lib/core/database/directory_repository.dart"

PART_METHODS: dict[str, set[str]] = {
    "directory_repository_phones.part.dart": {
        "_addDepartmentPhoneInTxn",
        "addDepartmentDirectPhone",
        "removeDepartmentDirectPhone",
        "getPhoneIdByNumber",
        "countPhoneReferencesExcludingAudit",
        "softDeletePhones",
        "getDepartmentDirectPhonesMap",
        "phoneNumberExists",
        "updatePhoneDepartment",
        "removePhoneFromAllUsers",
    },
    "directory_repository_users.part.dart": {
        "replaceUserPhones",
        "getAllUsers",
        "_userRowAuditValues",
        "_validateUserPhoneAssignmentPolicy",
        "insertUserFromMap",
        "_userPhoneNumbersOrdered",
        "_departmentNameForUserTxn",
        "getEquipmentOwnerSnapshots",
        "updateUser",
        "bulkUpdateUsers",
        "findExclusivePhonesForUserDelete",
        "_unlinkUserFromPhoneInTxn",
        "deleteUsers",
        "restoreUsers",
        "insertUser",
        "updateAssociationsIfNeeded",
    },
    "directory_repository_departments.part.dart": {
        "departmentNameExists",
        "getOrCreateDepartmentIdByName",
        "getDepartments",
        "getActiveDepartments",
        "getDepartmentRowById",
        "insertDepartment",
        "_isSqliteUniqueConstraintFailure",
        "_findDepartmentRowByKey",
        "_restoreDepartmentsInTxn",
        "restoreDepartmentByName",
        "saveDepartmentWithFloorContext",
        "backfillDepartmentFloorIdsFromMapFloor",
        "backfillAllDepartmentNameKeys",
        "_kBuildingMapPlacementClearedDefaults",
        "buildingMapPlacementColumnNames",
        "clearedBuildingMapPlacementColumns",
        "_applyDepartmentNameKeyFromName",
        "updateDepartment",
        "bulkUpdateDepartments",
        "softDeleteDepartment",
        "softDeleteDepartments",
        "restoreDepartments",
        "departmentNameExistsExcluding",
        "getDepartmentNameById",
    },
    "directory_repository_equipment.part.dart": {
        "getEquipmentIdByCode",
        "equipmentCodeExists",
        "countEquipmentReferencesExcludingAudit",
        "getEquipmentDefaultRemoteToolUsageCounts",
        "updateEquipmentDepartment",
        "clearEquipmentSharedDepartment",
        "removeEquipmentFromAllUsers",
        "getAllEquipment",
        "getAllUserEquipmentLinks",
        "countUsersLinkedToEquipment",
        "unlinkUserFromEquipment",
        "linkUserToEquipment",
        "copyUserEquipmentLinks",
        "replaceEquipmentUsers",
        "insertEquipmentFromMap",
        "updateEquipment",
        "bulkUpdateEquipments",
        "deleteEquipments",
        "restoreEquipment",
    },
    "directory_repository_categories.part.dart": {
        "getCategoryNames",
        "getActiveCategoryRows",
        "findActiveCategoryByNormalizedName",
        "categoryNormalizedNameTaken",
        "_findSoftDeletedCategoryRowByNormalizedName",
        "insertCategoryAndGetId",
        "updateCategoryNameAndSyncCalls",
        "softDeleteCategories",
        "restoreCategories",
    },
    "directory_repository_building_map.part.dart": {
        "listBuildingMapFloors",
        "insertBuildingMapFloor",
        "updateBuildingMapFloor",
        "countDepartmentsReferencingMapFloor",
        "deleteBuildingMapFloorClearingDepartmentMaps",
        "_buildingMapFloorDisplayLabel",
        "_isDepartmentMappedOnMap",
    },
    "directory_repository_settings_search.part.dart": {
        "getSetting",
        "setSetting",
        "getNonUserPhonesCatalogRows",
        "_omnisearchRank",
        "_omnisearchMapDisplayLabelFlat",
        "_omnisearchDepartmentMapDisplayLabel",
        "_omnisearchDepartmentSubtitle",
        "_omnisearchUnmappedHintForDepartmentId",
        "searchBuildingMapOmnisearch",
    },
    "directory_repository_integrity.part.dart": {
        "softDeleteTask",
        "softDeletePhoneForIntegrity",
        "deleteCallExternalLinkForIntegrity",
        "deleteOrphanUserPhonesJunction",
        "deleteOrphanDepartmentPhonesJunction",
        "deleteOrphanUserEquipmentJunction",
        "linkOrphanPhoneToDepartmentForIntegrity",
        "linkOrphanPhoneToUserForIntegrity",
        "fixDepartmentNameKeyForIntegrity",
        "softDeleteUserForIntegrity",
        "updateUserDepartmentForIntegrity",
        "integrityUpdateTaskFk",
        "integritySyncTaskTimestamps",
        "integrityDepartmentLabel",
        "integrityUserLabel",
    },
}

MAIN_METHODS: set[str] = {
    "_ensurePhonesDepartmentColumn",
    "_ensurePhonesIsDeletedColumn",
    "_phoneDigitsOnly",
    "_auditPerformingUser",
    "_kUserAuditColumns",
    "_userDisplayNameFromRow",
    "_userRowById",
    "_departmentAuditSnapshot",
    "_applyDepartmentAuditText",
    "_userPhoneIds",
    "_phoneNumbersByIds",
    "_equipmentCodesByIds",
    "_auditPhoneUserLinkDeltaInTxn",
    "_auditEquipmentUserLinkDeltaInTxn",
    "_replaceUserPhonesInTxn",
    "_readCount",
    "_equipmentIdsForUser",
    "_linkedEquipmentSnapshotsForUser",
    "_linkedUserSnapshotsForEquipment",
}

METHOD_START_RE = re.compile(
    r"^  (?:"
    r"static const\b|"
    r"static Iterable\b|"
    r"static Map<|"
    r"static void\b|"
    r"static bool\b|"
    r"static int\b|"
    r"static String\b|"
    r"Future<|"
    r"Future\b|"
    r"void\b|"
    r"int\b|"
    r"String\b|"
    r"bool\b|"
    r"List<|"
    r"Map<"
    r")"
)

MIXIN_NAMES: dict[str, str] = {
    "directory_repository_phones.part.dart": "DirectoryRepositoryPhones",
    "directory_repository_users.part.dart": "DirectoryRepositoryUsers",
    "directory_repository_departments.part.dart": "DirectoryRepositoryDepartments",
    "directory_repository_equipment.part.dart": "DirectoryRepositoryEquipment",
    "directory_repository_categories.part.dart": "DirectoryRepositoryCategories",
    "directory_repository_building_map.part.dart": "DirectoryRepositoryBuildingMap",
    "directory_repository_settings_search.part.dart": "DirectoryRepositorySettingsSearch",
    "directory_repository_integrity.part.dart": "DirectoryRepositoryIntegrity",
}

STATIC_CLASS_MEMBERS = (
    "_readCount",
    "_phoneDigitsOnly",
    "_kUserAuditColumns",
)


def qualify_static_members(body: str) -> str:
    for member in STATIC_CLASS_MEMBERS:
        body = re.sub(rf"(?<!\.)\b{re.escape(member)}\(", f"DirectoryRepository.{member}(", body)
        body = re.sub(rf"(?<!\.)\b{re.escape(member)}\b", f"DirectoryRepository.{member}", body)
    return body


def extract_method_name(line: str) -> str | None:
    if " static const " in f" {line}" or line.strip().startswith("static const "):
        assign = re.search(r"\b(_?\w+)\s*=", line)
        if assign:
            return assign.group(1)
    getter = re.search(r"\bget\s+(\w+)\b", line)
    if getter:
        return getter.group(1)
    arrow = re.search(r"\b(_?\w+)\s*\([^)]*\)\s*=>", line)
    if arrow:
        return arrow.group(1)
    calls = list(re.finditer(r"\b(_?\w+)\s*\(", line))
    if calls:
        return calls[-1].group(1)
    assign = re.search(r"\b(_?\w+)\s*=", line)
    if assign:
        return assign.group(1)
    return None


def parse_methods(lines: list[str]) -> list[tuple[str, int, int]]:
    class_start = next(
        i for i, line in enumerate(lines) if line.startswith("class DirectoryRepository")
    )
    class_end = len(lines) - 1
    for i in range(class_start + 1, len(lines)):
        if lines[i].strip() == "}" and not lines[i].startswith("  "):
            class_end = i
            break

    starts: list[tuple[str, int]] = []
    i = class_start + 1
    while i < class_end:
        line = lines[i]
        if not METHOD_START_RE.match(line):
            i += 1
            continue

        sig_parts = [line.rstrip()]
        j = i
        is_const_field = "static const" in line
        while j < class_end:
            current = lines[j]
            if is_const_field:
                if current.strip().endswith("};") or (
                    current.strip() == "};" or re.search(r"};\s*$", current)
                ):
                    break
            elif re.search(r"\)\s*(?:async\s*)?{", current) or "=>" in current:
                break
            if j + 1 >= class_end:
                break
            j += 1
            sig_parts.append(lines[j].rstrip())
        signature = " ".join(part.strip() for part in sig_parts)
        name = extract_method_name(signature)
        if name:
            starts.append((name, i))
        i = j + 1

    methods: list[tuple[str, int, int]] = []
    for idx, (name, start) in enumerate(starts):
        if idx + 1 < len(starts):
            end = starts[idx + 1][1] - 1
        else:
            end = class_end - 1
        methods.append((name, start + 1, end + 1))
    return methods


def assign_part(name: str) -> str:
    if name in MAIN_METHODS:
        return "main"
    for part, names in PART_METHODS.items():
        if name in names:
            return part
    raise KeyError(f"Unassigned method: {name}")


def mixin_for(part_file: str) -> str:
    return MIXIN_NAMES[part_file]


def main() -> None:
    lines = SRC.read_text(encoding="utf-8").splitlines(keepends=True)
    methods = parse_methods(lines)

    all_names = {m[0] for m in methods}
    mapped = MAIN_METHODS.copy()
    for names in PART_METHODS.values():
        mapped |= names
    missing = all_names - mapped
    extra = mapped - all_names
    if missing:
        raise SystemExit(f"Methods missing from mapping: {sorted(missing)}")
    if extra:
        raise SystemExit(f"Unknown methods in mapping: {sorted(extra)}")

    import_end = next(i for i, line in enumerate(lines) if line.startswith("import "))
    last_import = import_end
    for i in range(import_end, len(lines)):
        if lines[i].startswith("import ") or lines[i].strip() == "":
            last_import = i
        else:
            break

    imports = "".join(lines[: last_import + 1])
    if not imports.endswith("\n\n"):
        imports += "\n"

    part_decls = "\n".join(f"part '{p}';" for p in PART_METHODS) + "\n\n"

    class_line_idx = next(
        i for i, line in enumerate(lines) if line.startswith("class DirectoryRepository")
    )
    pre_class = "".join(lines[last_import + 1 : class_line_idx])

    class_open = (
        "class DirectoryRepository {\n"
        "  DirectoryRepository(this.db);\n\n"
        "  final Database db;\n\n"
    )

    main_body: list[str] = []
    for name, start, end in methods:
        if assign_part(name) != "main":
            continue
        main_body.append("".join(lines[start - 1 : end]))

    main_content = (
        imports
        + part_decls
        + pre_class
        + class_open
        + "".join(main_body)
        + "}\n"
    )

    out_dir = SRC.parent
    SRC.write_text(main_content, encoding="utf-8")

    for part_file in PART_METHODS:
        mixin = mixin_for(part_file)
        chunks: list[str] = [
            "part of 'directory_repository.dart';\n\n",
            f"extension {mixin} on DirectoryRepository {{\n",
        ]
        for name, start, end in methods:
            if assign_part(name) != part_file:
                continue
            body = "".join(lines[start - 1 : end])
            chunks.append(qualify_static_members(body))
        chunks.append("}\n")
        (out_dir / part_file).write_text("".join(chunks), encoding="utf-8")

    print("Split complete (mixin-based parts).")
    for part_file in PART_METHODS:
        count = sum(1 for n, _, _ in methods if assign_part(n) == part_file)
        print(f"  {part_file}: {count} methods")


if __name__ == "__main__":
    main()
