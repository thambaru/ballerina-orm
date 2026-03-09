import ballerina/io;
import ballerinax/mysql;
import bal_orm.orm as orm;
import bal_orm.orm_cli as cli;

# Example demonstrating Phase 5 migration engine integration
#
# This example shows:
# 1. Database introspection
# 2. Schema comparison
# 3. Migration generation
# 4. Migration application (simulated)

public function main() returns error? {
    io:println("=== Ballerina ORM Migration Engine Demo ===\n");
    
    # Step 1: Connect to database
    io:println("Step 1: Connecting to database...");
    mysql:Client dbClient = check new (
        "localhost",
        "root",
        "password",
        "test_orm_db",
        3306
    );
    io:println("✓ Connected to MySQL\n");
    
    # Step 2: Introspect current database schema
    io:println("Step 2: Introspecting database...");
    cli:IntrospectedSchema currentSchema = check cli:introspectMysql(dbClient, "test_orm_db");
    io:println(string `✓ Found ${currentSchema.tables.length()} tables\n`);
    
    # Step 3: Define desired schema (would come from @orm:Entity annotations)
    io:println("Step 3: Building desired schema...");
    cli:IntrospectedTable usersTable = {
        name: "users",
        schema: "test_orm_db",
        columns: [
            {
                name: "id",
                type: "INT",
                nullable: false,
                isPrimaryKey: true,
                isAutoIncrement: true,
                isUnique: false
            },
            {
                name: "email",
                type: "VARCHAR",
                nullable: false,
                isPrimaryKey: false,
                isAutoIncrement: false,
                isUnique: true
            },
            {
                name: "name",
                type: "VARCHAR",
                nullable: false,
                isPrimaryKey: false,
                isAutoIncrement: false,
                isUnique: false
            },
            {
                name: "created_at",
                type: "TIMESTAMP",
                nullable: false,
                isPrimaryKey: false,
                isAutoIncrement: false,
                isUnique: false
            }
        ],
        indexes: [
            {
                name: "idx_email",
                columns: ["email"],
                unique: true
            }
        ],
        foreignKeys: []
    };
    
    map<cli:IntrospectedTable> desiredTables = {"users": usersTable};
    io:println("✓ Desired schema defined\n");
    
    # Step 4: Compare schemas and detect differences
    io:println("Step 4: Comparing schemas...");
    cli:SchemaDiff diff = cli:diffSchemas(desiredTables, currentSchema.tables, "MYSQL");
    io:println(string `  Added: ${diff.added.length()} items`);
    io:println(string `  Modified: ${diff.modified.length()} items`);
    io:println(string `  Removed: ${diff.removed.length()} items\n`);
    
    # Print diff details
    if diff.added.length() > 0 {
        io:println("Changes to apply:");
        foreach var item in diff.added {
            io:println(string `  + ${item.description}`);
        }
        io:println("");
    }
    
    # Step 5: Generate SQL migration
    io:println("Step 5: Generating migration SQL...");
    string migrationSql = check cli:generateMigrationSql(diff, "MYSQL");
    io:println("✓ SQL generated:\n");
    io:println("--- migration.sql ---");
    io:println(migrationSql);
    io:println("---\n");
    
    # Step 6: Create migration file
    io:println("Step 6: Creating migration file...");
    cli:Migration migration = check cli:createMigrationFile(
        "migrations",
        "add_users_table",
        migrationSql
    );
    io:println(string `✓ Created migration: ${migration.id}_${migration.name}`);
    io:println(string `  Path: ${migration.path}\n`);
    
    # Step 7: List all migrations
    io:println("Step 7: Listing migrations...");
    cli:Migration[] migrations = check cli:listMigrations("migrations");
    io:println(string `✓ Total migrations: ${migrations.length()}`);
    foreach var m in migrations {
        io:println(string `  - ${m.id}_${m.name}`);
    }
    io:println("");
    
    # Cleanup
    check dbClient.close();
    io:println("=== Demo Complete ===");
}
