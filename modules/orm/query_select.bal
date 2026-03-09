# Projection input types and helpers.

# Dynamic select payload.
#
# Top-level keys are field names and values are booleans or nested select maps.
public type SelectInput map<anydata>;

# Extract top-level selected fields where the value is `true`.
public function selectedFields(SelectInput input) returns string[] {
    string[] fields = [];
    foreach var [fieldName, selector] in input.entries() {
        if selector is boolean && selector {
            fields.push(fieldName);
        }
    }
    return fields;
}
