import ballerina/io;
import ballerina/os;
import ballerinax/mysql;
import ballerinax/mysql.driver as _;
import ballerinax/postgresql;
import ballerinax/postgresql.driver as _;

# Connection settings read from `.ormrc.json` in the project root.
public type CliRcConfig record {|
    string provider = "MYSQL";
    string host = "localhost";
    int port = 3306;
    string user = "root";
    string password = "";
    string database = "";
|};

# Entry point for the `bal orm` CLI tool.
#
# Dispatches to the appropriate command handler based on `args`.
# Non-DB commands (`init`, `migrate status`, `generate`) work without a database
# connection.  DB commands (`migrate dev/deploy/reset`, `db push/pull`) read
# connection settings from `.ormrc.json` in the current working directory.
#
# + args - CLI arguments (command + options)
# + return - error if a command fails
public function runCli(string[] args) returns error? {
    if args.length() == 0 {
        printCliHelp();
        return;
    }

    string command = args[0];
    string projectDir = let string pwd = os:getEnv("PWD") in (pwd == "" ? "." : pwd);
    string migrationsDir = projectDir + "/migrations";

    match command {
        "init" => {
            check handleInitCommand(projectDir);
        }
        "generate" => {
            check handleGenerateCommand(projectDir);
        }
        "migrate" => {
            if args.length() < 2 {
                io:println("Error: 'migrate' requires a subcommand: dev, deploy, reset, status");
                return;
            }
            string sub = args[1];
            if sub == "status" {
                // status is file-based: no DB connection needed
                check handleMigrateStatusCommand(migrationsDir);
            } else {
                CliRcConfig cfg = check readOrmConfig(projectDir);
                CliDbClient dbClient = check openDbClient(cfg);
                string provider = cfg.provider.toUpperAscii();
                match sub {
                    "dev" => {
                        string name = cliArgValue(args, "--name") ?: "migration";
                        // desiredTables would be populated by the compiler plugin in a full
                        // implementation; pass an empty map so the diff shows all tables as new.
                        check handleMigrateDevCommand(dbClient, provider, migrationsDir, {}, name);
                    }
                    "deploy" => {
                        check handleMigrateDeployCommand(dbClient, provider, migrationsDir);
                    }
                    "reset" => {
                        check handleMigrateResetCommand(dbClient, provider, migrationsDir);
                    }
                    _ => {
                        io:println("Error: Unknown migrate subcommand '" + sub + "'. Use: dev, deploy, reset, status");
                    }
                }
                check dbClient.close();
            }
        }
        "db" => {
            if args.length() < 2 {
                io:println("Error: 'db' requires a subcommand: push, pull");
                return;
            }
            string sub = args[1];
            CliRcConfig cfg = check readOrmConfig(projectDir);
            CliDbClient dbClient = check openDbClient(cfg);
            string provider = cfg.provider.toUpperAscii();
            match sub {
                "push" => {
                    // desiredTables comes from compiler plugin output in a full implementation
                    check handleDbPushCommand(dbClient, provider, {});
                }
                "pull" => {
                    string? outputFile = cliArgValue(args, "--output");
                    check handleDbPullCommand(dbClient, provider, outputFile);
                }
                _ => {
                    io:println("Error: Unknown db subcommand '" + sub + "'. Use: push, pull");
                }
            }
            check dbClient.close();
        }
        "help"|"--help"|"-h" => {
            printCliHelp();
        }
        _ => {
            io:println("Error: Unknown command '" + command + "'");
            printCliHelp();
        }
    }
}

# Reads `.ormrc.json` from the given project directory.
#
# + projectDir - absolute path to the project root
# + return - parsed config or error if the file is missing / malformed
function readOrmConfig(string projectDir) returns CliRcConfig|error {
    string configPath = projectDir + "/.ormrc.json";
    json|io:Error raw = io:fileReadJson(configPath);
    if raw is io:Error {
        return error(string `ORM config not found at '${configPath}'. ` +
            "Run `bal orm init` or create .ormrc.json with provider, host, port, user, password, database.");
    }
    return (<json>raw).cloneWithType(CliRcConfig);
}

# Opens a database client using settings from a `CliRcConfig`.
#
# + cfg - connection settings
# + return - a live `sql:Client` or an error
function openDbClient(CliRcConfig cfg) returns CliDbClient|error {
    if cfg.provider.toUpperAscii() == "POSTGRESQL" {
        return check new postgresql:Client(
            cfg.host,
            cfg.user,
            cfg.password,
            cfg.database,
            cfg.port
        );
    }
    return check new mysql:Client(
        cfg.host,
        cfg.user,
        cfg.password,
        cfg.database,
        cfg.port
    );
}

# Extracts the value that follows a named flag in `args`.
#
# + args - full argument list
# + flag - flag name, e.g. `"--name"`
# + return - the next token after the flag, or `()` if not present
function cliArgValue(string[] args, string flag) returns string? {
    foreach int i in 0 ..< args.length() - 1 {
        if args[i] == flag {
            return args[i + 1];
        }
    }
    return ();
}

# Prints usage help to stdout.
function printCliHelp() {
    io:println("Ballerina ORM CLI");
    io:println("");
    io:println("USAGE:");
    io:println("  bal run . -- <command> [options]");
    io:println("");
    io:println("COMMANDS:");
    io:println("  init                 Initialize migrations directory and .ormrc.json template");
    io:println("  migrate dev          Diff schema, create migration file, and apply it (dev)");
    io:println("  migrate deploy       Apply all pending migrations (production)");
    io:println("  migrate reset        Drop and re-apply all migrations (dev only)");
    io:println("  migrate status       Show applied / pending migration status");
    io:println("  db push              Sync schema to database without a migration file");
    io:println("  db pull              Introspect database and generate Ballerina record types");
    io:println("  generate             Trigger ORM compiler plugin code generation");
    io:println("  help                 Show this help message");
    io:println("");
    io:println("OPTIONS:");
    io:println("  --name <label>       Migration name label (for migrate dev)");
    io:println("  --output <file>      Output file path (for db pull; defaults to stdout)");
    io:println("");
    io:println("CONFIGURATION (.ormrc.json):");
    io:println("  {");
    io:println("    \"provider\": \"MYSQL\",   // or \"POSTGRESQL\"");
    io:println("    \"host\":     \"localhost\",");
    io:println("    \"port\":     3306,");
    io:println("    \"user\":     \"root\",");
    io:println("    \"password\": \"\",");
    io:println("    \"database\": \"myapp\"");
    io:println("  }");
}
