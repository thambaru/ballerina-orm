import ballerina/io;
import ballerina/os;
import bal_orm.orm_cli;

# Sample CLI entry point for `bal orm` commands
#
# Usage:
#   bal run bal_orm_cli.bal -- init
#   bal run bal_orm_cli.bal -- migrate dev --name init
#   bal run bal_orm_cli.bal -- migrate status
#   bal run bal_orm_cli.bal -- db pull

public function main(string... args) returns error? {
    if args.length() == 0 {
        printHelp();
        return;
    }
    
    string command = args[0];
    
    match command {
        "init" => {
            string projectDir = os:getCwd();
            check orm_cli:handleInitCommand(projectDir);
        }
        "migrate" => {
            if args.length() < 2 {
                io:println("Error: migrate requires a subcommand (dev, deploy, reset, status)");
                return;
            }
            
            string subCommand = args[1];
            check handleMigrateCommand(subCommand, args);
        }
        "db" => {
            if args.length() < 2 {
                io:println("Error: db requires a subcommand (push, pull)");
                return;
            }
            
            string subCommand = args[1];
            check handleDbCommand(subCommand, args);
        }
        "generate" => {
            string projectDir = os:getCwd();
            check orm_cli:handleGenerateCommand(projectDir);
        }
        _ => {
            io:println("Error: Unknown command: " + command);
            printHelp();
        }
    }
}

function handleMigrateCommand(string subCommand, string[] args) returns error? {
    string projectDir = os:getCwd();
    string migrationsDir = projectDir + "/migrations";
    
    # For demo purposes, use hardcoded config
    # In production, this would read from .ormrc.json and establish DB connection
    
    match subCommand {
        "dev" => {
            string name = getArgValue(args, "--name") ?: "migration";
            io:println("Creating development migration: " + name);
            # check orm_cli:handleMigrateDevCommand(dbClient, "MYSQL", migrationsDir, desiredSchema, name);
        }
        "deploy" => {
            io:println("Deploying migrations...");
            # check orm_cli:handleMigrateDeployCommand(dbClient, migrationsDir);
        }
        "reset" => {
            io:println("Resetting database...");
            # check orm_cli:handleMigrateResetCommand(dbClient, migrationsDir, "MYSQL");
        }
        "status" => {
            io:println("Migration status:");
            # check orm_cli:handleMigrateStatusCommand(dbClient, migrationsDir);
        }
        _ => {
            io:println("Error: Unknown migrate subcommand: " + subCommand);
        }
    }
}

function handleDbCommand(string subCommand, string[] args) returns error? {
    # For demo purposes, use hardcoded config
    
    match subCommand {
        "push" => {
            io:println("Pushing schema to database...");
            # check orm_cli:handleDbPushCommand(dbClient, "MYSQL", desiredSchema);
        }
        "pull" => {
            string? outputFile = getArgValue(args, "--output");
            io:println("Pulling schema from database...");
            # check orm_cli:handleDbPullCommand(dbClient, "MYSQL", outputFile);
        }
        _ => {
            io:println("Error: Unknown db subcommand: " + subCommand);
        }
    }
}

function getArgValue(string[] args, string flag) returns string? {
    foreach int i in 0 ..< args.length() {
        if args[i] == flag && i + 1 < args.length() {
            return args[i + 1];
        }
    }
    return ();
}

function printHelp() {
    io:println("Ballerina ORM CLI");
    io:println("");
    io:println("USAGE:");
    io:println("  bal orm <command> [options]");
    io:println("");
    io:println("COMMANDS:");
    io:println("  init                Initialize ORM project structure");
    io:println("  migrate dev         Create and apply a dev migration");
    io:println("  migrate deploy      Apply pending migrations");
    io:println("  migrate reset       Reset database (dev only)");
    io:println("  migrate status      Show migration status");
    io:println("  db push             Push schema without migration file");
    io:println("  db pull             Pull schema from database");
    io:println("  generate            Generate ORM client code");
    io:println("");
    io:println("OPTIONS:");
    io:println("  --name <name>       Migration name (for migrate dev)");
    io:println("  --output <file>     Output file (for db pull)");
}
