# MySQL dialect helpers.

# Quote an identifier using MySQL rules.
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
public function mysqlPlaceholder(int index) returns string {
    _ = index;
    return "?";
}
