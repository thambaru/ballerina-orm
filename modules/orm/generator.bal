# Type and CRUD wrapper generation for ORM models.

# Generate model-level type and CRUD sources for all schema models.
public function generateModelArtifacts(SchemaGraph graph) returns map<ModelGeneration> {
    map<ModelGeneration> artifacts = {};

    foreach var [modelName, model] in graph.models.entries() {
        artifacts[modelName] = generateModelArtifact(model);
    }

    return artifacts;
}

function generateModelArtifact(ModelDefinition model) returns ModelGeneration {
    string createTypeName = model.name + "CreateInput";
    string updateTypeName = model.name + "UpdateInput";
    string whereTypeName = model.name + "WhereInput";
    string orderByTypeName = model.name + "OrderByInput";
    string includeTypeName = model.name + "Include";
    string[] filterTypeSources = generateFieldFilterTypes(model);
    string createDataMapperName = model.name.toLowerAscii() + "ToCreateData";
    string updateDataMapperName = model.name.toLowerAscii() + "ToUpdateData";

    GeneratedTypeSource[] generatedTypes = [
        {
            name: createTypeName,
            content: generateCreateInputType(model, createTypeName)
        },
        {
            name: updateTypeName,
            content: generateUpdateInputType(model, updateTypeName)
        },
        {
            name: whereTypeName,
            content: generateWhereInputType(model, whereTypeName)
        },
        {
            name: orderByTypeName,
            content: generateOrderByInputType(model, orderByTypeName)
        },
        {
            name: includeTypeName,
            content: generateIncludeType(model, includeTypeName)
        }
    ];

    foreach string filterTypeSource in filterTypeSources {
        generatedTypes.push({
            name: extractTypeName(filterTypeSource),
            content: filterTypeSource
        });
    }

    string modelToken = model.name.toLowerAscii();
    GeneratedCrudSource[] generatedCrud = [
        {
            name: modelToken + "FindMany",
            content: string `public function ${modelToken}FindMany(${whereTypeName}? whereInput = ()) returns QueryPlan {\n    QueryBuilder builder = fromModel("${model.name}");\n    if whereInput is ${whereTypeName} {\n        builder = builder.'where(whereInput);\n    }\n    return builder.findMany();\n}`
        },
        {
            name: modelToken + "FindUnique",
            content: string `public function ${modelToken}FindUnique(${whereTypeName} whereInput) returns QueryPlan {\n    return fromModel("${model.name}").'where(whereInput).findUnique();\n}`
        },
        {
            name: modelToken + "Create",
            content: generateCreateCrudSource(model, createTypeName, createDataMapperName, modelToken)
        },
        {
            name: modelToken + "Update",
            content: generateUpdateCrudSource(model, whereTypeName, updateTypeName, updateDataMapperName, modelToken)
        },
        {
            name: modelToken + "Delete",
            content: string `public function ${modelToken}Delete(${whereTypeName} whereInput) returns QueryPlan {\n    return fromModel("${model.name}").'where(whereInput).delete();\n}`
        }
    ];

    return {
        model: model.name,
        generatedTypes,
        generatedCrud
    };
}

function generateCreateCrudSource(
    ModelDefinition model,
    string createTypeName,
    string mapperName,
    string modelToken
) returns string {
    string mapper = generateCreateDataMapper(model, createTypeName, mapperName);
    string createFunction = string `public function ${modelToken}Create(${createTypeName} payload) returns QueryPlan {\n    return fromModel("${model.name}").create(${mapperName}(payload));\n}`;
    return mapper + "\n\n" + createFunction;
}

function generateUpdateCrudSource(
    ModelDefinition model,
    string whereTypeName,
    string updateTypeName,
    string mapperName,
    string modelToken
) returns string {
    string mapper = generateUpdateDataMapper(model, updateTypeName, mapperName);
    string updateFunction = string `public function ${modelToken}Update(${whereTypeName} whereInput, ${updateTypeName} payload) returns QueryPlan {\n    return fromModel("${model.name}").'where(whereInput).update(${mapperName}(payload));\n}`;
    return mapper + "\n\n" + updateFunction;
}

function generateCreateInputType(ModelDefinition model, string typeName) returns string {
    string[] lines = [];

    foreach ColumnDefinition column in model.columns {
        if !isCreateInputField(column) {
            continue;
        }

        string fieldType = createInputFieldType(column.ballerinaType);
        string fieldName = emitFieldIdentifier(column.fieldName);

        boolean required = !column.nullable && !column.hasDefault;
        string optionalMarker = required ? "" : "?";
        lines.push(string `    ${fieldType} ${fieldName}${optionalMarker};`);
    }

    return buildRecordTypeSource(typeName, lines);
}

