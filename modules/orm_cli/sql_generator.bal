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
            sql = sql + generateCreateTableSql(prefix + item.'table, [], provider) + "\n";
        }
    }

    foreach SchemaDiffItem item in diff.removed {
        if item.itemType == "TABLE" {
            sql = sql + string `DROP TABLE ${prefix}${item.'table};` + "\n";
        }
    }

    return sql;
}

# Generates CREATE TABLE SQL.
public function generateCreateTableSql(
    string tableName,
    IntrospectedColumn[] columns,
    string provider
) returns string {
    _ = columns;
    _ = provider;
    return string `CREATE TABLE ${tableName} ();`;
}

# Generates CREATE INDEX SQL.
public function generateCreateIndexSql(
    string indexName,
    string tableName,
    string[] columns,
    boolean unique,
    string provider
) returns string {
    _ = provider;
    string uniqueStr = "";
    if unique {
        uniqueStr = "UNIQUE ";
    }

    string columnList = ", ".join(...columns);
    return string `CREATE ${uniqueStr}INDEX ${indexName} ON ${tableName} (${columnList});`;
}
