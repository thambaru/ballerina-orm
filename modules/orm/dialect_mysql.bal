# MySQL dialect helpers.

# Quote an identifier using MySQL rules.
#
# + identifier - Raw identifier string to quote.
# + return - Backtick-quoted identifier safe for use in MySQL SQL strings.
public function mysqlQuoteIdentifier(string identifier) returns string {
    string escaped = "";
    int index = 0;
    while index < identifier.length() {
        string current = identifier.substring(index, index + 1);
        if current == "`" {
            escaped = escaped + "``";
        } else {
            escaped = string `${escaped}${current}`;
        }
        index += 1;
    }
    return "`" + escaped + "`";
}

# Placeholder for MySQL positional parameters.
#
# + index - 1-based parameter index (ignored for MySQL).
# + return - The literal `?` placeholder string.
public function mysqlPlaceholder(int index) returns string {
    _ = index;
    return "?";
}
