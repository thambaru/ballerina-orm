# Schema IR and normalized source types used by parser and validator.

# Error detail payload for schema parsing and validation failures.
#
# + code - Machine-readable error code.
# + message - Human-readable description of the failure.
# + model - Name of the model where the error occurred, if applicable.
# + fieldName - Name of the field where the error occurred, if applicable.
public type SchemaIssue record {|
    string code;
    string message;
    string? model;
    string? fieldName;
|};

# Error type used by the schema subsystem.
public type SchemaError error<SchemaIssue>;

# Input payload consumed by the runtime schema parser.
#
# This is the normalized schema source currently produced manually or by compiler tooling.
#
# + models - List of raw model definitions.
# + defaultEngine - Default database provider applied to all models unless overridden.
public type RawSchema record {|
    RawModel[] models;
    Engine? defaultEngine = ();
|};

# Normalized source definition for a single model.
#
# + name - Model name (typically the Ballerina record type name).
# + entity - Entity-level mapping settings from the @orm:Entity annotation.
# + fields - List of raw field definitions.
# + indexes - List of index definitions from @orm:Index annotations.
public type RawModel record {|
    string name;
    EntityConfig entity = {};
    RawField[] fields;
    IndexConfig[] indexes = [];
|};

# Normalized source definition for a single model field.
#
# + name - Field name as declared in the Ballerina record.
# + ballerinaType - Ballerina type string of the field.
# + isOptional - Whether the field is declared as optional.
# + isArray - Whether the field is declared as an array.
# + id - Whether the field is annotated with @orm:Id.
# + autoIncrement - Whether the field is annotated with @orm:AutoIncrement.
# + createdAt - Whether the field is annotated with @orm:CreatedAt.
# + updatedAt - Whether the field is annotated with @orm:UpdatedAt.
# + ignored - Whether the field is annotated with @orm:Ignore.
# + column - Column-level config from @orm:Column, if present.
# + relation - Relation config from @orm:Relation, if present.
public type RawField record {|
    string name;
    string ballerinaType;
    boolean isOptional = false;
    boolean isArray = false;
    boolean id = false;
    boolean autoIncrement = false;
    boolean createdAt = false;
    boolean updatedAt = false;
    boolean ignored = false;
    ColumnConfig? column = ();
    RelationConfig? relation = ();
|};

# Parsed graph of all models and relation edges.
#
# + models - Map of model name to parsed model definition.
# + relationEdges - Directed relation edges between models.
public type SchemaGraph record {|
    map<ModelDefinition> models;
    RelationEdge[] relationEdges;
|};

# Parsed model definition.
#
# + name - Model name.
# + tableName - Resolved database table name.
# + schema - Database schema prefix, if any.
# + engine - Database provider override for this model.
# + columns - List of parsed column definitions.
# + columnsByField - Map from field name to column definition for fast lookup.
# + indexes - List of parsed index definitions.
# + relations - List of parsed relation definitions.
public type ModelDefinition record {|
    string name;
    string tableName;
    string? schema;
    Engine? engine = ();
    ColumnDefinition[] columns;
    map<ColumnDefinition> columnsByField;
    IndexDefinition[] indexes;
    RelationDefinition[] relations;
|};

# Parsed column definition.
#
# + fieldName - Ballerina field name.
# + columnName - Database column name.
# + ballerinaType - Ballerina type string.
# + dbType - Explicit database column type override, if any.
# + length - Maximum character length, if configured.
# + nullable - Whether the column accepts NULL values.
# + unique - Whether the column has a unique constraint.
# + isId - Whether this column is part of the primary key.
# + autoIncrement - Whether the column is auto-incremented by the database.
# + createdAt - Whether the column is ORM-managed as a creation timestamp.
# + updatedAt - Whether the column is ORM-managed as an update timestamp.
# + hasDefault - Whether the column has a configured default value.
# + defaultValue - The default value, if any.
public type ColumnDefinition record {|
    string fieldName;
    string columnName;
    string ballerinaType;
    string? dbType;
    int? length;
    boolean nullable;
    boolean unique;
    boolean isId;
    boolean autoIncrement;
    boolean createdAt;
    boolean updatedAt;
    boolean hasDefault;
    anydata? defaultValue;
|};

# Parsed index definition.
#
# + name - Index name.
# + columns - List of column names forming the index.
# + unique - Whether the index enforces uniqueness.
public type IndexDefinition record {|
    string name;
    string[] columns;
    boolean unique;
|};

