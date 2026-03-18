# Generates SQL statements from schema diff for MySQL or PostgreSQL.
public function generateMigrationSql(
    SchemaDiff diff,
    string provider,
    string? tablePrefix = ()
) returns string|error {
    string prefix = "";
    if tablePrefix is string {
        prefix = tablePrefix;
    }

    string sql = "";

    foreach SchemaDiffItem item in diff.added {
        if item.itemType == "TABLE" {
            IntrospectedTable? tbl = item.tableDef;
            if tbl is IntrospectedTable {
                sql = sql + generateCreateTableSql(prefix + item.'table, tbl.columns, provider) + "\n";
            } else {
                sql = sql + generateCreateTableSql(prefix + item.'table, [], provider) + "\n";
            }
        } else if item.itemType == "COLUMN" {
            IntrospectedColumn? col = item.columnDef;
            if col is IntrospectedColumn {
                string colDef = generateColumnDefSql(col, provider);
                sql = sql + generateAlterAddColumnSql(item.'table, colDef, provider) + "\n";
            }
        } else if item.itemType == "INDEX" {
            string? newVal = item.newValue;
            if newVal is string {
                sql = sql + newVal + "\n";
            }
        }
    }

    foreach SchemaDiffItem item in diff.modified {
        if item.itemType == "COLUMN" {
            IntrospectedColumn? col = item.columnDef;
            if col is IntrospectedColumn {
                string colDef = generateColumnDefSql(col, provider);
                sql = sql + generateAlterModifyColumnSql(item.'table, col.name, colDef, provider) + "\n";
            }
        }
    }

    foreach SchemaDiffItem item in diff.removed {
        if item.itemType == "TABLE" {
            sql = sql + generateDropTableSql(prefix + item.'table, provider) + "\n";
        } else if item.itemType == "COLUMN" {
            string colName = item.column ?: "";
            if colName != "" {
                sql = sql + generateAlterDropColumnSql(item.'table, colName, provider) + "\n";
            }
        } else if item.itemType == "INDEX" {
            string idxName = item.column ?: "";
            if idxName != "" {
                sql = sql + generateDropIndexSql(idxName, item.'table, provider) + "\n";
            }
        }
    }

    return sql;
}

# Generates CREATE TABLE SQL with full column definitions.
public function generateCreateTableSql(
    string tableName,
    IntrospectedColumn[] columns,
    string provider
) returns string {
    string quotedTable = quoteCliIdentifier(tableName, provider);

    if columns.length() == 0 {
        return "CREATE TABLE " + quotedTable + " ();";
    }

    string[] colDefs = [];
    string[] pkCols = [];

    foreach IntrospectedColumn col in columns {
        colDefs.push("  " + generateColumnDefSql(col, provider));
        if col.isPrimaryKey {
            pkCols.push(quoteCliIdentifier(col.name, provider));
        }
    }

    if pkCols.length() > 0 {
        string pkList = joinCliStrings(pkCols, ", ");
        colDefs.push("  PRIMARY KEY (" + pkList + ")");
    }

    string body = joinCliStrings(colDefs, ",\n");
    return "CREATE TABLE " + quotedTable + " (\n" + body + "\n);";
}

# Generates DROP TABLE SQL.
public function generateDropTableSql(string tableName, string provider) returns string {
    return "DROP TABLE " + quoteCliIdentifier(tableName, provider) + ";";
}

# Generates ALTER TABLE ADD COLUMN SQL.
public function generateAlterAddColumnSql(
    string tableName,
    string columnDefinition,
    string provider
) returns string {
    string quotedTable = quoteCliIdentifier(tableName, provider);
    return "ALTER TABLE " + quotedTable + " ADD COLUMN " + columnDefinition + ";";
}

# Generates ALTER TABLE DROP COLUMN SQL.
public function generateAlterDropColumnSql(
    string tableName,
    string columnName,
    string provider
) returns string {
    string quotedTable = quoteCliIdentifier(tableName, provider);
    string quotedCol = quoteCliIdentifier(columnName, provider);
    return "ALTER TABLE " + quotedTable + " DROP COLUMN " + quotedCol + ";";
}

# Generates ALTER TABLE MODIFY/ALTER COLUMN SQL.
public function generateAlterModifyColumnSql(
    string tableName,
    string columnName,
    string columnDefinition,
    string provider
) returns string {
    string quotedTable = quoteCliIdentifier(tableName, provider);
    if provider == "MYSQL" {
        return "ALTER TABLE " + quotedTable + " MODIFY COLUMN " + columnDefinition + ";";
    }
    // PostgreSQL uses ALTER COLUMN ... TYPE
    string quotedCol = quoteCliIdentifier(columnName, provider);
    return "ALTER TABLE " + quotedTable + " ALTER COLUMN " + quotedCol + " TYPE " + columnDefinition + ";";
}

# Generates CREATE INDEX SQL.
public function generateCreateIndexSql(
    string indexName,
    string tableName,
    string[] columns,
    boolean unique,
    string provider
) returns string {
    string uniqueStr = "";
    if unique {
        uniqueStr = "UNIQUE ";
    }
    string quotedTable = quoteCliIdentifier(tableName, provider);
    string quotedIndex = quoteCliIdentifier(indexName, provider);
    string[] quotedCols = [];
    foreach string col in columns {
        quotedCols.push(quoteCliIdentifier(col, provider));
    }
    string columnList = joinCliStrings(quotedCols, ", ");
    if provider == "MYSQL" {
        return "CREATE " + uniqueStr + "INDEX " + quotedIndex + " ON " + quotedTable + " (" + columnList + ");";
    }
    return "CREATE " + uniqueStr + "INDEX " + quotedIndex + " ON " + quotedTable + " (" + columnList + ");";
}

# Generates DROP INDEX SQL (dialect-aware).
public function generateDropIndexSql(
    string indexName,
    string tableName,
    string provider
) returns string {
    string quotedIndex = quoteCliIdentifier(indexName, provider);
    if provider == "MYSQL" {
        string quotedTable = quoteCliIdentifier(tableName, provider);
        return "DROP INDEX " + quotedIndex + " ON " + quotedTable + ";";
    }
    // PostgreSQL DROP INDEX does not need ON tableName
    return "DROP INDEX " + quotedIndex + ";";
}

# Generates a column definition SQL fragment (without ALTER TABLE prefix).
public function generateColumnDefSql(IntrospectedColumn col, string provider) returns string {
    string quoted = quoteCliIdentifier(col.name, provider);
    string typeSql = resolveCliColumnType(col, provider);
    string notNull = col.nullable ? "" : " NOT NULL";
    string autoInc = "";
    if col.isAutoIncrement && provider == "MYSQL" {
        autoInc = " AUTO_INCREMENT";
    }
    string uniqueSql = "";
    if col.isUnique && !col.isPrimaryKey {
        uniqueSql = " UNIQUE";
    }
    string defaultSql = "";
    string? dv = col.defaultValue;
    if dv is string {
        defaultSql = " DEFAULT " + dv;
    }
    return quoted + " " + typeSql + notNull + autoInc + uniqueSql + defaultSql;
}

function resolveCliColumnType(IntrospectedColumn col, string provider) returns string {
    if col.isAutoIncrement && provider == "POSTGRESQL" {
        return "SERIAL";
    }
    return col.'type;
}

function quoteCliIdentifier(string name, string provider) returns string {
    string escaped = "";
    int index = 0;
    if provider == "MYSQL" {
        while index < name.length() {
            string c = name.substring(index, index + 1);
            if c == "`" {
                escaped = escaped + "``";
            } else {
                escaped = escaped + c;
            }
            index += 1;
        }
        return "`" + escaped + "`";
    }
    while index < name.length() {
        string c = name.substring(index, index + 1);
        if c == "\"" {
            escaped = escaped + "\"\"";
        } else {
            escaped = escaped + c;
        }
        index += 1;
    }
    return "\"" + escaped + "\"";
}

function joinCliStrings(string[] parts, string sep) returns string {
    string out = "";
    foreach string part in parts {
        if out == "" {
            out = part;
        } else {
            out = out + sep + part;
        }
    }
    return out;
}
