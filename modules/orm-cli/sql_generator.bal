# Generates SQL statements from schema diff for MySQL or PostgreSQL.
public function generateMigrationSql(
    SchemaDiff diff,
    string provider,
    string? tablePrefix = ()
) returns string|error {
    string sql = "";
    string prefix = tablePrefix ?? "";
    
    # Add new items
    foreach var item in diff.added {
        string sql_stmt = "";
        match item.itemType {
            "TABLE" => {
                sql_stmt = check generateCreateTableSql(item.table, [], provider);
            }
            "COLUMN" => {
                if item.column is string {
                    sql_stmt = generateAddColumnSql(item.table, item.column, getDefaultColumnDefinition(), provider);
                }
            }
            "INDEX" => {
                # Partial support, needs table structure info
                sql_stmt = "";
            }
        }
        
        if sql_stmt != "" {
            sql = sql + sql_stmt + "\n";
        }
    }
    
    # Modify items
    foreach var item in diff.modified {
        string sql_stmt = "";
        match item.itemType {
            "COLUMN" => {
                if item.column is string {
                    sql_stmt = generateModifyColumnSql(item.table, item.column, getDefaultColumnDefinition(), provider);
                }
            }
        }
        
        if sql_stmt != "" {
            sql = sql + sql_stmt + "\n";
        }
    }
    
    # Remove items (in reverse order)
    foreach var item in diff.removed {
        string sql_stmt = "";
        match item.itemType {
            "INDEX" => {
                if item.description.includes("Drop index") {
                    sql_stmt = generateDropIndexSql(extractIndexName(item.description), item.table, provider);
                }
            }
            "COLUMN" => {
                if item.column is string {
                    sql_stmt = generateDropColumnSql(item.table, item.column, provider);
                }
            }
            "TABLE" => {
                sql_stmt = generateDropTableSql(item.table, provider);
            }
        }
        
        if sql_stmt != "" {
            sql = sql + sql_stmt + "\n";
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
    string sql = string `CREATE TABLE ${tableName} (`;
    string[] columnDefs = [];
    
    foreach var col in columns {
        string colDef = generateColumnDefinition(col, provider);
        columnDefs.push(colDef);
    }
    
    if columnDefs.length() > 0 {
        sql = sql + "\n  " + ", ".join(...columnDefs) + "\n";
    }
    
    sql = sql + ")";
    
    if provider == "MYSQL" {
        sql = sql + " ENGINE=InnoDB DEFAULT CHARSET=utf8mb4";
    }
    
    sql = sql + ";";
    
    return sql;
}

# Generates column definition SQL.
private function generateColumnDefinition(IntrospectedColumn col, string provider) returns string {
    string def = col.name + " " + getColumnTypeSql(col.type, col, provider);
    
    if !col.nullable {
        def = def + " NOT NULL";
    }
    
    if col.isPrimaryKey {
        def = def + " PRIMARY KEY";
        if col.isAutoIncrement {
            if provider == "MYSQL" {
                def = def + " AUTO_INCREMENT";
            } else if provider == "POSTGRESQL" {
                # PostgreSQL uses SERIAL or BIGSERIAL
                def = col.name + " SERIAL PRIMARY KEY";
            }
        }
    }
    
    if col.isAutoIncrement && !col.isPrimaryKey {
        if provider == "MYSQL" {
            def = def + " AUTO_INCREMENT";
        }
    }
    
    if col.isUnique {
        def = def + " UNIQUE";
    }
    
    if col.defaultValue is string && col.defaultValue != "" {
        def = def + " DEFAULT " + col.defaultValue;
    }
    
    return def;
}

# Maps introspected column type to SQL type.
private function getColumnTypeSql(
    string type,
    IntrospectedColumn col,
    string provider
) returns string {
    # Type mapping
    map<string> typeMap = (provider == "MYSQL") ? getMySQLTypeMap() : getPostgresTypeMap();
    string sqlType = typeMap.get(type) ?: type;
    
    # Add length if needed
    if col.name != "" {
        # This is a simplified mapping, can be enhanced
        if (type == "varchar" || type == "character varying") && col.name != "" {
            sqlType = sqlType + "(255)";
        }
    }
    
    return sqlType;
}

# Gets MySQL type mappings.
private function getMySQLTypeMap() returns map<string> {
    return {
        "INT": "INT",
        "INTEGER": "INT",
        "BIGINT": "BIGINT",
        "SMALLINT": "SMALLINT",
        "TINYINT": "TINYINT",
        "DECIMAL": "DECIMAL",
        "NUMERIC": "NUMERIC",
        "FLOAT": "FLOAT",
        "DOUBLE": "DOUBLE",
        "VARCHAR": "VARCHAR",
        "character varying": "VARCHAR",
        "CHAR": "CHAR",
        "TEXT": "TEXT",
        "LONGTEXT": "LONGTEXT",
        "BOOLEAN": "BOOLEAN",
        "DATE": "DATE",
        "TIME": "TIME",
        "DATETIME": "DATETIME",
        "TIMESTAMP": "TIMESTAMP",
        "JSON": "JSON",
        "JSONB": "JSON"
    };
}

# Gets PostgreSQL type mappings.
private function getPostgresTypeMap() returns map<string> {
    return {
        "INT": "INTEGER",
        "INTEGER": "INTEGER",
        "BIGINT": "BIGINT",
        "SMALLINT": "SMALLINT",
        "SERIAL": "SERIAL",
        "BIGSERIAL": "BIGSERIAL",
        "DECIMAL": "NUMERIC",
        "NUMERIC": "NUMERIC",
        "FLOAT": "REAL",
        "DOUBLE": "DOUBLE PRECISION",
        "VARCHAR": "CHARACTER VARYING",
        "character varying": "CHARACTER VARYING",
        "CHAR": "CHARACTER",
        "TEXT": "TEXT",
        "BOOLEAN": "BOOLEAN",
        "DATE": "DATE",
        "TIME": "TIME",
        "TIMESTAMP": "TIMESTAMP",
        "TIMESTAMPTZ": "TIMESTAMP WITH TIME ZONE",
        "JSON": "JSON",
        "JSONB": "JSONB",
        "UUID": "UUID"
    };
}

# Generates ADD COLUMN SQL.
private function generateAddColumnSql(
    string table,
    string column,
    IntrospectedColumn col,
    string provider
) returns string {
    string colDef = generateColumnDefinition(col, provider);
    
    if provider == "MYSQL" {
        return string `ALTER TABLE ${table} ADD COLUMN ${colDef};`;
    } else {
        return string `ALTER TABLE ${table} ADD COLUMN ${colDef};`;
    }
}

# Generates MODIFY COLUMN SQL.
private function generateModifyColumnSql(
    string table,
    string column,
    IntrospectedColumn col,
    string provider
) returns string {
    string colDef = generateColumnDefinition(col, provider);
    
    if provider == "MYSQL" {
        return string `ALTER TABLE ${table} MODIFY COLUMN ${colDef};`;
    } else {
        # PostgreSQL uses ALTER COLUMN
        return string `ALTER TABLE ${table} ALTER COLUMN ${column} SET NOT NULL;`;
    }
}

# Generates DROP COLUMN SQL.
private function generateDropColumnSql(string table, string column, string provider) returns string {
    return string `ALTER TABLE ${table} DROP COLUMN ${column};`;
}

# Generates CREATE INDEX SQL.
public function generateCreateIndexSql(
    string indexName,
    string table,
    string[] columns,
    boolean unique,
    string provider
) returns string {
    string uniqueStr = unique ? "UNIQUE " : "";
    string columnList = ", ".join(...columns);
    return string `CREATE ${uniqueStr}INDEX ${indexName} ON ${table} (${columnList});`;
}

# Generates DROP INDEX SQL.
private function generateDropIndexSql(string indexName, string table, string provider) returns string {
    if provider == "MYSQL" {
        return string `ALTER TABLE ${table} DROP INDEX ${indexName};`;
    } else {
        return string `DROP INDEX ${indexName};`;
    }
}

# Generates DROP TABLE SQL.
private function generateDropTableSql(string table, string provider) returns string {
    return string `DROP TABLE ${table};`;
}

# Extracts index name from description string.
private function extractIndexName(string description) returns string {
    # Example: "Drop index idx_name on (col1, col2)"
    int? start = description.indexOf(" ");
    if start is () {
        return "";
    }
    
    int? end = description.indexOf(" on ");
    if end is () {
        end = description.length();
    }
    
    return description.substring(start + 1, end).trim();
}

# Gets default column definition for placeholder.
private function getDefaultColumnDefinition() returns IntrospectedColumn {
    return {
        name: "new_column",
        type: "VARCHAR",
        nullable: true,
        isPrimaryKey: false,
        isUnique: false,
        isAutoIncrement: false
    };
}
