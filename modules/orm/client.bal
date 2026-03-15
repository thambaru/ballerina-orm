import ballerina/sql;
import ballerinax/mysql;
import ballerinax/mysql.driver as _;
import ballerinax/postgresql;
import ballerinax/postgresql.driver as _;

# Union type used to store either provider client.
public type NativeDbClient mysql:Client|postgresql:Client;

# ORM database client wrapper for MySQL and PostgreSQL backends.
#
# + provider - Active database provider for this client instance.
public class Client {
    public final Engine provider;

    private final NormalizedClientConfig config;
    private final NativeDbClient nativeClient;

    public function init(ClientConfig config) returns error? {
        NormalizedClientConfig normalized = check normalizeClientConfig(config);
        self.provider = normalized.provider;
        self.config = redactedConfig(normalized);

        if normalized.provider == MYSQL {
            mysql:Client|error dbClient = new (
                host = normalized.host,
                user = normalized.user,
                password = normalized.password,
                database = normalized.database,
                port = normalized.port,
                options = normalized.mysqlOptions,
                connectionPool = normalized.connectionPool
            );
            if dbClient is error {
                return dbClient;
            }
            self.nativeClient = dbClient;
            return;
        }

        postgresql:Client|error dbClient = new (
            host = normalized.host,
            username = normalized.user,
            password = normalized.password,
            database = normalized.database,
            port = normalized.port,
            options = normalized.postgresqlOptions,
            connectionPool = normalized.connectionPool
        );
        if dbClient is error {
            return dbClient;
        }
        self.nativeClient = dbClient;
    }

    # Returns the normalized configuration used by this client.
    #
    # + return - Normalized configuration with the password redacted.
    public function getConfig() returns NormalizedClientConfig {
        return self.config;
    }

    # Expose the underlying database client for low-level SQL operations.
    #
    # + return - The underlying mysql:Client or postgresql:Client handle.
    public function getNativeClient() returns NativeDbClient {
        return self.nativeClient;
    }

    # Convert a query plan to SQL and execute it as a read query.
    #
    # Use this for `findMany`, `findFirst`, `findUnique`, `count`, and `aggregate` operations.
    #
    # + plan - Compiled query plan describing the read operation.
    # + return - A stream of generic record rows, or an error.
    public function query(QueryPlan plan) returns stream<record {}, sql:Error?>|SchemaError|ClientError|sql:Error {
        if !isReadOperation(plan.operation) {
            return clientError(
                "CLIENT_QUERY_OPERATION_INVALID",
                string `Operation '${plan.operation}' cannot be executed with query().`
            );
        }

        SqlQuery sqlQuery = check toSql(plan, self.provider);
        sql:ParameterizedQuery parameterizedQuery = check toParameterizedSqlQuery(sqlQuery, self.provider);
        return self.rawQueryParameterized(parameterizedQuery);
    }

    # Convert a query plan to SQL and execute it as a write query.
    #
    # Use this for `create`, `createMany`, `update`, `updateMany`, `upsert`, `delete`, and `deleteMany` operations.
    #
    # + plan - Compiled query plan describing the write operation.
    # + return - SQL execution result, or an error.
    public function execute(QueryPlan plan) returns sql:ExecutionResult|SchemaError|ClientError|sql:Error {
        if !isWriteOperation(plan.operation) {
            return clientError(
                "CLIENT_EXECUTE_OPERATION_INVALID",
                string `Operation '${plan.operation}' cannot be executed with execute().`
            );
        }

        SqlQuery sqlQuery = check toSql(plan, self.provider);
        sql:ParameterizedQuery parameterizedQuery = check toParameterizedSqlQuery(sqlQuery, self.provider);
        return self.rawExecuteParameterized(parameterizedQuery);
    }

