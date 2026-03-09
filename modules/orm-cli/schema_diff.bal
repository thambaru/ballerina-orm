import ballerina/io;

# Compares two schemas (desired vs actual) and returns the differences.
public function diffSchemas(
    map<IntrospectedTable> desiredTables,
    map<IntrospectedTable> actualTables,
    string provider
) returns SchemaDiff {
    SchemaDiff diff = {
        added: [],
        modified: [],
        removed: []
    };
    
    # Find added and modified tables
    foreach var [tableName, desiredTable] in desiredTables.entries() {
        if !actualTables.hasKey(tableName) {
            # Table is new
            diff.added.push({
                itemType: "TABLE",
                table: tableName,
                description: "New table"
            });
        } else {
            IntrospectedTable actualTable = actualTables[tableName];
            
            # Check for column changes
            diffTableColumns(desiredTable, actualTable, tableName, diff);
            
            # Check for index changes
            diffTableIndexes(desiredTable, actualTable, tableName, diff);
        }
    }
    
    # Find removed tables
    foreach var [tableName, _] in actualTables.entries() {
        if !desiredTables.hasKey(tableName) {
            diff.removed.push({
                itemType: "TABLE",
                table: tableName,
                description: "Removed table"
            });
        }
    }
    
    return diff;
}

# Diffs columns between desired and actual table.
private function diffTableColumns(
    IntrospectedTable desiredTable,
    IntrospectedTable actualTable,
    string tableName,
    SchemaDiff diff
) {
    map<IntrospectedColumn> desiredCols = {};
    map<IntrospectedColumn> actualCols = {};
    
    foreach var col in desiredTable.columns {
        desiredCols[col.name] = col;
    }
    
    foreach var col in actualTable.columns {
        actualCols[col.name] = col;
    }
    
    # Find added and modified columns
    foreach var [colName, desiredCol] in desiredCols.entries() {
        if !actualCols.hasKey(colName) {
            diff.added.push({
                itemType: "COLUMN",
                table: tableName,
                column: colName,
                description: string `Add column ${colName} (${desiredCol.type})`
            });
        } else {
            IntrospectedColumn actualCol = actualCols[colName];
            
            # Check if column definition changed
            if !columnsAreEqual(desiredCol, actualCol) {
                diff.modified.push({
                    itemType: "COLUMN",
                    table: tableName,
                    column: colName,
                    oldValue: columnDefinitionString(actualCol),
                    newValue: columnDefinitionString(desiredCol),
                    description: string `Modify column ${colName}`
                });
            }
        }
    }
    
    # Find removed columns
    foreach var [colName, _] in actualCols.entries() {
        if !desiredCols.hasKey(colName) {
            diff.removed.push({
                itemType: "COLUMN",
                table: tableName,
                column: colName,
                description: string `Remove column ${colName}`
            });
        }
    }
}

# Diffs indexes between desired and actual table.
private function diffTableIndexes(
    IntrospectedTable desiredTable,
    IntrospectedTable actualTable,
    string tableName,
    SchemaDiff diff
) {
    map<IntrospectedIndex> desiredIdxs = {};
    map<IntrospectedIndex> actualIdxs = {};
    
    foreach var idx in desiredTable.indexes {
        desiredIdxs[idx.name] = idx;
    }
    
    foreach var idx in actualTable.indexes {
        actualIdxs[idx.name] = idx;
    }
    
    # Find added indexes
    foreach var [idxName, desiredIdx] in desiredIdxs.entries() {
        if !actualIdxs.hasKey(idxName) {
            diff.added.push({
                itemType: "INDEX",
                table: tableName,
                description: string `Create index ${idxName} on (${", ".join(...desiredIdx.columns)})`
            });
        }
    }
    
    # Find removed indexes
    foreach var [idxName, _] in actualIdxs.entries() {
        if !desiredIdxs.hasKey(idxName) {
            # Skip primary key
            if idxName != "PRIMARY" {
                diff.removed.push({
                    itemType: "INDEX",
                    table: tableName,
                    description: string `Drop index ${idxName}`
                });
            }
        }
    }
}

# Checks if two column definitions are equivalent.
private function columnsAreEqual(IntrospectedColumn col1, IntrospectedColumn col2) returns boolean {
    return col1.type == col2.type
        && col1.nullable == col2.nullable
        && col1.isPrimaryKey == col2.isPrimaryKey
        && col1.isUnique == col2.isUnique
        && col1.isAutoIncrement == col2.isAutoIncrement;
}

# Converts a column to a string representation.
private function columnDefinitionString(IntrospectedColumn col) returns string {
    string def = col.name + " " + col.type;
    
    if !col.nullable {
        def = def + " NOT NULL";
    }
    
    if col.isPrimaryKey {
        def = def + " PRIMARY KEY";
    }
    
    if col.isAutoIncrement {
        def = def + " AUTO_INCREMENT";
    }
    
    if col.isUnique {
        def = def + " UNIQUE";
    }
    
    return def;
}

# Sorts a SchemaDiff in a logical order for applying migrations.
public function sortDiffForApply(SchemaDiff diff) returns SchemaDiff {
    # Order: tables first (in order), then columns, then indexes
    SchemaDiff sorted = {
        added: [],
        modified: [],
        removed: []
    };
    
    # Add tables
    foreach var item in diff.added {
        if item.itemType == "TABLE" {
            sorted.added.push(item);
        }
    }
    
    # Add columns to new tables
    foreach var item in diff.added {
        if item.itemType == "COLUMN" {
            sorted.added.push(item);
        }
    }
    
    # Add indexes
    foreach var item in diff.added {
        if item.itemType == "INDEX" {
            sorted.added.push(item);
        }
    }
    
    # Modified items
    sorted.modified = diff.modified;
    
    # Removed: reverse order (indexes, columns, tables)
    foreach var item in diff.removed {
        if item.itemType == "INDEX" {
            sorted.removed.push(item);
        }
    }
    
    foreach var item in diff.removed {
        if item.itemType == "COLUMN" {
            sorted.removed.push(item);
        }
    }
    
    foreach var item in diff.removed {
        if item.itemType == "TABLE" {
            sorted.removed.push(item);
        }
    }
    
    return sorted;
}
