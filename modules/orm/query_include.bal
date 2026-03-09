# Relation include input types and helpers.

# Dynamic include payload.
#
# Top-level keys are relation field names and values are booleans or nested include/select maps.
public type IncludeInput map<anydata>;

# Collect relation names that are explicitly included with `true`.
public function includedRelations(IncludeInput input) returns string[] {
    string[] relations = [];
    foreach var [fieldName, includeValue] in input.entries() {
        if includeValue is boolean && includeValue {
            relations.push(fieldName);
        }
    }
    return relations;
}
