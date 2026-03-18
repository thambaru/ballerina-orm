import ballerina/io;

# Main CLI handler for ORM migration commands.

public type MigrateDevOptions record {|
    boolean create = false;
    string name = "";
|};

public type MigrateDeployOptions record {|
    string? env = ();
|};

public type DbPullOptions record {|
    string? output = ();
|};

# Executes `bal orm init` - initializes project structure.
public function handleInitCommand(string projectDir) returns error? {
    io:println("Initializing ORM project...");
    return initProject(projectDir);
}

# Executes `bal orm migrate dev` - introspects DB, diffs against desired schema,
# creates a migration file, and records it.
public function handleMigrateDevCommand(
    CliDbClient dbClient,
    string provider,
    string migrationsDir,
    map<IntrospectedTable> desiredTables,
    string name
) returns error? {
    io:println("Generating migration: " + name);

    // Introspect the current database schema
    IntrospectedSchema actualSchema;
    if provider == "MYSQL" {
        actualSchema = check introspectMysql(dbClient);
    } else {
        actualSchema = check introspectPostgresql(dbClient);
    }

    // Diff desired vs actual
    SchemaDiff diff = diffSchemas(desiredTables, actualSchema.tables, provider);

    // Generate migration SQL
    string migrationSql = check generateMigrationSql(diff, provider);

    if migrationSql.trim() == "" {
        io:println("No schema changes detected.");
        return ();
    }

    // Create migration file
    Migration migration = check createMigrationFile(migrationsDir, name, migrationSql);
    io:println("Created migration: " + migration.path);

    // Apply migration against DB
    if provider == "MYSQL" {
        check executeMigrationOnMysql(dbClient, migrationSql);
        check recordMigrationAppliedMysql(dbClient, migration.id, migration.name);
    } else {
        check executeMigrationOnPostgresql(dbClient, migrationSql);
        check recordMigrationAppliedPostgresql(dbClient, migration.id, migration.name);
    }

    // Also record in the file-based lock
    check recordMigrationApplied(migrationsDir, migration.id, migration.name);

    io:println("Migration applied: " + migration.id);
    return ();
}

# Executes `bal orm migrate deploy` - applies pending migrations.
public function handleMigrateDeployCommand(
    CliDbClient dbClient,
    string provider,
    string migrationsDir
) returns error? {
    io:println("Deploying migrations...");

    Migration[] all = check listMigrations(migrationsDir);
    Migration[] applied = check getAppliedMigrations(migrationsDir);

    // Build set of applied migration IDs
    map<boolean> appliedIds = {};
    foreach Migration m in applied {
        appliedIds[m.id] = true;
    }

    // Find pending migrations
    Migration[] pending = [];
    foreach Migration m in all {
        if !appliedIds.hasKey(m.id) {
            pending.push(m);
        }
    }

    io:println(string `Total: ${all.length()}, Applied: ${applied.length()}, Pending: ${pending.length()}`);

    foreach Migration migration in pending {
        io:println("Applying migration: " + migration.id);
        if provider == "MYSQL" {
            check executeMigrationOnMysql(dbClient, migration.sql);
            check recordMigrationAppliedMysql(dbClient, migration.id, migration.name);
        } else {
            check executeMigrationOnPostgresql(dbClient, migration.sql);
            check recordMigrationAppliedPostgresql(dbClient, migration.id, migration.name);
        }
        check recordMigrationApplied(migrationsDir, migration.id, migration.name);
        io:println("Applied: " + migration.id);
    }

    io:println("Migrations deployed.");
    return ();
}

# Executes `bal orm migrate reset` - resets the database (dev only).
public function handleMigrateResetCommand(
    CliDbClient dbClient,
    string provider,
    string migrationsDir
) returns error? {
    io:println("Resetting database...");
    io:println("WARNING: This will drop and re-apply all migrations!");

    // Drop all user tables first by introspecting the current schema
    IntrospectedSchema currentSchema;
    if provider == "MYSQL" {
        currentSchema = check introspectMysql(dbClient);
    } else {
        currentSchema = check introspectPostgresql(dbClient);
    }

    foreach string tableName in currentSchema.tables.keys() {
        if tableName == "_orm_migrations" {
            continue;
        }
        string dropSql = generateDropTableSql(tableName, provider);
        if provider == "MYSQL" {
            check executeMigrationOnMysql(dbClient, dropSql);
        } else {
            check executeMigrationOnPostgresql(dbClient, dropSql);
        }
    }

    // Drop the migrations tracking table itself
    string dropTrackingSql = generateDropTableSql("_orm_migrations", provider);
    if provider == "MYSQL" {
        check executeMigrationOnMysql(dbClient, dropTrackingSql);
    } else {
        check executeMigrationOnPostgresql(dbClient, dropTrackingSql);
    }

    // Re-apply all migrations from scratch
    Migration[] all = check listMigrations(migrationsDir);

    foreach Migration migration in all {
        io:println("Re-applying: " + migration.id);
        if provider == "MYSQL" {
            check executeMigrationOnMysql(dbClient, migration.sql);
            check recordMigrationAppliedMysql(dbClient, migration.id, migration.name);
        } else {
            check executeMigrationOnPostgresql(dbClient, migration.sql);
            check recordMigrationAppliedPostgresql(dbClient, migration.id, migration.name);
        }
    }

    // Reset lock to all migrations applied
    check createMigrationLock(migrationsDir, all);
    io:println("Database reset complete.");
    return ();
}