function generateUpdateInputType(ModelDefinition model, string typeName) returns string {
    string[] lines = [];

    foreach ColumnDefinition column in model.columns {
        if !isUpdateInputField(column) {
            continue;
        }

        string fieldType = updateInputFieldType(column.ballerinaType, column.nullable);
        string fieldName = emitFieldIdentifier(column.fieldName);
        lines.push(string `    ${fieldType} ${fieldName}?;`);
    }

    return buildRecordTypeSource(typeName, lines);
}

function generateIncludeType(ModelDefinition model, string typeName) returns string {
    string[] lines = [];

    foreach RelationDefinition relation in model.relations {
        string relationField = emitFieldIdentifier(relation.fieldName);
        lines.push(string `    boolean ${relationField}?;`);
    }

    return buildRecordTypeSource(typeName, lines);
}

function generateWhereInputType(ModelDefinition model, string typeName) returns string {
    string[] lines = [
        string `    ${typeName}[]? AND;`,
        string `    ${typeName}[]? OR;`,
        string `    ${typeName}? NOT;`
    ];

    foreach ColumnDefinition column in model.columns {
        if !isWhereOrderInputField(column) {
            continue;
        }

        string fieldType = stripTypeDecorators(column.ballerinaType);
        string fieldName = emitFieldIdentifier(column.fieldName);
        string filterTypeName = buildFilterTypeName(model.name, column.fieldName);
        lines.push(string `    ${fieldType}|${filterTypeName} ${fieldName}?;`);
    }

    return buildRecordTypeSource(typeName, lines);
}

function generateOrderByInputType(ModelDefinition model, string typeName) returns string {
    string[] lines = [];

    foreach ColumnDefinition column in model.columns {
        if !isWhereOrderInputField(column) {
            continue;
        }

        string fieldName = emitFieldIdentifier(column.fieldName);
        lines.push(string `    SortDirection ${fieldName}?;`);
    }

    return buildRecordTypeSource(typeName, lines);
}

function generateFieldFilterTypes(ModelDefinition model) returns string[] {
    string[] output = [];

    foreach ColumnDefinition column in model.columns {
        if !isWhereOrderInputField(column) {
            continue;
        }

        string filterTypeName = buildFilterTypeName(model.name, column.fieldName);
        string fieldType = stripTypeDecorators(column.ballerinaType);
        FilterKind filterKind = resolveFilterKind(fieldType);

        string[] lines = [
            string `    ${fieldType}? equals;`,
            string `    ${fieldType}? not;`,
            string `    ${fieldType}[]? 'in;`,
            string `    ${fieldType}[]? notIn;`
        ];

        if filterKind == FILTER_KIND_INT || filterKind == FILTER_KIND_NUMBER {
            lines.push(string `    ${fieldType}? lt;`);
            lines.push(string `    ${fieldType}? lte;`);
            lines.push(string `    ${fieldType}? gt;`);
            lines.push(string `    ${fieldType}? gte;`);
        }

        if filterKind == FILTER_KIND_STRING {
            lines.push("    string? contains;");
            lines.push("    string? startsWith;");
            lines.push("    string? endsWith;");
        }

        lines.push("    boolean? isNull;");
        output.push(buildRecordTypeSource(filterTypeName, lines));
    }

    return output;
}

function generateCreateDataMapper(ModelDefinition model, string inputTypeName, string mapperName) returns string {
    string[] lines = [
        string `function ${mapperName}(${inputTypeName} payload) returns map<anydata> {`,
        "    map<anydata> data = {};"
    ];

    foreach ColumnDefinition column in model.columns {
        if !isCreateInputField(column) {
            continue;
        }

        string fieldName = emitFieldIdentifier(column.fieldName);
        string key = escapeStringLiteral(column.fieldName);
        boolean required = !column.nullable && !column.hasDefault;

        if required {
            lines.push(string `    data["${key}"] = payload.${fieldName};`);
        } else {
            lines.push(string `    if payload.${fieldName} is anydata {`);
            lines.push(string `        data["${key}"] = payload.${fieldName};`);
            lines.push("    }");
        }
    }

    lines.push("    return data;");
    lines.push("}");
    return joinWithSeparator(lines, "\n");
}

