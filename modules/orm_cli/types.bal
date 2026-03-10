import ballerina/time;

# Migration status type.
public type MigrationStatus "PENDING" | "APPLIED";

# Represents a single migration file.
public type Migration record {|
    string id;
    string name;
    string path;
    string sql;
    time:Utc? appliedAt = ();
|};

# Configuration for the ORM CLI.
public type CliConfig record {|
    string migrationsDir = "migrations";
    string schemaPath = ".";
    string? configPath = ();
|};

# Introspected database schema.
public type IntrospectedSchema record {|
    map<IntrospectedTable> tables;
    string provider;
|};

# Introspected table schema.
public type IntrospectedTable record {|
    string name;
    string? schema = ();
    IntrospectedColumn[] columns;
    IntrospectedIndex[] indexes;
    IntrospectedForeignKey[] foreignKeys;
|};

# Introspected column schema.
public type IntrospectedColumn record {|
    string name;
    string type;
    boolean nullable;
    boolean isPrimaryKey = false;
    boolean isUnique = false;
    boolean isAutoIncrement = false;
    string? defaultValue = ();
|};

# Introspected index schema.
public type IntrospectedIndex record {|
    string name;
    string[] columns;
    boolean unique;
|};

# Introspected foreign key schema.
public type IntrospectedForeignKey record {|
    string name;
    string column;
    string referencedTable;
    string referencedColumn;
    string? onDelete = ();
    string? onUpdate = ();
|};

# Represents a schema difference.
public type SchemaDiff record {|
    SchemaDiffItem[] added = [];
    SchemaDiffItem[] modified = [];
    SchemaDiffItem[] removed = [];
|};

# Represents a single schema difference item.
public type SchemaDiffItem record {|
    string itemType; # "TABLE", "COLUMN", "INDEX", "CONSTRAINT"
    string table;
    string? column = ();
    string? oldValue = ();
    string? newValue = ();
    string description;
|};

# Migration action details.
public type MigrationAction record {|
    string type; # "CREATE_TABLE", "ALTER_TABLE", "DROP_TABLE", "CREATE_INDEX", "DROP_INDEX"
    string table;
    string? column = ();
    string? definition = ();
|};

# Error detail payload for migration operations.
public type MigrationIssue record {|
    string code;
    string message;
|};

# Error type used by the CLI subsystem.
public type MigrationError error<MigrationIssue>;
