# Parse normalized schema source values into ORM schema IR.

# Parse a full schema graph and validate cross-model constraints.
public function parseSchema(RawSchema rawSchema) returns SchemaGraph|SchemaError {
    map<ModelDefinition> models = {};
    RelationEdge[] relationEdges = [];

    foreach RawModel model in rawSchema.models {
        if models.hasKey(model.name) {
            return schemaError("DUPLICATE_MODEL", string `Duplicate model '${model.name}'.`, model.name);
        }

        ModelDefinition|SchemaError parsedModel = parseModel(model);
        if parsedModel is SchemaError {
            return parsedModel;
        }

        models[model.name] = parsedModel;

        foreach RelationDefinition relation in parsedModel.relations {
            relationEdges.push({
                fromModel: parsedModel.name,
                fromField: relation.fieldName,
                toModel: relation.targetModel,
                relationType: relation.relationType,
                references: relation.references,
                foreignKey: relation.foreignKey,
                joinTable: relation.joinTable
            });
        }
    }

    SchemaGraph graph = {
        models,
        relationEdges
    };

    SchemaError? validationError = validateSchemaGraph(graph);
    if validationError is SchemaError {
        return validationError;
    }

    return graph;
}

# Parse a single raw model into a model definition.
public function parseModel(RawModel rawModel) returns ModelDefinition|SchemaError {
    if rawModel.name.trim().length() == 0 {
        return schemaError("MODEL_NAME_REQUIRED", "Model name cannot be empty.");
    }

    string tableName = rawModel.entity.tableName ?: toDefaultTableName(rawModel.name);
    Engine engine = rawModel.entity.engine ?: MYSQL;

    ColumnDefinition[] columns = [];
    map<ColumnDefinition> columnsByField = {};
    RelationDefinition[] relations = [];

    foreach RawField rawField in rawModel.fields {
        if rawField.ignored {
            continue;
        }

        if rawField.name.trim().length() == 0 {
            return schemaError("FIELD_NAME_REQUIRED", "Field name cannot be empty.", rawModel.name);
        }

        RelationConfig? relationConfig = rawField.relation;
        if relationConfig is RelationConfig {
            RelationType? relationType = relationConfig.'type ?: relationConfig.relationType;
            if relationType is () {
                return schemaError(
                    "RELATION_TYPE_REQUIRED",
                    string `Relation field '${rawField.name}' must define relation type.`,
                    rawModel.name,
                    rawField.name
                );
            }

            RelationDefinition relation = {
                fieldName: rawField.name,
                targetModel: relationConfig.model ?: inferModelNameFromType(rawField.ballerinaType),
                relationType,
                references: relationConfig.references ?: [],
                foreignKey: relationConfig.foreignKey ?: [],
                joinTable: relationConfig.joinTable
            };
            relations.push(relation);
        }

        boolean hasColumnMetadata = rawField.column is ColumnConfig || rawField.id || rawField.autoIncrement || rawField.createdAt ||
            rawField.updatedAt;
        if relationConfig is RelationConfig && !hasColumnMetadata {
            continue;
        }

        ColumnConfig columnConfig = rawField.column ?: {};
        string columnName = columnConfig.name ?: toSnakeCase(rawField.name);

        boolean nullable = rawField.isOptional;
        if rawField.column is ColumnConfig {
            nullable = columnConfig.nullable;
        }

        anydata? defaultValue = columnConfig?.'default;
        boolean hasDefault = columnConfig.hasKey("default");

        if rawField.id {
            nullable = false;
        }

        if rawField.autoIncrement && !rawField.id {
            return schemaError(
                "AUTOINCREMENT_REQUIRES_ID",
                string `Field '${rawField.name}' uses auto-increment but is not an id field.`,
                rawModel.name,
                rawField.name
            );
        }

        if columnsByField.hasKey(rawField.name) {
            return schemaError(
                "DUPLICATE_FIELD",
                string `Duplicate field '${rawField.name}' in model '${rawModel.name}'.`,
                rawModel.name,
                rawField.name
            );
        }

        ColumnDefinition definition = {
            fieldName: rawField.name,
            columnName,
            ballerinaType: rawField.ballerinaType,
            dbType: columnConfig.dbType,
            length: columnConfig.length,
            nullable,
            unique: columnConfig.unique,
            isId: rawField.id,
            autoIncrement: rawField.autoIncrement,
            createdAt: rawField.createdAt,
            updatedAt: rawField.updatedAt,
            hasDefault,
            defaultValue
        };

        columns.push(definition);
        columnsByField[rawField.name] = definition;
    }

    IndexDefinition[] indexes = [];
    foreach IndexConfig indexConfig in rawModel.indexes {
        if indexConfig.columns.length() == 0 {
            return schemaError("INDEX_COLUMNS_REQUIRED", "Index must include at least one column.", rawModel.name);
        }

        string inferredName = underscoreJoin([
            tableName,
            underscoreJoin(indexConfig.columns),
            indexConfig.unique ? "uidx" : "idx"
        ]);
        string indexName = indexConfig.name ?: inferredName;

        indexes.push({
            name: indexName,
            columns: indexConfig.columns,
            unique: indexConfig.unique
        });
    }

    return {
        name: rawModel.name,
        tableName,
        schema: rawModel.entity.schema,
        engine,
        columns,
        columnsByField,
        indexes,
        relations
    };
}
