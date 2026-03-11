import ballerina/sql;

# Row type for information_schema.TABLES query.
type MysqlTableRow record {|
    string table_name;
|};

# Row type for information_schema.COLUMNS query.
type MysqlColumnRow record {|
    string column_name;
    string column_type;
    string is_nullable;
    string? column_default;
    string column_key;
    string extra;
|};

# Row type for information_schema.STATISTICS query.
type MysqlIndexRow record {|
    string index_name;
    string column_name;
    int non_unique;
|};

# Row type for information_schema FK query.
type MysqlFkRow record {|
    string constraint_name;
    string column_name;
    string referenced_table_name;
    string referenced_column_name;
    string? delete_rule;
    string? update_rule;
|};

# Row type for querying current database.
type MysqlDbRow record {|string db_name?;|};

# Row type for tracking applied migrations.
type MysqlMigRow record {|string id; string name;|};

# Introspects a MySQL database and returns schema metadata.
public function introspectMysql(sql:Client dbClient, string? database = ()) returns IntrospectedSchema|error {
    string selectedDatabase = database ?: "";
    if selectedDatabase == "" {
        stream<MysqlDbRow, sql:Error?> dbStream = check dbClient->query(
            `SELECT DATABASE() AS db_name`
        );
        MysqlDbRow[]|error dbs = from MysqlDbRow row in dbStream select row;
        if dbs is error || (<MysqlDbRow[]>dbs).length() == 0 {
            return error("Could not determine current database");
        }
        string? val = (<MysqlDbRow[]>dbs)[0].db_name;
        if val is () {
            return error("Current database is null; connect with a database selected");
        }
        selectedDatabase = val;
    }

    // List all base tables
    stream<MysqlTableRow, sql:Error?> tableStream = check dbClient->query(
        `SELECT TABLE_NAME AS table_name
         FROM information_schema.TABLES
         WHERE TABLE_SCHEMA = ${selectedDatabase} AND TABLE_TYPE = 'BASE TABLE'
         ORDER BY TABLE_NAME`
    );
    MysqlTableRow[]|error tableRows = from MysqlTableRow row in tableStream select row;
    if tableRows is error {
        return tableRows;
    }

    MysqlTableRow[] tables = <MysqlTableRow[]>tableRows;
    map<IntrospectedTable> result = {};

    foreach MysqlTableRow tableRow in tables {
        string tableName = tableRow.table_name;

        // Columns
        stream<MysqlColumnRow, sql:Error?> colStream = check dbClient->query(
            `SELECT COLUMN_NAME AS column_name,
                    COLUMN_TYPE AS column_type,
                    IS_NULLABLE AS is_nullable,
                    COLUMN_DEFAULT AS column_default,
                    COLUMN_KEY AS column_key,
                    EXTRA AS extra
             FROM information_schema.COLUMNS
             WHERE TABLE_SCHEMA = ${selectedDatabase} AND TABLE_NAME = ${tableName}
             ORDER BY ORDINAL_POSITION`
        );
        MysqlColumnRow[]|error colRows = from MysqlColumnRow row in colStream select row;
        if colRows is error {
            return colRows;
        }

        IntrospectedColumn[] columns = [];
        foreach MysqlColumnRow col in <MysqlColumnRow[]>colRows {
            boolean isAutoInc = col.extra.indexOf("auto_increment") is int;
            columns.push({
                name: col.column_name,
                'type: col.column_type,
                nullable: col.is_nullable == "YES",
                isPrimaryKey: col.column_key == "PRI",
                isUnique: col.column_key == "UNI",
                isAutoIncrement: isAutoInc,
                defaultValue: col.column_default
            });
        }

        // Indexes (excluding PRIMARY)
        stream<MysqlIndexRow, sql:Error?> idxStream = check dbClient->query(
            `SELECT INDEX_NAME AS index_name,
                    COLUMN_NAME AS column_name,
                    NON_UNIQUE AS non_unique
             FROM information_schema.STATISTICS
             WHERE TABLE_SCHEMA = ${selectedDatabase}
               AND TABLE_NAME = ${tableName}
               AND INDEX_NAME != 'PRIMARY'
             ORDER BY INDEX_NAME, SEQ_IN_INDEX`
        );
        MysqlIndexRow[]|error idxRows = from MysqlIndexRow row in idxStream select row;
        if idxRows is error {
            return idxRows;
        }

        // Group index rows by index name
        map<IntrospectedIndex> indexMap = {};
        foreach MysqlIndexRow idxRow in <MysqlIndexRow[]>idxRows {
            if indexMap.hasKey(idxRow.index_name) {
                indexMap.get(idxRow.index_name).columns.push(idxRow.column_name);
            } else {
                indexMap[idxRow.index_name] = {
                    name: idxRow.index_name,
                    columns: [idxRow.column_name],
                    unique: idxRow.non_unique == 0
                };
            }
        }

        IntrospectedIndex[] indexes = [];
        foreach string idxName in indexMap.keys() {
            indexes.push(indexMap.get(idxName));
        }

        // Foreign keys
        stream<MysqlFkRow, sql:Error?> fkStream = check dbClient->query(
            `SELECT k.CONSTRAINT_NAME AS constraint_name,
                    k.COLUMN_NAME AS column_name,
                    k.REFERENCED_TABLE_NAME AS referenced_table_name,
                    k.REFERENCED_COLUMN_NAME AS referenced_column_name,
                    r.DELETE_RULE AS delete_rule,
                    r.UPDATE_RULE AS update_rule
             FROM information_schema.KEY_COLUMN_USAGE k
             JOIN information_schema.REFERENTIAL_CONSTRAINTS r
               ON k.CONSTRAINT_NAME = r.CONSTRAINT_NAME
              AND k.CONSTRAINT_SCHEMA = r.CONSTRAINT_SCHEMA
             WHERE k.TABLE_SCHEMA = ${selectedDatabase}
               AND k.TABLE_NAME = ${tableName}
               AND k.REFERENCED_TABLE_NAME IS NOT NULL`
        );
        MysqlFkRow[]|error fkRows = from MysqlFkRow row in fkStream select row;
        if fkRows is error {
            return fkRows;
        }

        IntrospectedForeignKey[] foreignKeys = [];
        foreach MysqlFkRow fk in <MysqlFkRow[]>fkRows {
            foreignKeys.push({
                name: fk.constraint_name,
                column: fk.column_name,
                referencedTable: fk.referenced_table_name,
                referencedColumn: fk.referenced_column_name,
                onDelete: fk.delete_rule,
                onUpdate: fk.update_rule
            });
        }

        result[tableName] = {
            name: tableName,
            columns,
            indexes,
            foreignKeys
        };
    }

    return {tables: result, provider: "MYSQL"};
}

