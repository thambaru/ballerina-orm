# PostgreSQL dialect helpers.

# Quote an identifier using PostgreSQL rules.
public function postgresqlQuoteIdentifier(string identifier) returns string {
    string escaped = "";
    int index = 0;
    while index < identifier.length() {
        string current = identifier.substring(index, index + 1);
        if current == "\"" {
            escaped = escaped + "\"\"";
        } else {
            escaped = string `${escaped}${current}`;
        }
        index += 1;
    }
    return "\"" + escaped + "\"";
}

# Placeholder for PostgreSQL positional parameters.
public function postgresqlPlaceholder(int index) returns string {
    return "$" + index.toString();
}
