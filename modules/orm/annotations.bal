# Annotation and metadata types used by the ORM schema system.

# Supported database providers.
public const MYSQL = "MYSQL";
public const POSTGRESQL = "POSTGRESQL";

# Database provider identifier.
public type Engine MYSQL|POSTGRESQL;

# Supported relation kinds.
public const ONE_TO_ONE = "ONE_TO_ONE";
public const ONE_TO_MANY = "ONE_TO_MANY";
public const MANY_TO_MANY = "MANY_TO_MANY";

# Relation type identifier.
public type RelationType ONE_TO_ONE|ONE_TO_MANY|MANY_TO_MANY;

# Entity-level mapping settings.
public type EntityConfig record {|
    string tableName?;
    string schema?;
    Engine engine?;
|};

# Column-level mapping settings.
public type ColumnConfig record {|
    string name?;
    string dbType?;
    int length?;
    boolean nullable = true;
    boolean unique = false;
    anydata? 'default?;
|};

# Index settings for single or composite indexes.
public type IndexConfig record {|
    string name?;
    string[] columns;
    boolean unique = false;
|};

# Relation mapping settings.
public type RelationConfig record {|
    RelationType 'type?;
    RelationType relationType?;
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