    # Execute raw SQL query text with positional parameters.
    # Returns a generic record stream. Cast result rows to your model type using a type descriptor.
    #
    # + text - Raw SQL query string with `?` (MySQL) or `$n` (PostgreSQL) placeholders.
    # + params - Positional parameter values matching the placeholders.
    # + return - A stream of generic record rows, or an error.
    public function rawQuery(string text, anydata[] params = []) returns stream<record {}, sql:Error?>|ClientError|sql:Error {
        sql:ParameterizedQuery parameterizedQuery = check toParameterizedSqlQuery({text: text, parameters: params}, self.provider);
        return self.rawQueryParameterized(parameterizedQuery);
    }

    # Execute raw SQL statement text with positional parameters.
    # Returns the number of affected rows.
    #
    # + text - Raw SQL statement string with `?` (MySQL) or `$n` (PostgreSQL) placeholders.
    # + params - Positional parameter values matching the placeholders.
    # + return - Number of affected rows, or an error.
    public function rawExecute(string text, anydata[] params = []) returns int|ClientError|sql:Error {
        sql:ParameterizedQuery parameterizedQuery = check toParameterizedSqlQuery({text: text, parameters: params}, self.provider);
        sql:ExecutionResult|sql:Error execResult = self.rawExecuteParameterized(parameterizedQuery);
        if execResult is sql:Error {
            return execResult;
        }
        return execResult.affectedRowCount ?: 0;
    }

    function rawQueryParameterized(sql:ParameterizedQuery parameterizedQuery) returns stream<record {}, sql:Error?>|sql:Error {
        if self.provider == MYSQL {
            mysql:Client dbClient = <mysql:Client>self.nativeClient;
            return dbClient->query(parameterizedQuery);
        }

        postgresql:Client dbClient = <postgresql:Client>self.nativeClient;
        return dbClient->query(parameterizedQuery);
    }

    function rawExecuteParameterized(sql:ParameterizedQuery parameterizedQuery) returns sql:ExecutionResult|sql:Error {
        if self.provider == MYSQL {
            mysql:Client dbClient = <mysql:Client>self.nativeClient;
            return dbClient->execute(parameterizedQuery);
        }

        postgresql:Client dbClient = <postgresql:Client>self.nativeClient;
        return dbClient->execute(parameterizedQuery);
    }

    # Create an executing query builder bound to this client for the given model type.
    #
    # Terminal methods on the returned builder execute immediately — no separate run step required.
    #
    # + modelType - Type descriptor of the model record type.
    # + return - An ExecutingQueryBuilder scoped to the given model.
    public function model(typedesc<anydata> modelType) returns ExecutingQueryBuilder {
        return new (self, extractModelName(modelType));
    }

    # Primary Prisma-like fluent API entry point. Returns a typed executing query builder.
    #
    # Example:
    # ```ballerina
    # User[] users = check db.'from(User)
    #     .'where({status: {equals: "ACTIVE"}})
    #     .orderBy({id: orm:DESC})
    #     .findMany();
    # ```
    #
    # + modelType - Type descriptor of the model record type.
    # + return - An ExecutingQueryBuilder scoped to the given model.
    public function 'from(typedesc<anydata> modelType) returns ExecutingQueryBuilder {
        return new (self, extractModelName(modelType));
    }

    # Close the underlying database client.
    #
    # + return - An error if closing fails, otherwise nil.
    public function close() returns error? {
        if self.provider == MYSQL {
            mysql:Client dbClient = <mysql:Client>self.nativeClient;
            return dbClient.close();
        }

        postgresql:Client dbClient = <postgresql:Client>self.nativeClient;
        return dbClient.close();
    }
}

# Convert generated SQL payload to a sql:ParameterizedQuery.
#
# + sqlQuery - SQL text and positional parameters to convert.
# + provider - Database provider that determines placeholder syntax.
# + return - A sql:ParameterizedQuery ready for execution, or a ClientError.
public function toParameterizedSqlQuery(SqlQuery sqlQuery, Engine provider) returns sql:ParameterizedQuery|ClientError {
    if provider == MYSQL {
        return buildMysqlParameterizedQuery(sqlQuery.text, sqlQuery.parameters);
    }
    return buildPostgresqlParameterizedQuery(sqlQuery.text, sqlQuery.parameters);
}

