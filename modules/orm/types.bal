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
#
# + provider - Explicit database provider. Inferred from `url` if omitted.
# + url - Full connection URL. Overrides individual fields when supplied.
# + host - Database host name or IP address.
# + port - Database port number.
# + user - Database user name.
# + password - Database password.
# + database - Target database or schema name.
# + mysqlOptions - Additional MySQL-specific connection options.
# + postgresqlOptions - Additional PostgreSQL-specific connection options.
# + connectionPool - Optional connection pool settings.
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
#
# + provider - Database provider inferred from the URL scheme.
# + host - Host name or IP address extracted from the URL.
# + port - Port number extracted from the URL.
# + user - User name extracted from the URL authority, if present.
# + password - Password extracted from the URL authority, if present.
# + database - Database name extracted from the URL path, if present.
# + query - Additional query parameters from the URL.
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
#
# + provider - Resolved database provider.
# + host - Resolved host name or IP address.
# + port - Resolved port number.
# + user - Resolved user name, or nil if not set.
# + password - Resolved password, or nil if not set.
# + database - Resolved database name, or nil if not set.
# + mysqlOptions - MySQL-specific connection options, if applicable.
# + postgresqlOptions - PostgreSQL-specific connection options, if applicable.
# + connectionPool - Resolved connection pool settings, if any.
# + query - Extra query parameters from the connection URL.
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
#
# + code - Machine-readable error code.
# + message - Human-readable error description.
# + fieldName - Name of the configuration field that caused the error, if applicable.
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
