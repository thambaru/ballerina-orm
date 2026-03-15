# PostgreSQL dialect helpers.

# Quote an identifier using PostgreSQL rules.
#
# + identifier - Raw identifier string to quote.
# + return - Double-quoted identifier safe for use in PostgreSQL SQL strings.
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
#
# + index - 1-based parameter index.
# + return - A `$n` placeholder string (e.g. `$1`, `$2`).
public function postgresqlPlaceholder(int index) returns string {
    return "$" + index.toString();
}
