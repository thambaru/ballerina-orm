import ballerina/file;
import ballerina/io;
import ballerina/time;
import ballerina/os;

# Initializes a new ORM project with migrations directory and config.
public function initProject(string projectDir) returns MigrationError? {
    string migrationsDir = projectDir + "/migrations";
    
    # Create migrations directory
    error? result = file:createDir(migrationsDir, {recursive: true});
    if result is error {
        return error MigrationError({
            code: "INIT_FAILED",
            message: "Failed to create migrations directory: " + result.message()
        });
    }
    
    # Create .ormrc.json config (placeholder)
    string configPath = projectDir + "/.ormrc.json";
    string configContent = string `{
  "migrationsDir": "migrations",
  "schemaPath": ".",
  "provider": "MYSQL"
}`;
    
    result = file:writeString(configPath, configContent);
    if result is error {
        return error MigrationError({
            code: "CONFIG_CREATE_FAILED",
            message: "Failed to create config file: " + result.message()
        });
    }
    
    io:println("✓ Initialized ORM project");
    io:println("  - Created migrations directory");
    io:println("  - Created .ormrc.json config");
    
    return ();
}

# Generates a new migration file with the given SQL.
public function createMigrationFile(
    string migrationsDir,
    string name,
    string sql
) returns Migration|MigrationError {
    # Generate migration ID (timestamp)
    time:Utc now = time:utcNow();
    int timestamp = <int>(now.seconds * 1000000 + now.nanos / 1000);
    string id = timestamp.toString();
    
    # Create migration directory
    string migrationDir = migrationsDir + "/" + id + "_" + name;
    error? result = file:createDir(migrationDir, {recursive: true});
    
    if result is error {
        return error MigrationError({
            code: "MIGRATION_DIR_CREATE_FAILED",
            message: "Failed to create migration directory: " + result.message()
        });
    }
    
    # Write migration.sql
    string sqlFilePath = migrationDir + "/migration.sql";
    result = file:writeString(sqlFilePath, sql);
    
    if result is error {
        return error MigrationError({
            code: "MIGRATION_FILE_CREATE_FAILED",
            message: "Failed to write migration file: " + result.message()
        });
    }
    
    return {
        id,
        name,
        path: migrationDir,
        sql
    };
}

# Lists all migrations in a directory.
public function listMigrations(string migrationsDir) returns Migration[]|MigrationError {
    Migration[] migrations = [];
    
    # Read migrations directory
    string[]|error files = file:readDir(migrationsDir);
    
    if files is error {
        return error MigrationError({
            code: "READ_MIGRATIONS_FAILED",
            message: "Failed to read migrations directory: " + files.message()
        });
    }
    
    foreach var filePath in files {
        # Parse migration ID from directory name
        string fileName = file:getPathInfo(filePath).name;
        
        if fileName.includes("_") {
            # Expected format: {timestamp}_{name}
            string[] parts = fileName.split("_", 1);
            
            if parts.length() >= 1 {
                string id = parts[0];
                string name = parts.length() > 1 ? parts[1] : "unknown";
                
                # Try to read migration.sql
                string sqlPath = filePath + "/migration.sql";
                string|error sqlContent = file:readString(sqlPath);
                
                if sqlContent is string {
                    migrations.push({
                        id,
                        name,
                        path: filePath,
                        sql: sqlContent
                    });
                }
            }
        }
    }
    
    return migrations;
}

# Gets the next migration ID (for ordering).
public function getNextMigrationId(Migration[] migrations) returns string {
    if migrations.length() == 0 {
        return "1";
    }
    
    # Sort by ID (numeric)
    int lastId = 0;
    foreach var migration in migrations {
        int|error id = int:fromString(migration.id);
        if id is int && id > lastId {
            lastId = id;
        }
    }
    
    return (lastId + 1).toString();
}

# Creates a migration lock file to track applied migrations.
public function createMigrationLock(
    string migrationsDir,
    Migration[] appliedMigrations
) returns MigrationError? {
    string lockPath = migrationsDir + "/migration_lock.toml";
    string content = "# Migration lock file - auto-generated\n\n";
    
    foreach var migration in appliedMigrations {
        content = content + string `[[migrations]]
id = "${migration.id}"
name = "${migration.name}"
applied_at = "${time:utcNow()}"

`;
    }
    
    error? result = file:writeString(lockPath, content);
    
    if result is error {
        return error MigrationError({
            code: "LOCK_FILE_CREATE_FAILED",
            message: "Failed to create migration lock file: " + result.message()
        });
    }
    
    return ();
}

# Reads applied migrations from the database _orm_migrations table.
public function getAppliedMigrations(
    anydata dbClient
) returns Migration[]|MigrationError {
    # This will be implemented to query _orm_migrations table
    # For now, return empty list
    return [];
}

# Records a migration as applied in the _orm_migrations table.
public function recordMigrationApplied(
    anydata dbClient,
    string migrationId,
    string migrationName
) returns MigrationError? {
    # This will be implemented to insert into _orm_migrations table
    # For now, just return success
    return ();
}
