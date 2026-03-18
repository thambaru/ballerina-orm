# Shared type mapping helpers for compiler-plugin analysis and generation.

# Returns `true` if two Ballerina field types are compatible for relation keys.
#
# + sourceType - Ballerina type string of the foreign key field.
# + targetType - Ballerina type string of the referenced primary key field.
# + return - `true` if the two types are considered compatible for relation mapping.
public function areRelationTypesCompatible(string sourceType, string targetType) returns boolean {
    return normalizedRelationTypeKey(sourceType) == normalizedRelationTypeKey(targetType);
}

# Returns a type string suitable for generated create inputs.
#
# + ballerinaType - The original Ballerina type string.
# + return - The base type without optional or array decorators.
public function createInputFieldType(string ballerinaType) returns string {
    return stripTypeDecorators(ballerinaType);
}

# Returns a type string suitable for generated update inputs.
#
# + ballerinaType - The original Ballerina type string.
# + nullable - Whether the field should be treated as optional in update inputs.
# + return - The base type, optionally suffixed with `?` for nullable update fields.
public function updateInputFieldType(string ballerinaType, boolean nullable) returns string {
    string baseType = stripTypeDecorators(ballerinaType);
    if nullable && !baseType.endsWith("?") {
        return string `${baseType}?`;
    }
    return baseType;
}

# Emit a Ballerina field identifier, quoting keyword-like names when needed.
#
# + fieldName - The field name to emit.
# + return - The field name prefixed with `'` if it is a Ballerina keyword.
public function emitFieldIdentifier(string fieldName) returns string {
    return isKeywordIdentifier(fieldName) ? "'" + fieldName : fieldName;
}

function normalizedRelationTypeKey(string ballerinaType) returns string {
    string value = stripTypeDecorators(ballerinaType).toLowerAscii();

    if value == "byte" || value == "int" {
        return "int";
    }

    if value == "float" || value == "decimal" {
        return "number";
    }

    if value == "string" || value.endsWith(":uuid") {
        return "string";
    }

    if value.endsWith(":utc") || value.endsWith(":civil") || value.endsWith(":date") ||
        value.endsWith(":timeofday") {
        return "time";
    }

    int? separator = value.lastIndexOf(":");
    if separator is int {
        return value.substring(separator + 1);
    }

    return value;
}

function stripTypeDecorators(string ballerinaType) returns string {
    string value = ballerinaType.trim();

    while value.endsWith("?") {
        value = value.substring(0, value.length() - 1);
    }

    while value.endsWith("[]") {
        value = value.substring(0, value.length() - 2);
    }

    return value;
}

function isKeywordIdentifier(string fieldName) returns boolean {
    return fieldName == "from" ||
        fieldName == "where" ||
        fieldName == "select" ||
        fieldName == "table" ||
        fieldName == "in" ||
        fieldName == "equals" ||
        fieldName == "order" ||
        fieldName == "group" ||
        fieldName == "by" ||
        fieldName == "join" ||
        fieldName == "limit" ||
        fieldName == "type" ||
        fieldName == "function" ||
        fieldName == "transaction" ||
        fieldName == "check" ||
        fieldName == "error";
}
