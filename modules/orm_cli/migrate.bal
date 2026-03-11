import ballerina/file;
import ballerina/io;
import ballerina/time;

# Initializes a new ORM project structure by creating the migrations directory
# and writing an `.ormrc.json` config template if one does not already exist.
public function initProject(string projectDir) returns MigrationError? {
    string migrationsDir = projectDir + "/migrations";
    file:Error? result = file:createDir(migrationsDir, file:RECURSIVE);
    if result is file:Error {
        return error MigrationError("INIT_FAILED", code = "INIT_FAILED", message = "Failed to create migrations directory: " + result.message());
    }
    io:println("Created migrations directory: " + migrationsDir);

    // Write initial migration_lock.toml (overwrite if exists)
    string lockPath = migrationsDir + "/migration_lock.toml";
    string|io:Error existing = io:fileReadString(lockPath);
    if existing is io:Error {
        // File does not exist yet — create it
        io:Error? writeErr = io:fileWriteString(lockPath, "# ORM migration lock file\n# Do not edit manually\napplied = []\n");
        if writeErr is io:Error {
            return error MigrationError("INIT_FAILED", code = "INIT_FAILED", message = "Failed to create migration lock: " + writeErr.message());
        }
    }

    // Write .ormrc.json template if it does not exist yet
    string ormrcPath = projectDir + "/.ormrc.json";
    string|io:Error ormrcExisting = io:fileReadString(ormrcPath);
    if ormrcExisting is io:Error {
        string template = "{\n" +
            "  \"provider\": \"MYSQL\",\n" +
            "  \"host\":     \"localhost\",\n" +
            "  \"port\":     3306,\n" +
            "  \"user\":     \"root\",\n" +
            "  \"password\": \"\",\n" +
            "  \"database\": \"myapp\"\n" +
            "}\n";
        io:Error? writeErr = io:fileWriteString(ormrcPath, template);
        if writeErr is io:Error {
            return error MigrationError("INIT_FAILED", code = "INIT_FAILED", message = "Failed to create .ormrc.json: " + writeErr.message());
        }
        io:println("Created .ormrc.json — fill in your database credentials.");
    }

    io:println("Initialized ORM project.");
    return ();
}

# Creates a migration file on disk under migrationsDir/{id}/migration.sql
public function createMigrationFile(
    string migrationsDir,
    string name,
    string sql
) returns Migration|MigrationError {
    string migrationName = name == "" ? "migration" : name;
    string id = generateMigrationTimestamp() + "_" + migrationName;
    string migrationDir = migrationsDir + "/" + id;

    file:Error? mkdirErr = file:createDir(migrationDir, file:RECURSIVE);
    if mkdirErr is file:Error {
        return error MigrationError("CREATE_MIGRATION_FAILED", code = "CREATE_MIGRATION_FAILED",
            message = "Failed to create migration directory: " + mkdirErr.message());
    }

    string filePath = migrationDir + "/migration.sql";
    io:Error? writeErr = io:fileWriteString(filePath, sql);
    if writeErr is io:Error {
        return error MigrationError("CREATE_MIGRATION_FAILED", code = "CREATE_MIGRATION_FAILED",
            message = "Failed to write migration SQL: " + writeErr.message());
    }

    return {id, name: migrationName, path: filePath, sql};
}

# Lists all migrations from the migrations directory, sorted by ID (chronological).
public function listMigrations(string migrationsDir) returns Migration[]|MigrationError {
    file:MetaData[]|error entries = file:readDir(migrationsDir);
    if entries is error {
        return [];  // Directory may not exist yet
    }

    // Collect migration directory names (exclude migration_lock.toml and files)
    string[] migDirNames = [];
    foreach file:MetaData entry in entries {
        // Extract the entry name from absPath (MetaData has no 'name' field)
        string absPath = entry.absPath;
        int? lastSlash = absPath.lastIndexOf("/");
        string entryName = lastSlash is int ? absPath.substring(lastSlash + 1) : absPath;
        if entry.dir && entryName != "." && entryName != ".." {
            migDirNames.push(entryName);
        }
    }

    // Sort lexicographically (timestamp prefix ensures chronological order)
    string[] sortedNames = from string n in migDirNames order by n ascending select n;

    Migration[] migrations = [];
    foreach string dirName in sortedNames {
        string sqlPath = migrationsDir + "/" + dirName + "/migration.sql";
        string|io:Error sqlContent = io:fileReadString(sqlPath);
        if sqlContent is io:Error {
            continue;
        }

        // Parse id and name from directory name: "YYYYMMDDHHMMSS_name"
        string id = dirName;
        string migName = dirName;
        int? underscoreIdx = dirName.indexOf("_");
        if underscoreIdx is int {
            migName = dirName.substring(underscoreIdx + 1);
        }

        migrations.push({
            id,
            name: migName,
            path: sqlPath,
            sql: sqlContent
        });
    }

    return migrations;
}

