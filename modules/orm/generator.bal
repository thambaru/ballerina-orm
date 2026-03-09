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
            content: string `public type ${whereTypeName} map<anydata>;`
        },
        {
            name: orderByTypeName,
            content: string `public type ${orderByTypeName} map<SortDirection>;`
        },
        {
            name: includeTypeName,
            content: generateIncludeType(model, includeTypeName)
        }
    ];

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
            content: string `public function ${modelToken}Create(${createTypeName} payload) returns QueryPlan {\n    return fromModel("${model.name}").create(payload);\n}`
        },
        {
            name: modelToken + "Update",
            content: string `public function ${modelToken}Update(${whereTypeName} whereInput, ${updateTypeName} payload) returns QueryPlan {\n    return fromModel("${model.name}").'where(whereInput).update(payload);\n}`
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

function isCreateInputField(ColumnDefinition column) returns boolean {
    return !column.autoIncrement && !column.createdAt && !column.updatedAt;
}

function isUpdateInputField(ColumnDefinition column) returns boolean {
    return !column.autoIncrement && !column.createdAt && !column.updatedAt && !column.isId;
}

function buildRecordTypeSource(string typeName, string[] fieldLines) returns string {
    string fields = joinWithSeparator(fieldLines, "\n");
    if fields == "" {
        fields = "    anydata __placeholder?;";
    }

    return string `public type ${typeName} record {|\n${fields}\n|};`;
}
