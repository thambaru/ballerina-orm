import ballerinax/mysql;
import ballerina/sql;
import ballerina/regex;

# Introspects a MySQL database and returns its schema.
public function introspectMysql(mysql:Client dbClient, string? database = ()) returns IntrospectedSchema|error {
    string targetDb = database ?? "information_schema";
    
    # Get all tables
    map<IntrospectedTable> tables = {};
    
    string tableQuery = string `
        SELECT TABLE_SCHEMA, TABLE_NAME 
        FROM INFORMATION_SCHEMA.TABLES 
        WHERE TABLE_SCHEMA != 'information_schema' 
        AND TABLE_SCHEMA != 'mysql' 
        AND TABLE_SCHEMA != 'performance_schema'
        AND TABLE_SCHEMA != 'sys'
    `;
    
    if database is string {
        tableQuery = string `${tableQuery} AND TABLE_SCHEMA = ?`;
    }
    
    sql:ParameterizedQuery tableQueryObj = sql:queryConcat(
        sql:`${tableQuery}`
    );
    
    record {
        string TABLE_SCHEMA;
        string TABLE_NAME;
    }[] tableRows = check dbClient->query(tableQueryObj);
    
    foreach var tableRow in tableRows {
        string tableName = tableRow.TABLE_NAME;
        string schema = tableRow.TABLE_SCHEMA;
        
        # Get columns for this table
        IntrospectedColumn[] columns = check getTableColumns(dbClient, schema, tableName);
        
        # Get indexes for this table
        IntrospectedIndex[] indexes = check getTableIndexes(dbClient, schema, tableName);
        
        # Get foreign keys for this table
        IntrospectedForeignKey[] foreignKeys = check getTableForeignKeys(dbClient, schema, tableName);
        
        tables[tableName] = {
            name: tableName,
            schema: schema,
            columns,
            indexes,
            foreignKeys
        };
    }
    
    return {
        tables,
        provider: "MYSQL"
    };
}

# Gets columns from a MySQL table via information_schema.
private function getTableColumns(mysql:Client dbClient, string schema, string tableName) returns IntrospectedColumn[]|error {
    IntrospectedColumn[] columns = [];
    
    string columnQuery = string `
        SELECT 
            COLUMN_NAME, 
            COLUMN_TYPE,
            IS_NULLABLE,
            COLUMN_KEY,
            EXTRA,
            COLUMN_DEFAULT
        FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ?
        ORDER BY ORDINAL_POSITION
    `;
    
    sql:ParameterizedQuery colQueryObj = sql:queryConcat(
        sql:`${columnQuery}`
    );
    
    record {
        string COLUMN_NAME;
        string COLUMN_TYPE;
        string IS_NULLABLE;
        string COLUMN_KEY;
        string EXTRA;
        string? COLUMN_DEFAULT;
    }[] colRows = check dbClient->query(colQueryObj, schema, tableName);
    
    foreach var colRow in colRows {
        string colType = colRow.COLUMN_TYPE;
        
        # Parse base type and length from COLUMN_TYPE (e.g., "varchar(255)" -> "varchar", 255)
        [string, int?] [baseType, length] = parseColumnType(colType);
        
        boolean isPrimaryKey = colRow.COLUMN_KEY == "PRI";
        boolean isUnique = colRow.COLUMN_KEY == "UNI";
        boolean isAutoIncrement = colRow.EXTRA.includes("auto_increment");
        
        columns.push({
            name: colRow.COLUMN_NAME,
            type: baseType,
            nullable: colRow.IS_NULLABLE == "YES",
            isPrimaryKey,
            isUnique,
            isAutoIncrement,
            defaultValue: colRow.COLUMN_DEFAULT
        });
    }
    
    return columns;
}

