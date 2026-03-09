import ballerinax/mysql;
import ballerinax/mysql.driver as _;
import ballerinax/postgresql;
import ballerinax/postgresql.driver as _;

# Union type used to store either provider client.
public type NativeDbClient mysql:Client|postgresql:Client;

# ORM database client wrapper for MySQL and PostgreSQL backends.
public class Client {
    public final Engine provider;

    private final NormalizedClientConfig config;
    private final NativeDbClient nativeClient;

    public function init(ClientConfig config) returns error? {
        NormalizedClientConfig normalized = check normalizeClientConfig(config);
        self.provider = normalized.provider;
        self.config = normalized;

        if normalized.provider == MYSQL {
            mysql:Client|error dbClient = new (
                normalized.host,
                normalized.user,
                normalized.password,
                normalized.database,
                normalized.port,
                normalized.mysqlOptions,
                normalized.connectionPool
            );
            if dbClient is error {
                return dbClient;
            }
            self.nativeClient = dbClient;
            return;
        }

        postgresql:Client|error dbClient = new (
            normalized.host,
            normalized.user,
            normalized.password,
            normalized.database,
            normalized.port,
            normalized.postgresqlOptions,
            normalized.connectionPool
        );
        if dbClient is error {
            return dbClient;
        }
        self.nativeClient = dbClient;
    }

    # Returns the normalized configuration used by this client.
    public function getConfig() returns NormalizedClientConfig {
        return self.config;
    }

    # Expose the underlying database client for low-level SQL operations.
    public function getNativeClient() returns NativeDbClient {
        return self.nativeClient;
    }

    # Close the underlying database client.
    public isolated function close() returns error? {
        if self.provider == MYSQL {
            mysql:Client dbClient = <mysql:Client>self.nativeClient;
            return dbClient.close();
        }

        postgresql:Client dbClient = <postgresql:Client>self.nativeClient;
        return dbClient.close();
    }
}