# Ensures the _orm_migrations tracking table exists in MySQL.
public function ensureMysqlMigrationsTable(sql:Client dbClient) returns error? {
    _ = check dbClient->execute(
        `CREATE TABLE IF NOT EXISTS _orm_migrations (
            id VARCHAR(255) NOT NULL,
            name VARCHAR(255) NOT NULL,
            applied_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`
    );
}

# Reads applied migrations from MySQL _orm_migrations table.
public function getAppliedMigrationsMysql(sql:Client dbClient) returns Migration[]|error {
    check ensureMysqlMigrationsTable(dbClient);
    stream<MysqlMigRow, sql:Error?> s = check dbClient->query(
        `SELECT id, name FROM _orm_migrations ORDER BY id`
    );
    MysqlMigRow[]|error rows = from MysqlMigRow r in s select r;
    if rows is error {
        return rows;
    }
    Migration[] migrations = [];
    foreach MysqlMigRow r in <MysqlMigRow[]>rows {
        migrations.push({id: r.id, name: r.name, path: "", sql: ""});
    }
    return migrations;
}

# Records a migration as applied in MySQL _orm_migrations table.
public function recordMigrationAppliedMysql(sql:Client dbClient, string migrationId, string migrationName) returns error? {
    check ensureMysqlMigrationsTable(dbClient);
    _ = check dbClient->execute(
        `INSERT INTO _orm_migrations (id, name) VALUES (${migrationId}, ${migrationName})`
    );
}

# Executes a migration SQL string against MySQL (splits on ';').
public function executeMigrationOnMysql(sql:Client dbClient, string migrationSql) returns error? {
    // Execute each non-empty statement separated by semicolons.
    // The SQL is trusted (internally generated DDL), so raw execution is safe.
    int cursor = 0;
    while cursor < migrationSql.length() {
        int? semi = migrationSql.indexOf(";", cursor);
        int end = semi is int ? semi : migrationSql.length();
        string stmt = migrationSql.substring(cursor, end).trim();
        if stmt != "" {
            // Build a raw (no-parameter) ParameterizedQuery using the same pattern
            // as assembleParameterizedQuery in the ORM client module.
            sql:ParameterizedQuery q = ``;
            q.strings = [stmt].cloneReadOnly();
            _ = check dbClient->execute(q);
        }
        cursor = end + 1;
    }
}
