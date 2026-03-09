# Schema IR and normalized source types used by parser and validator.

# Error detail payload for schema parsing and validation failures.
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
# This mirrors information extracted from annotations and record fields.
public type RawSchema record {|
    RawModel[] models;
|};

# Normalized source definition for a single model.
public type RawModel record {|
    string name;
    EntityConfig entity = {};
    RawField[] fields;
    IndexConfig[] indexes = [];
|};

# Normalized source definition for a single model field.
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
public type SchemaGraph record {|
    map<ModelDefinition> models;
    RelationEdge[] relationEdges;
|};

# Parsed model definition.
public type ModelDefinition record {|
    string name;
    string tableName;
    string? schema;
    Engine engine;
    ColumnDefinition[] columns;
    map<ColumnDefinition> columnsByField;
    IndexDefinition[] indexes;
    RelationDefinition[] relations;
|};

# Parsed column definition.
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
public type IndexDefinition record {|
    string name;
    string[] columns;
    boolean unique;
|};

# Parsed relation definition from one model field.
public type RelationDefinition record {|
    string fieldName;
    string targetModel;
    RelationType relationType;
    string[] references;
    string[] foreignKey;
    string? joinTable;
|};

# Directed edge representation for relation graph traversal.
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
function schemaError(string code, string message, string? model = (), string? fieldName = ()) returns SchemaError {
    return error("SCHEMA_ERROR", code = code, message = message, model = model, fieldName = fieldName);
}

# Normalize a model name to a default snake_case plural table name.
function toDefaultTableName(string modelName) returns string {
    return string `${toSnakeCase(modelName)}s`;
}

# Convert a PascalCase or camelCase identifier to snake_case.
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