function generateUpdateDataMapper(ModelDefinition model, string inputTypeName, string mapperName) returns string {
    string[] lines = [
        string `function ${mapperName}(${inputTypeName} payload) returns map<anydata> {`,
        "    map<anydata> data = {};"
    ];

    foreach ColumnDefinition column in model.columns {
        if !isUpdateInputField(column) {
            continue;
        }

        string fieldName = emitFieldIdentifier(column.fieldName);
        string key = escapeStringLiteral(column.fieldName);
        lines.push(string `    if payload.${fieldName} is anydata {`);
        lines.push(string `        data["${key}"] = payload.${fieldName};`);
        lines.push("    }");
    }

    lines.push("    return data;");
    lines.push("}");
    return joinWithSeparator(lines, "\n");
}

function isCreateInputField(ColumnDefinition column) returns boolean {
    return !column.autoIncrement && !column.createdAt && !column.updatedAt;
}

function isUpdateInputField(ColumnDefinition column) returns boolean {
    return !column.autoIncrement && !column.createdAt && !column.updatedAt && !column.isId;
}

function isWhereOrderInputField(ColumnDefinition column) returns boolean {
    string normalizedType = stripTypeDecorators(column.ballerinaType);
    return isScalarInputType(normalizedType);
}

type FilterKind FILTER_KIND_INT|FILTER_KIND_NUMBER|FILTER_KIND_STRING|FILTER_KIND_BOOLEAN|FILTER_KIND_OTHER;

const FILTER_KIND_INT = "INT";
const FILTER_KIND_NUMBER = "NUMBER";
const FILTER_KIND_STRING = "STRING";
const FILTER_KIND_BOOLEAN = "BOOLEAN";
const FILTER_KIND_OTHER = "OTHER";

function resolveFilterKind(string ballerinaType) returns FilterKind {
    string value = ballerinaType.toLowerAscii();

    if value == "byte" || value == "int" {
        return FILTER_KIND_INT;
    }

    if value == "float" || value == "decimal" {
        return FILTER_KIND_NUMBER;
    }

    if value == "string" {
        return FILTER_KIND_STRING;
    }

    if value == "boolean" {
        return FILTER_KIND_BOOLEAN;
    }

    return FILTER_KIND_OTHER;
}

function isScalarInputType(string ballerinaType) returns boolean {
    string value = ballerinaType.trim();

    if value.endsWith("[]") {
        return false;
    }

    if value == "int" || value == "byte" || value == "float" || value == "decimal" ||
        value == "string" || value == "boolean" || value == "json" || value == "xml" ||
        value == "anydata" {
        return true;
    }

    if value.startsWith("time:") {
        return true;
    }

    int? firstPipe = value.indexOf("|");
    if firstPipe is int {
        int cursor = 0;
        while cursor <= value.length() {
            int? nextPipe = value.indexOf("|", cursor);
            int segmentEnd = nextPipe is int ? nextPipe : value.length();
            string trimmed = value.substring(cursor, segmentEnd).trim();
            if trimmed == "()" {
                if nextPipe is int {
                    cursor = nextPipe + 1;
                    continue;
                }
                break;
            }

            if !isScalarInputType(trimmed) {
                return false;
            }

            if nextPipe is int {
                cursor = nextPipe + 1;
                continue;
            }
            break;
        }
        return true;
    }

    return false;
}

function buildFilterTypeName(string modelName, string fieldName) returns string {
    return modelName + toPascalCase(fieldName) + "Filter";
}

function toPascalCase(string value) returns string {
    if value == "" {
        return "Field";
    }

    string normalized = value.trim();
    if normalized.startsWith("'") {
        normalized = normalized.substring(1);
    }

    string first = normalized.substring(0, 1).toUpperAscii();
    return first + normalized.substring(1);
}

function extractTypeName(string sourceCode) returns string {
    string prefix = "public type ";
    if !sourceCode.startsWith(prefix) {
        return "GeneratedType";
    }

    int startIndex = prefix.length();
    int? end = sourceCode.indexOf(" ", startIndex);
    if end is int {
        return sourceCode.substring(startIndex, end);
    }

    return "GeneratedType";
}

function escapeStringLiteral(string value) returns string {
    string out = "";
    int cursor = 0;
    while cursor < value.length() {
        string character = value.substring(cursor, cursor + 1);
        if character == "\\" {
            out += "\\\\";
        } else if character == "\"" {
            out += "\\\"";
        } else {
            out += character;
        }
        cursor += 1;
    }
    return out;
}

function buildRecordTypeSource(string typeName, string[] fieldLines) returns string {
    string fields = joinWithSeparator(fieldLines, "\n");
    if fields == "" {
        fields = "    anydata __placeholder?;";
    }

    return string `public type ${typeName} record {|\n${fields}\n|};`;
}
