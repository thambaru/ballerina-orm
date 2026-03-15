import ballerinax/mysql;
import ballerinax/postgresql;

# Normalize client config from explicit fields and/or connection URL.
#
# + config - Raw client configuration potentially containing a connection URL.
# + return - Fully resolved and validated configuration, or a ClientError.
public function normalizeClientConfig(ClientConfig config) returns NormalizedClientConfig|ClientError {
    ParsedConnectionUrl? parsedFromUrl = ();
    string? rawUrl = config.url;
    if rawUrl is string {
        ParsedConnectionUrl|ClientError parsed = parseConnectionUrl(rawUrl);
        if parsed is ClientError {
            return parsed;
        }
        parsedFromUrl = parsed;
    }

    Engine? providerFromConfig = config.provider;
    Engine? providerFromUrl = parsedFromUrl?.provider;
    if providerFromConfig is Engine && providerFromUrl is Engine && providerFromConfig != providerFromUrl {
        return clientError(
            "CLIENT_PROVIDER_MISMATCH",
            string `Provider '${providerFromConfig}' does not match URL provider '${providerFromUrl}'.`,
            "provider"
        );
    }

    Engine? resolvedProvider = providerFromConfig ?: providerFromUrl;
    if resolvedProvider is () {
        return clientError("CLIENT_PROVIDER_REQUIRED", "Either provider or URL must be provided in client config.", "provider");
    }

    string host = pickString(config.host, parsedFromUrl?.host) ?: "localhost";
    if host.trim() == "" {
        return clientError("CLIENT_HOST_REQUIRED", "Host cannot be empty.", "host");
    }

    int port = config.port ?: parsedFromUrl?.port ?: defaultPort(resolvedProvider);
    if port <= 0 || port > 65535 {
        return clientError("CLIENT_PORT_INVALID", string `Port '${port}' is out of range.`, "port");
    }

    string? user = pickString(config.user, parsedFromUrl?.user, defaultUser(resolvedProvider));
    string? password = pickString(config.password, parsedFromUrl?.password);
    string? database = pickString(config.database, parsedFromUrl?.database);

    if resolvedProvider == MYSQL && config.postgresqlOptions is postgresql:Options {
        return clientError(
            "CLIENT_OPTIONS_MISMATCH",
            "postgresqlOptions cannot be set when provider is MYSQL.",
            "postgresqlOptions"
        );
    }

    if resolvedProvider == POSTGRESQL && config.mysqlOptions is mysql:Options {
        return clientError(
            "CLIENT_OPTIONS_MISMATCH",
            "mysqlOptions cannot be set when provider is POSTGRESQL.",
            "mysqlOptions"
        );
    }

    return {
        provider: resolvedProvider,
        host,
        port,
        user,
        password,
        database,
        mysqlOptions: config.mysqlOptions,
        postgresqlOptions: config.postgresqlOptions,
        connectionPool: resolveConnectionPool(config.connectionPool),
        query: parsedFromUrl?.query ?: {}
    };
}

# Resolve ORM pool config into the shared SQL connection pool type.
#
# + poolConfig - Optional pool configuration to resolve.
# + return - The resolved pool config, or nil if none was provided.
public function resolveConnectionPool(ConnectionPoolConfig? poolConfig = ()) returns ConnectionPoolConfig? {
    return poolConfig;
}

function pickString(string? primary, string? secondary, string? fallback = ()) returns string? {
    if primary is string {
        return primary;
    }
    if secondary is string {
        return secondary;
    }
    return fallback;
}

function defaultPort(Engine provider) returns int {
    return provider == MYSQL ? DEFAULT_MYSQL_PORT : DEFAULT_POSTGRESQL_PORT;
}

function defaultUser(Engine provider) returns string {
    return provider == MYSQL ? "root" : "postgres";
}