function buildMysqlParameterizedQuery(string text, anydata[] parameters) returns sql:ParameterizedQuery|ClientError {
    string[] strings = [];
    sql:Value[] values = [];
    string current = "";

    int parameterIndex = 0;
    int index = 0;
    while index < text.length() {
        string c = text.substring(index, index + 1);
        if c == "?" {
            if parameterIndex >= parameters.length() {
                return clientError(
                    "CLIENT_SQL_PARAMETER_MISMATCH",
                    "SQL contains more placeholders than provided parameters."
                );
            }

            strings.push(current);
            current = "";
            sql:Value value = check toSqlValue(parameters[parameterIndex], parameterIndex + 1);
            values.push(value);
            parameterIndex += 1;
        } else {
            current = string `${current}${c}`;
        }
        index += 1;
    }

    strings.push(current);
    if parameterIndex != parameters.length() {
        return clientError(
            "CLIENT_SQL_PARAMETER_MISMATCH",
            "More SQL parameters were provided than placeholders in the query."
        );
    }

    return assembleParameterizedQuery(strings, values);
}

function buildPostgresqlParameterizedQuery(string text, anydata[] parameters) returns sql:ParameterizedQuery|ClientError {
    string[] strings = [];
    sql:Value[] values = [];

    int cursor = 0;
    int parameterIndex = 0;
    while parameterIndex < parameters.length() {
        string token = "$" + (parameterIndex + 1).toString();
        int? tokenIndex = text.indexOf(token, cursor);
        if tokenIndex is () {
            return clientError(
                "CLIENT_SQL_PARAMETER_MISMATCH",
                string `Missing placeholder '${token}' in PostgreSQL SQL text.`
            );
        }

        int position = tokenIndex;
        strings.push(text.substring(cursor, position));
        sql:Value value = check toSqlValue(parameters[parameterIndex], parameterIndex + 1);
        values.push(value);
        cursor = position + token.length();
        parameterIndex += 1;
    }

    string unexpectedToken = "$" + (parameters.length() + 1).toString();
    if text.indexOf(unexpectedToken, cursor) is int {
        return clientError(
            "CLIENT_SQL_PARAMETER_MISMATCH",
            "SQL contains more placeholders than provided parameters."
        );
    }

    strings.push(text.substring(cursor));
    return assembleParameterizedQuery(strings, values);
}

function assembleParameterizedQuery(string[] strings, sql:Value[] values) returns sql:ParameterizedQuery {
    sql:ParameterizedQuery parameterizedQuery = ``;
    parameterizedQuery.strings = strings.cloneReadOnly();
    parameterizedQuery.insertions = values;
    return parameterizedQuery;
}

function toSqlValue(anydata value, int index) returns sql:Value|ClientError {
    if value is sql:Value {
        return value;
    }

    return clientError(
        "CLIENT_SQL_PARAMETER_TYPE_UNSUPPORTED",
        string `SQL parameter at position ${index.toString()} is not supported by sql:Value.`
    );
}

function redactedConfig(NormalizedClientConfig config) returns NormalizedClientConfig {
    return {
        provider: config.provider,
        host: config.host,
        port: config.port,
        user: config.user,
        password: (),
        database: config.database,
        mysqlOptions: config.mysqlOptions,
        postgresqlOptions: config.postgresqlOptions,
        connectionPool: config.connectionPool,
        query: config.query
    };
}

function isReadOperation(QueryOperation operation) returns boolean {
    return operation == FIND_MANY || operation == FIND_FIRST || operation == FIND_UNIQUE ||
        operation == COUNT || operation == AGGREGATE;
}

function isWriteOperation(QueryOperation operation) returns boolean {
    return operation == CREATE || operation == CREATE_MANY || operation == UPDATE ||
        operation == UPDATE_MANY || operation == UPSERT || operation == DELETE ||
        operation == DELETE_MANY;
}
