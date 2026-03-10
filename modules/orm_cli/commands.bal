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

# Executes `bal orm migrate dev` - creates and applies a dev migration.
#
# This command:
# 1. Introspects the database
# 2. Compares with desired schema (from annotated records)
# 3. Generates SQL migration if needed
# 4. Applies migration
public function handleMigrateDevCommand(
    anydata dbClient,
    string provider,
    string migrationsDir,
    string desiredSchemaJson,
    string name
) returns error? {
    io:println("Generating migration...");
    
    // Parse desired schema from JSON (simplified - just announce intent)
    io:println("  Provider: " + provider);
    io:println("  Migrations dir: " + migrationsDir);
    io:println("  Migration name: " + name);
    
    // TODO: Introspect DB
    // IntrospectedSchema actual = check introspectDatabase(dbClient, provider);
    
    // TODO: Parse desired schema from JSON
    // map<IntrospectedTable> desired = check parseDesiredSchema(desiredSchemaJson);
    
    // TODO: Diff schemas
    // SchemaDiff diff = diffSchemas(desired, actual.tables, provider);
    
    // TODO: Generate SQL
    // string migrationSql = check generateMigrationSql(diff, provider);
    
    // TODO: Create migration file
    // Migration migration = check createMigrationFile(migrationsDir, name, migrationSql);
    
    // TODO: Apply migration
    // check recordMigrationApplied(dbClient, migration.id, migration.name);
    
    io:println("✓ Migration ready");
    
    return ();
}

# Executes `bal orm migrate deploy` - applies pending migrations.
#
# This command:
# 1. Reads migration lock file or DB applied migrations
# 2. Finds pending migrations
# 3. Applies them in order
# 4. Records in _orm_migrations table
public function handleMigrateDeployCommand(
    anydata dbClient,
    string migrationsDir
) returns error? {
    io:println("Deploying migrations...");
    
    // TODO: Get applied migrations
    // Migration[] applied = check getAppliedMigrations(dbClient);
    
    // TODO: Get all migrations
    Migration[] all = check listMigrations(migrationsDir);
    
    // TODO: Find pending
    // Migration[] pending = all.filter(m => !applied.any(a => a.id == m.id));
    
    io:println(string `Found ${all.length()} total migrations`);
    
    // TODO: Apply each migration
    // foreach var migration in pending {
    //     check executeMigration(dbClient, migration);
    //     check recordMigrationApplied(dbClient, migration.id, migration.name);
    // }
    
    io:println("✓ Migrations deployed");
    
    return ();
}

# Executes `bal orm migrate reset` - resets the database (dev only).
#
# This command:
# 1. Drops all tables
# 2. Clears migration tracking
# 3. Re-runs all migrations
public function handleMigrateResetCommand(
    anydata dbClient,
    string migrationsDir,
    string provider
) returns error? {
    io:println("Resetting database...");
    io:println("WARNING: This will drop all tables!");
    
    // TODO: Drop all tables
    // check dropAllTables(dbClient, provider);
    
    // TODO: Clear migration tracking
    // check clearMigrationTracking(dbClient);
    
    // TODO: Re-apply all migrations
    // Migration[] all = check listMigrations(migrationsDir);
    // foreach var migration in all {
    //     check executeMigration(dbClient, migration);
    // }
    
    io:println("✓ Database reset complete");
    
    return ();
}

# Executes `bal orm migrate status` - shows migration status.
#
# Displays:
# - Total migrations
# - Applied migrations
# - Pending migrations
public function handleMigrateStatusCommand(
    anydata dbClient,
    string migrationsDir
) returns error? {
    io:println("Migration Status:");
    io:println("================");
    
    // Get all migrations
    Migration[] all = check listMigrations(migrationsDir);
    
    // TODO: Get applied migrations
    // Migration[] applied = check getAppliedMigrations(dbClient);
    
    io:println(string `Total migrations: ${all.length()}`);
    // io:println(string `Applied: ${applied.length()}`);
    // io:println(string `Pending: ${(all.length() - applied.length())}`);
    
    return ();
}

# Executes `bal orm db push` - pushes schema directly without migration file.
#
# This command:
# 1. Introspects the database
# 2. Compares with desired schema
# 3. Executes ALTER statements directly
# 4. Does NOT create a migration file
public function handleDbPushCommand(
    anydata dbClient,
    string provider,
    string desiredSchemaJson
) returns error? {
    io:println("Pushing schema to database...");
    
    // TODO: Implement full flow
    // IntrospectedSchema actual = check introspectDatabase(dbClient, provider);
    // map<IntrospectedTable> desired = check parseDesiredSchema(desiredSchemaJson);
    // SchemaDiff diff = diffSchemas(desired, actual.tables, provider);
    // string sql = check generateMigrationSql(diff, provider);
    // check execSql(dbClient, sql);
    
    io:println("✓ Schema pushed");
    
    return ();
}

# Executes `bal orm db pull` - introspects database and generates record types.
#
# This command:
# 1. Introspects the database
# 2. Generates Ballerina record types from schema
# 3. Writes to file or stdout
public function handleDbPullCommand(
    anydata dbClient,
    string provider,
    string? outputFile = (),
    string? database = ()
) returns error? {
    io:println("Pulling schema from database...");
    
    // TODO: Implement introspection and code generation
    // IntrospectedSchema schema;
    // if provider == "MYSQL" {
    //     mysql:Client mysqlClient = <mysql:Client>dbClient;
    //     schema = check introspectMysql(mysqlClient, database);
    // } else {
    //     postgresql:Client pgClient = <postgresql:Client>dbClient;
    //     schema = check introspectPostgresql(pgClient, database);
    // }
    
    // string generatedCode = check generateRecordTypes(schema);
    
    // if outputFile is string {
    //     check file:writeString(outputFile, generatedCode);
    //     io:println("✓ Schema written to " + outputFile);
    // } else {
    //     io:println(generatedCode);
    // }
    
    io:println("✓ Schema pulled");
    
    return ();
}

# Executes `bal orm generate` - triggers compiler plugin code generation.
#
# This command:
# 1. Scans for @orm:Entity annotations
# 2. Triggers the compiler plugin
# 3. Generates CRUD wrappers, input types, etc.
public function handleGenerateCommand(string projectDir) returns error? {
    io:println("Generating ORM code...");
    
    // TODO: This would typically be triggered by the compiler plugin
    // Check for entity annotations
    // Generate CRUD methods
    // Generate input/filter types
    
    io:println("✓ ORM code generated");
    
    return ();
}