# Executes `bal orm migrate status` - shows migration status (file-based).
public function handleMigrateStatusCommand(string migrationsDir) returns error? {
    io:println("Migration Status:");
    io:println("================");

    Migration[] all = check listMigrations(migrationsDir);
    Migration[] applied = check getAppliedMigrations(migrationsDir);

    map<boolean> appliedIds = {};
    foreach Migration m in applied {
        appliedIds[m.id] = true;
    }

    io:println(string `Total migrations: ${all.length()}`);
    io:println(string `Applied: ${applied.length()}`);
    io:println(string `Pending: ${all.length() - applied.length()}`);

    if all.length() > 0 {
        io:println("");
        foreach Migration m in all {
            string status = appliedIds.hasKey(m.id) ? "[applied]" : "[pending]";
            io:println(status + " " + m.id);
        }
    }

    return ();
}

# Executes `bal orm db push` - pushes desired schema directly to the database.
public function handleDbPushCommand(
    CliDbClient dbClient,
    string provider,
    map<IntrospectedTable> desiredTables
) returns error? {
    io:println("Pushing schema to database...");

    IntrospectedSchema actualSchema;
    if provider == "MYSQL" {
        actualSchema = check introspectMysql(dbClient);
    } else {
        actualSchema = check introspectPostgresql(dbClient);
    }

    SchemaDiff diff = diffSchemas(desiredTables, actualSchema.tables, provider);
    string sql = check generateMigrationSql(diff, provider);

    if sql.trim() == "" {
        io:println("Schema is already up to date.");
        return ();
    }

    if provider == "MYSQL" {
        check executeMigrationOnMysql(dbClient, sql);
    } else {
        check executeMigrationOnPostgresql(dbClient, sql);
    }

    io:println("Schema pushed.");
    return ();
}

# Executes `bal orm db pull` - introspects database and prints schema.
public function handleDbPullCommand(
    CliDbClient dbClient,
    string provider,
    string? outputFile = (),
    string? database = ()
) returns error? {
    io:println("Pulling schema from database...");

    IntrospectedSchema schema;
    if provider == "MYSQL" {
        schema = check introspectMysql(dbClient, database);
    } else {
        schema = check introspectPostgresql(dbClient, database);
    }

    string generated = generateRecordTypes(schema);

    if outputFile is string {
        io:Error? writeErr = io:fileWriteString(<string>outputFile, generated);
        if writeErr is io:Error {
            return writeErr;
        }
        io:println("Schema written to " + <string>outputFile);
    } else {
        io:println(generated);
    }

    return ();
}

# Executes `bal orm generate` - triggers compiler plugin code generation.
public function handleGenerateCommand(string projectDir) returns error? {
    _ = projectDir;
    io:println("Run `bal build` to trigger the ORM compiler plugin code generation.");
    return ();
}

# Generates Ballerina record type stubs from an introspected schema.
function generateRecordTypes(IntrospectedSchema schema) returns string {
    string output = "import ballerina/time;\nimport thambaru/bal_orm.orm;\n\n";
    foreach string tableName in schema.tables.keys() {
        IntrospectedTable tbl = schema.tables.get(tableName);
        output = output + "@orm:Entity {tableName: \"" + tbl.name + "\"}\n";
        output = output + "public type " + toPascalCaseCli(tbl.name) + " record {|\n";
        foreach IntrospectedColumn col in tbl.columns {
            string balType = dbTypeToBallerina(col.'type);
            string optional = col.nullable ? "?" : "";
            string annotations = "";
            if col.isPrimaryKey {
                annotations = "@orm:Id ";
            }
            if col.isAutoIncrement {
                annotations = annotations + "@orm:AutoIncrement ";
            }
            if annotations != "" {
                output = output + "    " + annotations + "\n";
            }
            output = output + "    " + balType + optional + " " + col.name + ";\n";
        }
        output = output + "|};\n\n";
    }
    return output;
}

function toPascalCaseCli(string name) returns string {
    if name.length() == 0 { return name; }
    string first = name.substring(0, 1).toUpperAscii();
    if name.length() == 1 { return first; }
    return first + name.substring(1);
}

function dbTypeToBallerina(string dbType) returns string {
    string t = dbType.toLowerAscii();
    if t == "int" || t == "integer" || t == "smallint" || t.indexOf("int(") is int { return "int"; }
    if t == "bigint" { return "int"; }
    if t == "float" || t == "real" || t == "double" || t == "double precision" { return "float"; }
    if t == "decimal" || t == "numeric" || t.indexOf("decimal(") is int || t.indexOf("numeric(") is int { return "decimal"; }
    if t == "boolean" || t == "tinyint(1)" { return "boolean"; }
    if t == "text" || t.indexOf("varchar") is int || t.indexOf("char(") is int { return "string"; }
    if t == "datetime" || t == "timestamp" || t == "timestamptz" || t == "date" || t == "time" { return "time:Utc"; }
    if t == "json" || t == "jsonb" { return "json"; }
    return "string";
}

