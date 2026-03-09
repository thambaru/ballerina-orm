# Filter and ordering input types used by the query builder.

# Sort direction constants.
public const ASC = "ASC";
public const DESC = "DESC";

# Supported sort direction type.
public type SortDirection ASC|DESC;

# Dynamic where-clause payload.
#
# Field names map to literal values or operator maps.
# Logical operators are represented by `AND`, `OR`, and `NOT` keys.
public type WhereInput map<anydata>;

# Dynamic order-by payload where keys are field names and values are sort directions.
public type OrderByInput map<SortDirection>;

# Aggregate input payload.
public type AggregateInput map<anydata>;

# Checks whether the provided key is a logical where operator.
public function isLogicalWhereOperator(string key) returns boolean {
    return key == "AND" || key == "OR" || key == "NOT";
}
