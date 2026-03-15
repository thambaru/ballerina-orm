# Annotation and metadata types used by the ORM schema system.

# Supported database providers.
public const MYSQL = "MYSQL";
public const POSTGRESQL = "POSTGRESQL";

# Database provider identifier.
public type Engine MYSQL|POSTGRESQL;

# Supported relation kinds.
public const ONE_TO_ONE = "ONE_TO_ONE";
public const ONE_TO_MANY = "ONE_TO_MANY";
public const MANY_TO_ONE = "MANY_TO_ONE";
public const MANY_TO_MANY = "MANY_TO_MANY";

# Relation type identifier.
public type RelationType ONE_TO_ONE|ONE_TO_MANY|MANY_TO_ONE|MANY_TO_MANY;

# Entity-level mapping settings.
#
# + tableName - Database table name. Defaults to the snake_case plural of the model name.
# + schema - Optional database schema name prefix.
# + engine - Force a specific database provider for this model.
public type EntityConfig record {|
    string tableName?;
    string schema?;
    Engine engine?;
|};

# Column-level mapping settings.
#
# + name - Column name override. Defaults to the snake_case of the field name.
# + type - Explicit database column type string.
# + length - Maximum character length for string columns.
# + nullable - Whether the column accepts NULL values.
# + unique - Whether a unique constraint is applied to this column.
# + default - Default value applied at the database level.
public type ColumnConfig record {|
    string name?;
    string 'type?;
    int length?;
    boolean nullable = true;
    boolean unique = false;
    anydata? 'default?;
|};

# Index settings for single or composite indexes.
#
# + name - Optional explicit index name. Auto-generated from columns if omitted.
# + columns - Field names that form the index.
# + unique - Whether the index enforces uniqueness.
public type IndexConfig record {|
    string name?;
    string[] columns;
    boolean unique = false;
|};

# Relation mapping settings.
#
# + type - Relation kind: ONE_TO_ONE, ONE_TO_MANY, MANY_TO_ONE, or MANY_TO_MANY.
# + model - Target model name. Inferred from the Ballerina field type when omitted.
# + references - Primary-key field names on the target model side.
# + foreignKey - Foreign-key field names on the owning model side.
# + joinTable - Join table name for MANY_TO_MANY relations.
public type RelationConfig record {|
    RelationType 'type?;
    string model?;
    string[] references?;
    string[] foreignKey?;
    string joinTable?;
|};

# Marker used for field-level no-payload annotations.
public type Marker record {||};

# Attach table-level metadata to a model record type.
public annotation EntityConfig Entity on type;

# Attach index metadata to a model record type.
# Declared as an array so `@Index { ... }` can be repeated multiple times.
public annotation IndexConfig[] Index on type;

# Mark a field as part of the primary key.
public annotation Marker Id on field;

# Mark a field as auto-incrementing.
public annotation Marker AutoIncrement on field;

# Override column-level properties for a field.
public annotation ColumnConfig Column on field;

# Attach relation metadata to a relation field.
public annotation RelationConfig Relation on field;

# Mark a field as ORM-managed creation timestamp.
public annotation Marker CreatedAt on field;

# Mark a field as ORM-managed update timestamp.
public annotation Marker UpdatedAt on field;

# Exclude a field from persistence mapping.
public annotation Marker Ignore on field;
