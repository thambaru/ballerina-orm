# MySQL dialect helpers.

# Quote an identifier using MySQL rules.
public function mysqlQuoteIdentifier(string identifier) returns string {
    return "`" + identifier + "`";
}

# Placeholder for MySQL positional parameters.
public function mysqlPlaceholder(int index) returns string {
    _ = index;
    return "?";
}
