# PostgreSQL dialect helpers.

# Quote an identifier using PostgreSQL rules.
public function postgresqlQuoteIdentifier(string identifier) returns string {
    return "\"" + identifier + "\"";
}

# Placeholder for PostgreSQL positional parameters.
public function postgresqlPlaceholder(int index) returns string {
    return "$" + index.toString();
}
