import ballerina/sql;

# Row type for information_schema.tables query (PostgreSQL).
type PgTableRow record {|
    string table_name;
|};

# Row type for information_schema.columns query (PostgreSQL).
type PgColumnRow record {|
    string column_name;
    string data_type;
    string is_nullable;
    string? column_default;
    int? character_maximum_length;
    string? udt_name;
|};

# Row type for pg_indexes query.
type PgIndexRow record {|
    string indexname;
    string indexdef;
|};

# Row type for pg index columns query.
type PgIndexColRow record {|
    string indexname;
    string column_name;
    boolean indisunique;
|};

# Row type for FK query.
type PgFkRow record {|
    string constraint_name;
    string column_name;
    string foreign_table_name;
    string foreign_column_name;
    string? delete_rule;
    string? update_rule;
|};

# Row type for primary key column query.
type PgPkRow record {|string column_name;|};

# Row type for tracking applied migrations.
type PgMigRow record {|string id; string name;|};

# Introspects a PostgreSQL database and returns schema metadata.
public function introspectPostgresql(sql:Client dbClient, string? schema = ()) returns IntrospectedSchema|error {
    string selectedSchema = schema ?: "public";

    // List all base tables
    stream<PgTableRow, sql:Error?> tableStream = check dbClient->query(
        `SELECT table_name
         FROM information_schema.tables
         WHERE table_schema = ${selectedSchema}
           AND table_type = 'BASE TABLE'
         ORDER BY table_name`
    );
    PgTableRow[]|error tableRows = from PgTableRow row in tableStream select row;
    if tableRows is error {
        return tableRows;
    }

    PgTableRow[] tables = <PgTableRow[]>tableRows;
    map<IntrospectedTable> result = {};

    foreach PgTableRow tableRow in tables {
        string tableName = tableRow.table_name;

        // Columns
        stream<PgColumnRow, sql:Error?> colStream = check dbClient->query(
            `SELECT column_name,
                    data_type,
                    is_nullable,
                    column_default,
                    character_maximum_length,
                    udt_name
             FROM information_schema.columns
             WHERE table_schema = ${selectedSchema} AND table_name = ${tableName}
             ORDER BY ordinal_position`
        );
        PgColumnRow[]|error colRows = from PgColumnRow row in colStream select row;
        if colRows is error {
            return colRows;
        }

        IntrospectedColumn[] columns = [];
        foreach PgColumnRow col in <PgColumnRow[]>colRows {
            string colType = resolvePgColumnType(col);
            string? colDefault = col.column_default;
            boolean isAutoInc = colDefault is string && colDefault.indexOf("nextval") is int;
            columns.push({
                name: col.column_name,
                'type: colType,
                nullable: col.is_nullable == "YES",
                isAutoIncrement: isAutoInc,
                defaultValue: colDefault
            });
        }

        // Primary key columns
        stream<PgPkRow, sql:Error?> pkStream = check dbClient->query(
            `SELECT kcu.column_name
             FROM information_schema.table_constraints tc
             JOIN information_schema.key_column_usage kcu
               ON tc.constraint_name = kcu.constraint_name
              AND tc.table_schema = kcu.table_schema
             WHERE tc.table_schema = ${selectedSchema}
               AND tc.table_name = ${tableName}
               AND tc.constraint_type = 'PRIMARY KEY'
             ORDER BY kcu.ordinal_position`
        );
        PgPkRow[]|error pkRows = from PgPkRow row in pkStream select row;
        if pkRows is error {
            return pkRows;
        }
        map<boolean> pkCols = {};
        foreach PgPkRow pk in <PgPkRow[]>pkRows {
            pkCols[pk.column_name] = true;
        }
        // Mark primary key columns
        foreach int i in 0 ..< columns.length() {
            if pkCols.hasKey(columns[i].name) {
                IntrospectedColumn c = columns[i];
                columns[i] = {
                    name: c.name,
                    'type: c.'type,
                    nullable: c.nullable,
                    isPrimaryKey: true,
                    isUnique: c.isUnique,
                    isAutoIncrement: c.isAutoIncrement,
                    defaultValue: c.defaultValue
                };
            }
        }

        // Indexes (user-defined, excluding primary key)
        stream<PgIndexColRow, sql:Error?> idxStream = check dbClient->query(
            `SELECT i.relname AS indexname,
                    a.attname AS column_name,
                    ix.indisunique
             FROM pg_index ix
             JOIN pg_class t ON t.oid = ix.indrelid
             JOIN pg_class i ON i.oid = ix.indexrelid
             JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = ANY(ix.indkey)
             JOIN pg_namespace n ON n.oid = t.relnamespace
             WHERE n.nspname = ${selectedSchema}
               AND t.relname = ${tableName}
               AND ix.indisprimary = false
             ORDER BY i.relname, a.attnum`
        );
        PgIndexColRow[]|error idxRows = from PgIndexColRow row in idxStream select row;
        if idxRows is error {
            return idxRows;
        }

        map<IntrospectedIndex> indexMap = {};
        foreach PgIndexColRow idxRow in <PgIndexColRow[]>idxRows {
            if indexMap.hasKey(idxRow.indexname) {
                indexMap.get(idxRow.indexname).columns.push(idxRow.column_name);
            } else {
                indexMap[idxRow.indexname] = {
                    name: idxRow.indexname,
                    columns: [idxRow.column_name],
                    unique: idxRow.indisunique
                };
            }
        }
        IntrospectedIndex[] indexes = [];
        foreach string idxName in indexMap.keys() {
            indexes.push(indexMap.get(idxName));
        }

        // Foreign keys
        stream<PgFkRow, sql:Error?> fkStream = check dbClient->query(
            `SELECT tc.constraint_name,
                    kcu.column_name,
                    ccu.table_name AS foreign_table_name,
                    ccu.column_name AS foreign_column_name,
                    rc.delete_rule,
                    rc.update_rule
             FROM information_schema.table_constraints tc
             JOIN information_schema.key_column_usage kcu
               ON tc.constraint_name = kcu.constraint_name
              AND tc.table_schema = kcu.table_schema
             JOIN information_schema.constraint_column_usage ccu
               ON ccu.constraint_name = tc.constraint_name
              AND ccu.table_schema = tc.table_schema
             JOIN information_schema.referential_constraints rc
               ON rc.constraint_name = tc.constraint_name
             WHERE tc.constraint_type = 'FOREIGN KEY'
               AND tc.table_schema = ${selectedSchema}
               AND tc.table_name = ${tableName}`
        );
        PgFkRow[]|error fkRows = from PgFkRow row in fkStream select row;
        if fkRows is error {
            return fkRows;
        }

        IntrospectedForeignKey[] foreignKeys = [];
        foreach PgFkRow fk in <PgFkRow[]>fkRows {
            foreignKeys.push({
                name: fk.constraint_name,
                column: fk.column_name,
                referencedTable: fk.foreign_table_name,
                referencedColumn: fk.foreign_column_name,
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

    return {tables: result, provider: "POSTGRESQL"};
}

function resolvePgColumnType(PgColumnRow col) returns string {
    string dt = col.data_type;
    int? maxLen = col.character_maximum_length;
    if dt == "character varying" {
        if maxLen is int {
            return "varchar(" + maxLen.toString() + ")";
        }
        return "varchar";
    }
    if dt == "character" {
        if maxLen is int {
            return "char(" + maxLen.toString() + ")";
        }
        return "char";
    }
    if dt == "integer" { return "int"; }
    if dt == "bigint" { return "bigint"; }
    if dt == "smallint" { return "smallint"; }
    if dt == "boolean" { return "boolean"; }
    if dt == "text" { return "text"; }
    if dt == "real" { return "float"; }
    if dt == "double precision" { return "double"; }
    if dt == "numeric" || dt == "decimal" {
        string? udt = col.udt_name;
        if udt is string {
            return udt;
        }
        return "numeric";
    }
    if dt == "timestamp without time zone" { return "timestamp"; }
    if dt == "timestamp with time zone" { return "timestamptz"; }
    if dt == "date" { return "date"; }
    if dt == "time without time zone" { return "time"; }
    if dt == "json" { return "json"; }
    if dt == "jsonb" { return "jsonb"; }
    if dt == "uuid" { return "uuid"; }
    return dt;
}

# Ensures the _orm_migrations tracking table exists in PostgreSQL.
public function ensurePostgresqlMigrationsTable(sql:Client dbClient) returns error? {
    _ = check dbClient->execute(
        `CREATE TABLE IF NOT EXISTS _orm_migrations (
            id VARCHAR(255) NOT NULL,
            name VARCHAR(255) NOT NULL,
            applied_at TIMESTAMP NOT NULL DEFAULT NOW(),
            PRIMARY KEY (id)
        )`
    );
}

# Reads applied migrations from PostgreSQL _orm_migrations table.
public function getAppliedMigrationsPostgresql(sql:Client dbClient) returns Migration[]|error {
    check ensurePostgresqlMigrationsTable(dbClient);
    stream<PgMigRow, sql:Error?> s = check dbClient->query(
        `SELECT id, name FROM _orm_migrations ORDER BY id`
    );
    PgMigRow[]|error rows = from PgMigRow r in s select r;
    if rows is error {
        return rows;
    }
    Migration[] migrations = [];
    foreach PgMigRow r in <PgMigRow[]>rows {
        migrations.push({id: r.id, name: r.name, path: "", sql: ""});
    }
    return migrations;
}

# Records a migration as applied in PostgreSQL _orm_migrations table.
public function recordMigrationAppliedPostgresql(sql:Client dbClient, string migrationId, string migrationName) returns error? {
    check ensurePostgresqlMigrationsTable(dbClient);
    _ = check dbClient->execute(
        `INSERT INTO _orm_migrations (id, name) VALUES (${migrationId}, ${migrationName})`
    );
}

# Executes a migration SQL string against PostgreSQL (splits on ';').
public function executeMigrationOnPostgresql(sql:Client dbClient, string migrationSql) returns error? {
    int cursor = 0;
    while cursor < migrationSql.length() {
        int? semi = migrationSql.indexOf(";", cursor);
        int end = semi is int ? semi : migrationSql.length();
        string stmt = migrationSql.substring(cursor, end).trim();
        if stmt != "" {
            // Build a raw (no-parameter) ParameterizedQuery
            sql:ParameterizedQuery q = ``;
            q.strings = [stmt].cloneReadOnly();
            _ = check dbClient->execute(q);
        }
        cursor = end + 1;
    }
}