# Parsed relation definition from one model field.
#
# + fieldName - Name of the relation field on this model.
# + targetModel - Name of the related model.
# + relationType - Kind of relation (ONE_TO_ONE, ONE_TO_MANY, etc.).
# + references - Primary-key fields on the target model.
# + foreignKey - Foreign-key fields on the owning model.
# + joinTable - Join table name for MANY_TO_MANY relations, if any.
public type RelationDefinition record {|
    string fieldName;
    string targetModel;
    RelationType relationType;
    string[] references;
    string[] foreignKey;
    string? joinTable;
|};

# Directed edge representation for relation graph traversal.
#
# + fromModel - Name of the source model.
# + fromField - Name of the relation field on the source model.
# + toModel - Name of the target model.
# + relationType - Kind of relation.
# + references - Primary-key fields on the target model.
# + foreignKey - Foreign-key fields on the source model.
# + joinTable - Join table name for MANY_TO_MANY relations, if any.
public type RelationEdge record {|
    string fromModel;
    string fromField;
    string toModel;
    RelationType relationType;
    string[] references;
    string[] foreignKey;
    string? joinTable;
|};

# Build a structured schema error.
#
# + code - Machine-readable error code.
# + message - Human-readable error description.
# + model - Model name context, if applicable.
# + fieldName - Field name context, if applicable.
# + return - A SchemaError with the given payload.
function schemaError(string code, string message, string? model = (), string? fieldName = ()) returns SchemaError {
    return error("SCHEMA_ERROR", code = code, message = message, model = model, fieldName = fieldName);
}

# Normalize a model name to a default snake_case plural table name.
#
# + modelName - PascalCase model name (e.g. `UserProfile`).
# + return - Plural snake_case table name (e.g. `user_profiles`).
function toDefaultTableName(string modelName) returns string {
    return pluralizeSnakeCase(toSnakeCase(modelName));
}

function pluralizeSnakeCase(string tableName) returns string {
    if tableName.endsWith("fe") {
        return string `${tableName.substring(0, tableName.length() - 2)}ves`;
    }
    if tableName.endsWith("f") {
        return string `${tableName.substring(0, tableName.length() - 1)}ves`;
    }

    int length = tableName.length();
    if length > 1 && tableName.endsWith("y") {
        string previous = tableName.substring(length - 2, length - 1);
        if !isLowercaseVowel(previous) {
            return string `${tableName.substring(0, length - 1)}ies`;
        }
    }

    if tableName.endsWith("s") || tableName.endsWith("x") || tableName.endsWith("z") ||
        tableName.endsWith("ch") || tableName.endsWith("sh") {
        return string `${tableName}es`;
    }

    return string `${tableName}s`;
}

function isLowercaseVowel(string value) returns boolean {
    return value == "a" || value == "e" || value == "i" || value == "o" || value == "u";
}

# Convert a PascalCase or camelCase identifier to snake_case.
#
# + value - Identifier string to convert.
# + return - snake_case equivalent of the input string.
function toSnakeCase(string value) returns string {
    int len = value.length();
    if len == 0 {
        return value;
    }

    string out = "";
    int index = 0;
    while index < len {
        string c = value.substring(index, index + 1);
        if index > 0 && c >= "A" && c <= "Z" {
            out = string `${out}_${c.toLowerAscii()}`;
        } else {
            out = string `${out}${c.toLowerAscii()}`;
        }
        index += 1;
    }

    return out;
}

# Join non-empty tokens with an underscore.
#
# + parts - Array of string tokens to join.
# + return - Underscore-joined non-empty tokens.
function underscoreJoin(string[] parts) returns string {
    string out = "";
    foreach string part in parts {
        if part == "" {
            continue;
        }
        if out == "" {
            out = part;
        } else {
            out = string `${out}_${part}`;
        }
    }
    return out;
}

# Infer a target model identifier from a raw field type string.
#
# + ballerinaType - Ballerina type string of the relation field.
# + return - The inferred model name extracted from the type.
function inferModelNameFromType(string ballerinaType) returns string {
    string value = ballerinaType.trim();
    if value.endsWith("?") {
        value = value.substring(0, value.length() - 1);
    }
    if value.endsWith("[]") {
        value = value.substring(0, value.length() - 2);
    }
    int? sep = value.lastIndexOf(":");
    if sep is int {
        value = value.substring(sep + 1);
    }
    return value;
}
