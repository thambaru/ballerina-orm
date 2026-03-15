# Parse database connection URLs into normalized provider/host/credential values.
#
# + connectionUrl - Connection URL string (e.g. `mysql://user:pass@host:3306/db`).
# + return - Parsed connection values, or a ClientError if the URL is invalid.
public function parseConnectionUrl(string connectionUrl) returns ParsedConnectionUrl|ClientError {
    string trimmed = connectionUrl.trim();
    if trimmed == "" {
        return clientError("URL_EMPTY", "Connection URL cannot be empty.", "url");
    }

    int? schemeSep = trimmed.indexOf("://");
    if schemeSep is () {
        return clientError("URL_SCHEME_MISSING", "Connection URL must include a scheme such as mysql:// or postgresql://.",
            "url");
    }

    string scheme = trimmed.substring(0, schemeSep).toLowerAscii();
    Engine provider = check providerFromScheme(scheme);

    string remainder = trimmed.substring(schemeSep + 3);
    string queryString = "";
    int? querySep = remainder.indexOf("?");
    if querySep is int {
        queryString = remainder.substring(querySep + 1);
        remainder = remainder.substring(0, querySep);
    }
    map<string> query = parseQueryString(queryString);

    string authority = remainder;
    string rawPath = "";
    int? pathSep = remainder.indexOf("/");
    if pathSep is int {
        authority = remainder.substring(0, pathSep);
        rawPath = remainder.substring(pathSep + 1);
    }

    if authority.trim() == "" {
        return clientError("URL_HOST_MISSING", "Connection URL must include a host.", "url");
    }

    string? user = ();
    string? password = ();
    string hostPort = authority;

    int? atSep = authority.lastIndexOf("@");
    if atSep is int {
        string userInfo = authority.substring(0, atSep);
        hostPort = authority.substring(atSep + 1);

        if userInfo == "" {
            return clientError("URL_USERINFO_INVALID", "URL user info cannot be empty before '@'.", "url");
        }

        int? passwordSep = userInfo.indexOf(":");
        if passwordSep is int {
            user = userInfo.substring(0, passwordSep);
            password = userInfo.substring(passwordSep + 1);
        } else {
            user = userInfo;
        }
    }

    [string, int]|ClientError hostAndPort = parseHostAndPort(hostPort, provider);
    if hostAndPort is ClientError {
        return hostAndPort;
    }

    string? database = ();
    if rawPath != "" {
        int? nestedPathSep = rawPath.indexOf("/");
        string dbSegment = nestedPathSep is int ? rawPath.substring(0, nestedPathSep) : rawPath;
        if dbSegment != "" {
            database = dbSegment;
        }
    }

    return {
        provider,
        host: hostAndPort[0],
        port: hostAndPort[1],
        user,
        password,
        database,
        query
    };
}

function providerFromScheme(string scheme) returns Engine|ClientError {
    if scheme == "mysql" {
        return MYSQL;
    }
    if scheme == "postgresql" || scheme == "postgres" {
        return POSTGRESQL;
    }

    return clientError(
        "URL_SCHEME_UNSUPPORTED",
        string `Unsupported URL scheme '${scheme}'. Supported schemes: mysql, postgresql.`,
        "url"
    );
}

function parseHostAndPort(string hostPort, Engine provider) returns [string, int]|ClientError {
    string host = "";
    string? rawPort = ();

    if hostPort.startsWith("[") {
        int? bracketEnd = hostPort.indexOf("]");
        if bracketEnd is () {
            return clientError("URL_HOST_INVALID", "Invalid IPv6 host segment in connection URL.", "url");
        }

        host = hostPort.substring(1, bracketEnd);
        if bracketEnd + 1 < hostPort.length() {
            string trailing = hostPort.substring(bracketEnd + 1);
            if !trailing.startsWith(":") {
                return clientError("URL_HOST_INVALID", "Invalid host/port segment in connection URL.", "url");
            }
            rawPort = trailing.substring(1);
        }
    } else {
        int colonCount = countOccurrences(hostPort, ":");
        if colonCount == 1 {
            int colonIndex = <int>hostPort.lastIndexOf(":");
            host = hostPort.substring(0, colonIndex);
            rawPort = hostPort.substring(colonIndex + 1);
        } else {
            host = hostPort;
        }
    }

    if host.trim() == "" {
        return clientError("URL_HOST_MISSING", "Connection URL must include a valid host.", "url");
    }

    int port = provider == MYSQL ? DEFAULT_MYSQL_PORT : DEFAULT_POSTGRESQL_PORT;
    if rawPort is string {
        if rawPort == "" {
            return clientError("URL_PORT_INVALID", "Connection URL port cannot be empty.", "url");
        }

        int|error parsedPort = int:fromString(rawPort);
        if parsedPort is error {
            return clientError("URL_PORT_INVALID", string `Invalid port '${rawPort}' in connection URL.`, "url");
        }

        if parsedPort <= 0 || parsedPort > 65535 {
            return clientError("URL_PORT_INVALID", string `Port '${rawPort}' is out of range.`, "url");
        }

        port = parsedPort;
    }

    return [host, port];
}

function parseQueryString(string queryString) returns map<string> {
    map<string> query = {};
    if queryString == "" {
        return query;
    }

    int cursor = 0;
    int length = queryString.length();
    while cursor <= length {
        int? nextSep = queryString.indexOf("&", cursor);
        int end = nextSep is int ? nextSep : length;

        string pair = queryString.substring(cursor, end);
        if pair != "" {
            int? eqIndex = pair.indexOf("=");
            if eqIndex is int {
                string key = pair.substring(0, eqIndex);
                string value = pair.substring(eqIndex + 1);
                if key != "" {
                    query[key] = value;
                }
            } else {
                query[pair] = "";
            }
        }

        if nextSep is () {
            break;
        }
        cursor = end + 1;
    }

    return query;
}

function countOccurrences(string value, string target) returns int {
    int count = 0;
    int index = 0;
    while index < value.length() {
        string ch = value.substring(index, index + 1);
        if ch == target {
            count += 1;
        }
        index += 1;
    }
    return count;
}
