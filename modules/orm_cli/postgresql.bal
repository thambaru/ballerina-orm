import ballerinax/postgresql;
import ballerina/sql;

# Introspects a PostgreSQL database and returns its schema.
public function introspectPostgresql(postgresql:Client dbClient, string? schema = ()) returns IntrospectedSchema|error {
    string targetSchema = schema ?? "public";
    
    # Get all tables
    map<IntrospectedTable> tables = {};
    
    string tableQuery = string `
        SELECT table_name, table_schema
        FROM information_schema.tables
        WHERE table_schema NOT IN ('pg_catalog', 'information_schema')
    `;
    
    if schema is string {
        tableQuery = string `${tableQuery} AND table_schema = ?`;
    }
    
    sql:ParameterizedQuery tableQueryObj = sql:queryConcat(
        sql:`${tableQuery}`
    );
    
    record {
        string table_name;
        string table_schema;
    }[] tableRows;
    
    if schema is string {
        tableRows = check dbClient->query(tableQueryObj, schema);
    } else {
        tableRows = check dbClient->query(tableQueryObj);
    }
    
    foreach var tableRow in tableRows {
        string tableName = tableRow.table_name;
        string tableSchema = tableRow.table_schema;
        
        # Get columns for this table
        IntrospectedColumn[] columns = check getTableColumnsPostgres(dbClient, tableSchema, tableName);
        
        # Get indexes for this table
        IntrospectedIndex[] indexes = check getTableIndexesPostgres(dbClient, tableSchema, tableName);
        
        # Get foreign keys for this table
        IntrospectedForeignKey[] foreignKeys = check getTableForeignKeysPostgres(dbClient, tableSchema, tableName);
        
        tables[tableName] = {
            name: tableName,
            schema: tableSchema,
            columns,
            indexes,
            foreignKeys
        };
    }
    
    return {
        tables,
        provider: "POSTGRESQL"
    };
}

# Gets columns from a PostgreSQL table via pg_catalog.
private function getTableColumnsPostgres(postgresql:Client dbClient, string schema, string tableName) returns IntrospectedColumn[]|error {
    IntrospectedColumn[] columns = [];
    
    string columnQuery = string `
        SELECT
            c.column_name,
            c.data_type,
            c.is_nullable,
            c.character_maximum_length,
            c.numeric_precision,
            c.numeric_scale,
            c.column_default,
            EXISTS(
                SELECT 1 FROM information_schema.table_constraints tc
                JOIN information_schema.key_column_usage kcu
                    ON tc.constraint_name = kcu.constraint_name
                WHERE tc.table_schema = c.table_schema
                    AND tc.table_name = c.table_name
                    AND kcu.column_name = c.column_name
                    AND tc.constraint_type = 'PRIMARY KEY'
            ) as is_primary_key,
            EXISTS(
                SELECT 1 FROM information_schema.table_constraints tc
                JOIN information_schema.key_column_usage kcu
                    ON tc.constraint_name = kcu.constraint_name
                WHERE tc.table_schema = c.table_schema
                    AND tc.table_name = c.table_name
                    AND kcu.column_name = c.column_name
                    AND tc.constraint_type = 'UNIQUE'
            ) as is_unique
        FROM information_schema.columns c
        WHERE c.table_schema = ? AND c.table_name = ?
        ORDER BY c.ordinal_position
    `;
    
    sql:ParameterizedQuery colQueryObj = sql:queryConcat(
        sql:`${columnQuery}`
    );
    
    record {
        string column_name;
        string data_type;
        string is_nullable;
        int? character_maximum_length;
        int? numeric_precision;
        int? numeric_scale;
        string? column_default;
        boolean is_primary_key;
        boolean is_unique;
    }[] colRows = check dbClient->query(colQueryObj, schema, tableName);
    
    foreach var colRow in colRows {
        columns.push({
            name: colRow.column_name,
            type: colRow.data_type,
            nullable: colRow.is_nullable == "YES",
            isPrimaryKey: colRow.is_primary_key,
            isUnique: colRow.is_unique,
            isAutoIncrement: (colRow.column_default ?? "").includes("nextval"),
            defaultValue: colRow.column_default
        });
    }
    
    return columns;
}