# Gets the next migration ID from an existing list.
public function getNextMigrationId(Migration[] migrations) returns string {
    return generateMigrationTimestamp();
}

# Writes migration lock state to migration_lock.toml (file-based tracking).
public function createMigrationLock(
    string migrationsDir,
    Migration[] appliedMigrations
) returns MigrationError? {
    string lockPath = migrationsDir + "/migration_lock.toml";
    string content = "# ORM migration lock file\n# Do not edit manually\napplied = [";
    if appliedMigrations.length() > 0 {
        content = content + "\n";
        foreach Migration m in appliedMigrations {
            content = content + "  \"" + m.id + "\",\n";
        }
    }
    content = content + "]\n";

    io:Error? writeErr = io:fileWriteString(lockPath, content);
    if writeErr is io:Error {
        return error MigrationError("LOCK_WRITE_FAILED", code = "LOCK_WRITE_FAILED",
            message = "Failed to write migration lock: " + writeErr.message());
    }
    return ();
}

# Reads applied migration IDs from migration_lock.toml.
public function getAppliedMigrations(string migrationsDir) returns Migration[]|MigrationError {
    string lockPath = migrationsDir + "/migration_lock.toml";
    string|io:Error content = io:fileReadString(lockPath);
    if content is io:Error {
        return [];  // Lock file may not exist yet
    }

    // Parse the applied = [...] list from TOML manually
    string fileContent = content;
    int? arrStart = fileContent.indexOf("[", 0);
    int? arrEnd = fileContent.indexOf("]", 0);
    if arrStart is () || arrEnd is () {
        return [];
    }

    int startPos = arrStart;
    int endPos = arrEnd;
    if endPos <= startPos {
        return [];
    }

    string inner = fileContent.substring(startPos + 1, endPos).trim();
    if inner == "" {
        return [];
    }

    Migration[] applied = [];
    int cursor = 0;
    while cursor < inner.length() {
        int? quoteStart = inner.indexOf("\"", cursor);
        if quoteStart is () { break; }
        int? quoteEnd = inner.indexOf("\"", quoteStart + 1);
        if quoteEnd is () { break; }
        string migId = inner.substring(quoteStart + 1, quoteEnd);
        if migId != "" {
            string migName = migId;
            int? underscoreIdx = migId.indexOf("_");
            if underscoreIdx is int {
                migName = migId.substring(underscoreIdx + 1);
            }
            applied.push({id: migId, name: migName, path: "", sql: ""});
        }
        cursor = quoteEnd + 1;
    }

    return applied;
}

# Records a migration as applied by appending to migration_lock.toml.
public function recordMigrationApplied(
    string migrationsDir,
    string migrationId,
    string migrationName
) returns MigrationError? {
    Migration[]|MigrationError current = getAppliedMigrations(migrationsDir);
    Migration[] applied = [];
    if current is Migration[] {
        applied = current;
    }

    // Check not already applied
    foreach Migration m in applied {
        if m.id == migrationId {
            return ();
        }
    }

    applied.push({id: migrationId, name: migrationName, path: "", sql: ""});
    return createMigrationLock(migrationsDir, applied);
}

# Generates a timestamp-based migration ID: YYYYMMDDHHMMSS.
function generateMigrationTimestamp() returns string {
    time:Utc now = time:utcNow();
    time:Civil civil = time:utcToCivil(now);
    string year = civil.year.toString();
    string month = padMigrationNum(civil.month);
    string day = padMigrationNum(civil.day);
    string hour = padMigrationNum(civil.hour);
    string minute = padMigrationNum(civil.minute);
    string second = padMigrationNum(<int>civil.second);
    return year + month + day + hour + minute + second;
}

function padMigrationNum(int n) returns string {
    string s = n.toString();
    if s.length() == 1 {
        return "0" + s;
    }
    return s;
}
