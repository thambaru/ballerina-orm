import ballerina/test;
import ballerina/file;
import ballerina/io;

string testMigrationsDir = "/tmp/bal_orm_test_migrations";

// Recursively removes a directory and its contents using file:remove.
function removeDirRecursive(string dirPath) {
    file:MetaData[]|error entries = file:readDir(dirPath);
    if entries is file:MetaData[] {
        foreach file:MetaData entry in entries {
            if entry.dir {
                removeDirRecursive(entry.absPath);
            } else {
                file:Error? e = file:remove(entry.absPath);
                if e is file:Error {
                    // cleanup is best-effort, ignore
                }
            }
        }
    }
    file:Error? dirRemoveErr = file:remove(dirPath);
    if dirRemoveErr is file:Error {
        // cleanup is best-effort, ignore
    }
}

@test:BeforeSuite
function cleanupBeforeTests() {
    // Remove any leftover state from previous test runs
    removeDirRecursive(testMigrationsDir);
}

// ─── SQL Generation Tests ──────────────────────────────────────────────────

@test:Config {}
function testGenerateCreateTableMysqlNoColumns() {
    string sql = generateCreateTableSql("users", [], "MYSQL");
    test:assertEquals(sql, "CREATE TABLE `users` ();");
}

@test:Config {}
function testGenerateCreateTableMysqlWithColumns() {
    IntrospectedColumn[] cols = [
        {name: "id", 'type: "int", nullable: false, isPrimaryKey: true, isAutoIncrement: true},
        {name: "email", 'type: "varchar(255)", nullable: false},
        {name: "name", 'type: "varchar(255)", nullable: true}
    ];
    string sql = generateCreateTableSql("users", cols, "MYSQL");
    test:assertTrue(sql.startsWith("CREATE TABLE `users`"));
    test:assertTrue(sql.indexOf("`id` int NOT NULL AUTO_INCREMENT") is int);
    test:assertTrue(sql.indexOf("`email` varchar(255) NOT NULL") is int);
    test:assertTrue(sql.indexOf("`name` varchar(255)") is int);
    test:assertTrue(sql.indexOf("PRIMARY KEY (`id`)") is int);
}

@test:Config {}
function testGenerateCreateTablePostgresqlWithColumns() {
    IntrospectedColumn[] cols = [
        {name: "id", 'type: "int", nullable: false, isPrimaryKey: true, isAutoIncrement: true},
        {name: "title", 'type: "varchar(500)", nullable: false}
    ];
    string sql = generateCreateTableSql("posts", cols, "POSTGRESQL");
    test:assertTrue(sql.startsWith("CREATE TABLE \"posts\""));
    // PostgreSQL auto-increment becomes SERIAL
    test:assertTrue(sql.indexOf("SERIAL") is int);
    test:assertTrue(sql.indexOf("\"title\" varchar(500) NOT NULL") is int);
    test:assertTrue(sql.indexOf("PRIMARY KEY (\"id\")") is int);
}

@test:Config {}
function testGenerateDropTableSql() {
    string mysqlSql = generateDropTableSql("users", "MYSQL");
    test:assertEquals(mysqlSql, "DROP TABLE `users`;");

    string pgSql = generateDropTableSql("users", "POSTGRESQL");
    test:assertEquals(pgSql, "DROP TABLE \"users\";");
}

@test:Config {}
function testGenerateAlterAddColumnSql() {
    string sql = generateAlterAddColumnSql("users", "`status` varchar(50) NOT NULL", "MYSQL");
    test:assertEquals(sql, "ALTER TABLE `users` ADD COLUMN `status` varchar(50) NOT NULL;");
}

@test:Config {}
function testGenerateAlterDropColumnSql() {
    string mysqlSql = generateAlterDropColumnSql("users", "old_field", "MYSQL");
    test:assertEquals(mysqlSql, "ALTER TABLE `users` DROP COLUMN `old_field`;");

    string pgSql = generateAlterDropColumnSql("users", "old_field", "POSTGRESQL");
    test:assertEquals(pgSql, "ALTER TABLE \"users\" DROP COLUMN \"old_field\";");
}

@test:Config {}
function testGenerateModifyColumnSql() {
    string mysqlSql = generateAlterModifyColumnSql("users", "name", "`name` varchar(300) NOT NULL", "MYSQL");
    test:assertTrue(mysqlSql.indexOf("MODIFY COLUMN") is int);

    string pgSql = generateAlterModifyColumnSql("users", "name", "varchar(300) NOT NULL", "POSTGRESQL");
    test:assertTrue(pgSql.indexOf("ALTER COLUMN") is int);
    test:assertTrue(pgSql.indexOf("TYPE") is int);
}

@test:Config {}
function testGenerateCreateIndexSql() {
    string sql = generateCreateIndexSql("idx_email", "users", ["email"], true, "MYSQL");
    test:assertTrue(sql.indexOf("CREATE UNIQUE INDEX") is int);
    test:assertTrue(sql.indexOf("`idx_email`") is int);
    test:assertTrue(sql.indexOf("`users`") is int);
    test:assertTrue(sql.indexOf("`email`") is int);
}

@test:Config {}
function testGenerateDropIndexSqlMysql() {
    string sql = generateDropIndexSql("idx_old", "users", "MYSQL");
    test:assertTrue(sql.indexOf("ON `users`") is int);
}

@test:Config {}
function testGenerateDropIndexSqlPostgresql() {
    string sql = generateDropIndexSql("idx_old", "users", "POSTGRESQL");
    test:assertFalse(sql.indexOf(" ON ") is int);
    test:assertTrue(sql.indexOf("DROP INDEX") is int);
}

// ─── Schema Diff Tests ─────────────────────────────────────────────────────

@test:Config {}
function testDiffSchemasAddTable() {
    map<IntrospectedTable> desired = {
        "users": {
            name: "users",
            columns: [{name: "id", 'type: "int", nullable: false, isPrimaryKey: true}],
            indexes: [],
            foreignKeys: []
        }
    };
    map<IntrospectedTable> actual = {};
    SchemaDiff diff = diffSchemas(desired, actual, "MYSQL");
    test:assertEquals(diff.added.length(), 1);
    test:assertEquals(diff.added[0].itemType, "TABLE");
    test:assertEquals(diff.added[0].'table, "users");
    test:assertTrue(diff.added[0].tableDef is IntrospectedTable);
}

@test:Config {}
function testDiffSchemasRemoveTable() {
    map<IntrospectedTable> desired = {};
    map<IntrospectedTable> actual = {
        "old_table": {
            name: "old_table",
            columns: [],
            indexes: [],
            foreignKeys: []
        }
    };
    SchemaDiff diff = diffSchemas(desired, actual, "MYSQL");
    test:assertEquals(diff.removed.length(), 1);
    test:assertEquals(diff.removed[0].itemType, "TABLE");
    test:assertEquals(diff.removed[0].'table, "old_table");
}

@test:Config {}
function testDiffSchemasAddColumn() {
    IntrospectedTable usersDesired = {
        name: "users",
        columns: [
            {name: "id", 'type: "int", nullable: false, isPrimaryKey: true},
            {name: "email", 'type: "varchar(255)", nullable: false},
            {name: "status", 'type: "varchar(50)", nullable: true}  // new column
        ],
        indexes: [],
        foreignKeys: []
    };
    IntrospectedTable usersActual = {
        name: "users",
        columns: [
            {name: "id", 'type: "int", nullable: false, isPrimaryKey: true},
            {name: "email", 'type: "varchar(255)", nullable: false}
        ],
        indexes: [],
        foreignKeys: []
    };
    map<IntrospectedTable> desired = {"users": usersDesired};
    map<IntrospectedTable> actual = {"users": usersActual};
    SchemaDiff diff = diffSchemas(desired, actual, "MYSQL");
    test:assertEquals(diff.added.length(), 1);
    test:assertEquals(diff.added[0].itemType, "COLUMN");
    test:assertEquals(diff.added[0].column, "status");
}

@test:Config {}
function testDiffSchemasRemoveColumn() {
    IntrospectedTable usersDesired = {
        name: "users",
        columns: [
            {name: "id", 'type: "int", nullable: false, isPrimaryKey: true}
        ],
        indexes: [],
        foreignKeys: []
    };
    IntrospectedTable usersActual = {
        name: "users",
        columns: [
            {name: "id", 'type: "int", nullable: false, isPrimaryKey: true},
            {name: "old_field", 'type: "varchar(100)", nullable: true}
        ],
        indexes: [],
        foreignKeys: []
    };
    map<IntrospectedTable> desired = {"users": usersDesired};
    map<IntrospectedTable> actual = {"users": usersActual};
    SchemaDiff diff = diffSchemas(desired, actual, "MYSQL");
    test:assertEquals(diff.removed.length(), 1);
    test:assertEquals(diff.removed[0].itemType, "COLUMN");
    test:assertEquals(diff.removed[0].column, "old_field");
}

@test:Config {}
function testDiffSchemasModifyColumn() {
    IntrospectedTable usersDesired = {
        name: "users",
        columns: [
            {name: "id", 'type: "int", nullable: false, isPrimaryKey: true},
            {name: "name", 'type: "varchar(300)", nullable: false}  // was varchar(100)
        ],
        indexes: [],
        foreignKeys: []
    };
    IntrospectedTable usersActual = {
        name: "users",
        columns: [
            {name: "id", 'type: "int", nullable: false, isPrimaryKey: true},
            {name: "name", 'type: "varchar(100)", nullable: false}
        ],
        indexes: [],
        foreignKeys: []
    };
    map<IntrospectedTable> desired = {"users": usersDesired};
    map<IntrospectedTable> actual = {"users": usersActual};
    SchemaDiff diff = diffSchemas(desired, actual, "MYSQL");
    test:assertEquals(diff.modified.length(), 1);
    test:assertEquals(diff.modified[0].itemType, "COLUMN");
    test:assertEquals(diff.modified[0].column, "name");
    test:assertEquals(diff.modified[0].oldValue, "varchar(100)");
    test:assertEquals(diff.modified[0].newValue, "varchar(300)");
}

// ─── generateMigrationSql integration test ────────────────────────────────

@test:Config {}
function testGenerateMigrationSqlForNewTable() returns error? {
    IntrospectedTable newTable = {
        name: "categories",
        columns: [
            {name: "id", 'type: "int", nullable: false, isPrimaryKey: true, isAutoIncrement: true},
            {name: "name", 'type: "varchar(255)", nullable: false}
        ],
        indexes: [],
        foreignKeys: []
    };
    SchemaDiff diff = {
        added: [{itemType: "TABLE", 'table: "categories", description: "New table", tableDef: newTable}],
        modified: [],
        removed: []
    };
    string sql = check generateMigrationSql(diff, "MYSQL");
    test:assertTrue(sql.indexOf("CREATE TABLE `categories`") is int);
    test:assertTrue(sql.indexOf("`id` int NOT NULL AUTO_INCREMENT") is int);
}

// ─── Migration File I/O Tests ──────────────────────────────────────────────

@test:AfterSuite {}
function cleanupTestMigrationsDir() {
    // Clean up after all tests using our recursive helper
    removeDirRecursive(testMigrationsDir);
}

@test:Config {}
function testInitProject() returns error? {
    check initProject(testMigrationsDir);
    // Verify the migrations directory was created by reading it
    file:MetaData[]|error dirInfo = file:readDir(testMigrationsDir + "/migrations");
    test:assertFalse(dirInfo is error, "migrations directory should exist");
}

@test:Config {dependsOn: [testInitProject]}
function testCreateAndListMigrations() returns error? {
    string migrDir = testMigrationsDir + "/migrations";
    string sql = "CREATE TABLE `test_table` (`id` INT PRIMARY KEY);";

    Migration m = check createMigrationFile(migrDir, "create_test_table", sql);
    test:assertTrue(m.id.endsWith("_create_test_table"));
    test:assertEquals(m.sql, sql);

    Migration[] listed = check listMigrations(migrDir);
    test:assertEquals(listed.length(), 1);
    test:assertEquals(listed[0].sql, sql);
}

@test:Config {dependsOn: [testCreateAndListMigrations]}
function testRecordAndGetAppliedMigrations() returns error? {
    string migrDir = testMigrationsDir + "/migrations";
    Migration[] migrations = check listMigrations(migrDir);
    test:assertTrue(migrations.length() > 0);

    string migId = migrations[0].id;
    check recordMigrationApplied(migrDir, migId, migrations[0].name);

    Migration[] applied = check getAppliedMigrations(migrDir);
    test:assertEquals(applied.length(), 1);
    test:assertEquals(applied[0].id, migId);
}

@test:Config {dependsOn: [testRecordAndGetAppliedMigrations]}
function testCreateMigrationLock() returns error? {
    string migrDir = testMigrationsDir + "/migrations";
    Migration[] migrations = check listMigrations(migrDir);
    check createMigrationLock(migrDir, migrations);

    string lockPath = migrDir + "/migration_lock.toml";
    string|io:Error content = io:fileReadString(lockPath);
    test:assertTrue(content is string, "lock file should exist and be readable");
    if content is string {
        test:assertTrue(content.indexOf("applied") is int);
    }
}

@test:Config {}
function testMigrationIdFormat() returns error? {
    string migrDir = "/tmp/bal_orm_test_id_format_12345";
    check file:createDir(migrDir, file:RECURSIVE);
    Migration m = check createMigrationFile(migrDir, "test_migration", "SELECT 1;");
    test:assertTrue(m.id.length() > 14);  // at least YYYYMMDDHHMMSS_
    test:assertTrue(m.id.endsWith("_test_migration"));
}

