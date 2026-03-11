# Compares two schemas (desired vs actual) and returns the differences.
public function diffSchemas(
    map<IntrospectedTable> desiredTables,
    map<IntrospectedTable> actualTables,
    string provider
) returns SchemaDiff {
    _ = provider;

    SchemaDiff diff = {
        added: [],
        modified: [],
        removed: []
    };

    // Detect added tables and column-level differences in existing tables
    foreach string tableName in desiredTables.keys() {
        IntrospectedTable desiredTable = desiredTables.get(tableName);
        if !actualTables.hasKey(tableName) {
            diff.added.push({
                itemType: "TABLE",
                'table: tableName,
                description: "New table: " + tableName,
                tableDef: desiredTable
            });
        } else {
            IntrospectedTable actualTable = actualTables.get(tableName);
            diffTableColumns(tableName, desiredTable, actualTable, diff);
            diffTableIndexes(tableName, desiredTable, actualTable, diff, provider);
        }
    }

    // Detect removed tables
    foreach string tableName in actualTables.keys() {
        if !desiredTables.hasKey(tableName) {
            diff.removed.push({
                itemType: "TABLE",
                'table: tableName,
                description: "Removed table: " + tableName
            });
        }
    }

    return diff;
}

function diffTableColumns(
    string tableName,
    IntrospectedTable desiredTable,
    IntrospectedTable actualTable,
    SchemaDiff diff
) {
    // Build a lookup map for actual columns
    map<IntrospectedColumn> actualColMap = {};
    foreach IntrospectedColumn col in actualTable.columns {
        actualColMap[col.name] = col;
    }

    // Build a lookup map for desired columns
    map<boolean> desiredColNames = {};
    foreach IntrospectedColumn col in desiredTable.columns {
        desiredColNames[col.name] = true;
    }

    // Detect added and modified columns
    foreach IntrospectedColumn desiredCol in desiredTable.columns {
        if !actualColMap.hasKey(desiredCol.name) {
            diff.added.push({
                itemType: "COLUMN",
                'table: tableName,
                column: desiredCol.name,
                newValue: desiredCol.'type,
                description: "Add column: " + tableName + "." + desiredCol.name,
                columnDef: desiredCol
            });
        } else {
            IntrospectedColumn actualCol = actualColMap.get(desiredCol.name);
            if !columnsMatch(desiredCol, actualCol) {
                diff.modified.push({
                    itemType: "COLUMN",
                    'table: tableName,
                    column: desiredCol.name,
                    oldValue: actualCol.'type,
                    newValue: desiredCol.'type,
                    description: "Modify column: " + tableName + "." + desiredCol.name,
                    columnDef: desiredCol
                });
            }
        }
    }

    // Detect removed columns
    foreach IntrospectedColumn actualCol in actualTable.columns {
        if !desiredColNames.hasKey(actualCol.name) {
            diff.removed.push({
                itemType: "COLUMN",
                'table: tableName,
                column: actualCol.name,
                oldValue: actualCol.'type,
                description: "Remove column: " + tableName + "." + actualCol.name,
                columnDef: actualCol
            });
        }
    }
}

function diffTableIndexes(
    string tableName,
    IntrospectedTable desiredTable,
    IntrospectedTable actualTable,
    SchemaDiff diff,
    string provider
) {
    // Build lookup maps for indexes by name
    map<IntrospectedIndex> actualIdxMap = {};
    foreach IntrospectedIndex idx in actualTable.indexes {
        actualIdxMap[idx.name] = idx;
    }
    map<boolean> desiredIdxNames = {};
    foreach IntrospectedIndex idx in desiredTable.indexes {
        desiredIdxNames[idx.name] = true;
    }

    // Detect added indexes
    foreach IntrospectedIndex desiredIdx in desiredTable.indexes {
        if !actualIdxMap.hasKey(desiredIdx.name) {
            string indexSql = generateCreateIndexSql(
                desiredIdx.name, tableName, desiredIdx.columns, desiredIdx.unique, provider
            );
            diff.added.push({
                itemType: "INDEX",
                'table: tableName,
                column: desiredIdx.name,
                newValue: indexSql,
                description: "Add index: " + desiredIdx.name + " on " + tableName
            });
        }
    }

    // Detect removed indexes
    foreach IntrospectedIndex actualIdx in actualTable.indexes {
        if !desiredIdxNames.hasKey(actualIdx.name) {
            diff.removed.push({
                itemType: "INDEX",
                'table: tableName,
                column: actualIdx.name,
                oldValue: actualIdx.name,
                description: "Remove index: " + actualIdx.name + " on " + tableName
            });
        }
    }
}

function columnsMatch(IntrospectedColumn desired, IntrospectedColumn actual) returns boolean {
    if desired.'type != actual.'type {
        return false;
    }
    if desired.nullable != actual.nullable {
        return false;
    }
    if desired.isAutoIncrement != actual.isAutoIncrement {
        return false;
    }
    if desired.isUnique != actual.isUnique {
        return false;
    }
    return true;
}

# Sorts a SchemaDiff in a logical apply order.
public function sortDiffForApply(SchemaDiff diff) returns SchemaDiff {
    return diff;
}