# Gets indexes from a PostgreSQL table via pg_catalog.
private function getTableIndexesPostgres(postgresql:Client dbClient, string schema, string tableName) returns IntrospectedIndex[]|error {
    IntrospectedIndex[] indexes = [];
    
    string indexQuery = string `
        SELECT
            t.relname as index_name,
            a.attname as column_name,
            ix.indisunique as is_unique
        FROM
            pg_index ix
            JOIN pg_class i ON i.oid = ix.indexrelid
            JOIN pg_class t ON t.oid = ix.indrelid
            JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = ANY(ix.indkey)
            JOIN pg_namespace n ON n.oid = t.relnamespace
        WHERE
            n.nspname = ? AND t.relname = ? AND NOT ix.indisprimary
        ORDER BY i.relname, a.attnum
    `;
    
    sql:ParameterizedQuery idxQueryObj = sql:queryConcat(
        sql:`${indexQuery}`
    );
    
    record {
        string index_name;
        string column_name;
        boolean is_unique;
    }[] idxRows = check dbClient->query(idxQueryObj, schema, tableName);
    
    # Group by index name
    map<string[]> indexColumns = {};
    map<boolean> indexUnique = {};
    
    foreach var idxRow in idxRows {
        string idxName = idxRow.index_name;
        string colName = idxRow.column_name;
        
        if !indexColumns.hasKey(idxName) {
            indexColumns[idxName] = [];
            indexUnique[idxName] = idxRow.is_unique;
        }
        
        indexColumns[idxName].push(colName);
    }
    
    foreach var [idxName, cols] in indexColumns.entries() {
        indexes.push({
            name: idxName,
            columns: cols,
            unique: indexUnique.get(idxName) ?: false
        });
    }
    
    return indexes;
}

# Gets foreign keys from a PostgreSQL table via pg_catalog.
private function getTableForeignKeysPostgres(postgresql:Client dbClient, string schema, string tableName) returns IntrospectedForeignKey[]|error {
    IntrospectedForeignKey[] foreignKeys = [];
    
    string fkQuery = string `
        SELECT
            tc.constraint_name,
            kcu.column_name,
            ccu.table_name AS referenced_table_name,
            ccu.column_name AS referenced_column_name,
            rc.update_rule,
            rc.delete_rule
        FROM information_schema.table_constraints AS tc
        JOIN information_schema.key_column_usage AS kcu
            ON tc.constraint_name = kcu.constraint_name
            AND tc.table_schema = kcu.table_schema
        JOIN information_schema.constraint_column_usage AS ccu
            ON ccu.constraint_name = tc.constraint_name
            AND ccu.table_schema = tc.table_schema
        JOIN information_schema.referential_constraints AS rc
            ON rc.constraint_name = tc.constraint_name
        WHERE tc.constraint_type = 'FOREIGN KEY'
            AND tc.table_schema = ?
            AND tc.table_name = ?
    `;
    
    sql:ParameterizedQuery fkQueryObj = sql:queryConcat(
        sql:`${fkQuery}`
    );
    
    record {
        string constraint_name;
        string column_name;
        string referenced_table_name;
        string referenced_column_name;
        string update_rule;
        string delete_rule;
    }[] fkRows = check dbClient->query(fkQueryObj, schema, tableName);
    
    foreach var fkRow in fkRows {
        foreignKeys.push({
            name: fkRow.constraint_name,
            column: fkRow.column_name,
            referencedTable: fkRow.referenced_table_name,
            referencedColumn: fkRow.referenced_column_name,
            onDelete: fkRow.delete_rule,
            onUpdate: fkRow.update_rule
        });
    }
    
    return foreignKeys;
}
