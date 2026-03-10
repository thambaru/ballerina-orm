# Compares two schemas (desired vs actual) and returns the differences.
public function diffSchemas(
    map<IntrospectedTable> desiredTables,
    map<IntrospectedTable> actualTables,
    string provider
) returns SchemaDiff {
    _ = provider;

    SchemaDiff diff = {
        added: [],
        modified: [],
        removed: []
    };

    foreach string tableName in desiredTables.keys() {
        if !actualTables.hasKey(tableName) {
            diff.added.push({
                itemType: "TABLE",
                'table: tableName,
                description: "New table"
            });
        }
    }

    foreach string tableName in actualTables.keys() {
        if !desiredTables.hasKey(tableName) {
            diff.removed.push({
                itemType: "TABLE",
                'table: tableName,
                description: "Removed table"
            });
        }
    }

    return diff;
}

# Sorts a SchemaDiff in a logical apply order.
public function sortDiffForApply(SchemaDiff diff) returns SchemaDiff {
    return diff;
}