# Gets indexes from a MySQL table via information_schema.
private function getTableIndexes(mysql:Client dbClient, string schema, string tableName) returns IntrospectedIndex[]|error {
    IntrospectedIndex[] indexes = [];
    
    string indexQuery = string `
        SELECT 
            INDEX_NAME, 
            COLUMN_NAME,
            NON_UNIQUE
        FROM INFORMATION_SCHEMA.STATISTICS
        WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ? AND INDEX_NAME != 'PRIMARY'
        ORDER BY INDEX_NAME, SEQ_IN_INDEX
    `;
    
    sql:ParameterizedQuery idxQueryObj = sql:queryConcat(
        sql:`${indexQuery}`
    );
    
    record {
        string INDEX_NAME;
        string COLUMN_NAME;
        int NON_UNIQUE;
    }[] idxRows = check dbClient->query(idxQueryObj, schema, tableName);
    
    # Group by index name
    map<string[]> indexColumns = {};
    map<int> indexUnique = {};
    
    foreach var idxRow in idxRows {
        string idxName = idxRow.INDEX_NAME;
        string colName = idxRow.COLUMN_NAME;
        
        if !indexColumns.hasKey(idxName) {
            indexColumns[idxName] = [];
            indexUnique[idxName] = idxRow.NON_UNIQUE;
        }
        
        indexColumns[idxName].push(colName);
    }
    
    foreach var [idxName, cols] in indexColumns.entries() {
        indexes.push({
            name: idxName,
            columns: cols,
            unique: indexUnique[idxName] == 0
        });
    }
    
    return indexes;
}

# Gets foreign keys from a MySQL table via information_schema.
private function getTableForeignKeys(mysql:Client dbClient, string schema, string tableName) returns IntrospectedForeignKey[]|error {
    IntrospectedForeignKey[] foreignKeys = [];
    
    string fkQuery = string `
        SELECT 
            CONSTRAINT_NAME,
            COLUMN_NAME,
            REFERENCED_TABLE_NAME,
            REFERENCED_COLUMN_NAME,
            DELETE_RULE,
            UPDATE_RULE
        FROM INFORMATION_SCHEMA.REFERENTIAL_CONSTRAINTS
        JOIN INFORMATION_SCHEMA.KEY_COLUMN_USAGE 
            ON REFERENTIAL_CONSTRAINTS.CONSTRAINT_NAME = KEY_COLUMN_USAGE.CONSTRAINT_NAME
            AND REFERENTIAL_CONSTRAINTS.TABLE_NAME = KEY_COLUMN_USAGE.TABLE_NAME
        WHERE REFERENTIAL_CONSTRAINTS.TABLE_SCHEMA = ? 
        AND REFERENTIAL_CONSTRAINTS.TABLE_NAME = ?
    `;
    
    sql:ParameterizedQuery fkQueryObj = sql:queryConcat(
        sql:`${fkQuery}`
    );
    
    record {
        string CONSTRAINT_NAME;
        string COLUMN_NAME;
        string? REFERENCED_TABLE_NAME;
        string? REFERENCED_COLUMN_NAME;
        string DELETE_RULE;
        string UPDATE_RULE;
    }[] fkRows = check dbClient->query(fkQueryObj, schema, tableName);
    
    foreach var fkRow in fkRows {
        if fkRow.REFERENCED_TABLE_NAME is string && fkRow.REFERENCED_COLUMN_NAME is string {
            foreignKeys.push({
                name: fkRow.CONSTRAINT_NAME,
                column: fkRow.COLUMN_NAME,
                referencedTable: fkRow.REFERENCED_TABLE_NAME,
                referencedColumn: fkRow.REFERENCED_COLUMN_NAME,
                onDelete: fkRow.DELETE_RULE,
                onUpdate: fkRow.UPDATE_RULE
            });
        }
    }
    
    return foreignKeys;
}

# Parses MySQL COLUMN_TYPE into base type and optional length.
# Example: "varchar(255)" -> ["varchar", 255]
#          "int" -> ["int", ()]
#          "decimal(10,2)" -> ["decimal", 10] (simplified)
private function parseColumnType(string columnType) returns [string, int?] {
    int? openParen = columnType.indexOf("(");
    
    if openParen is () {
        return [columnType.trim(), ()];
    }
    
    string baseType = columnType.substring(0, openParen).trim();
    int? closeParen = columnType.indexOf(")");
    
    if closeParen is () {
        return [baseType, ()];
    }
    
    string params = columnType.substring(openParen + 1, closeParen);
    string[] parts = regex:split(params, ",");
    
    if parts.length() > 0 {
        int|error length = int:fromString(parts[0].trim());
        if length is int {
            return [baseType, length];
        }
    }
    
    return [baseType, ()];
}
