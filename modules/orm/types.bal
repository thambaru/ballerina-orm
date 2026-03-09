import ballerina/sql;
import ballerinax/mysql;
import ballerinax/postgresql;

# Default port used by MySQL.
public const DEFAULT_MYSQL_PORT = 3306;

# Default port used by PostgreSQL.
public const DEFAULT_POSTGRESQL_PORT = 5432;

# Shared connection pool configuration delegated to `ballerina/sql`.
public type ConnectionPoolConfig sql:ConnectionPool;

# Client configuration accepted by `orm:Client`.
public type ClientConfig record {|
    Engine? provider = ();
    string? url = ();
    string? host = ();
    int? port = ();
    string? user = ();
    string? password = ();
    string? database = ();
    mysql:Options? mysqlOptions = ();
    postgresql:Options? postgresqlOptions = ();
    ConnectionPoolConfig? connectionPool = ();
|};

# Parsed values from a connection URL.
public type ParsedConnectionUrl record {|
    Engine provider;
    string host;
    int port;
    string? user = ();
    string? password = ();
    string? database = ();
    map<string> query = {};
|};

# Normalized runtime configuration used by the ORM client.
public type NormalizedClientConfig record {|
    Engine provider;
    string host;
    int port;
    string? user = ();
    string? password = ();
    string? database = ();
    mysql:Options? mysqlOptions = ();
    postgresql:Options? postgresqlOptions = ();
    ConnectionPoolConfig? connectionPool = ();
    map<string> query = {};
|};

# Client configuration and URL parser error payload.
public type ClientErrorDetail record {|
    string code;
    string message;
    string? fieldName = ();
|};

# Client subsystem error type.
public type ClientError error<ClientErrorDetail>;

function clientError(string code, string message, string? fieldName = ()) returns ClientError {
    return error("CLIENT_ERROR", code = code, message = message, fieldName = fieldName);
}
