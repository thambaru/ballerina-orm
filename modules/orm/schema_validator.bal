# Validation functions for schema graph consistency checks.

# Validate model-level and cross-model constraints.
public function validateSchemaGraph(SchemaGraph graph) returns SchemaError? {
    map<string> usedTables = {};

    foreach var [modelName, model] in graph.models.entries() {
        if model.columns.length() == 0 {
            return schemaError("MODEL_HAS_NO_COLUMNS", string `Model '${modelName}' has no persisted columns.`, modelName);
        }

        boolean hasPrimaryKey = false;
        int createdAtCount = 0;
        int updatedAtCount = 0;
        foreach ColumnDefinition column in model.columns {
            if column.isId {
                hasPrimaryKey = true;
            }
            if column.createdAt {
                createdAtCount += 1;
            }
            if column.updatedAt {
                updatedAtCount += 1;
            }
        }

        if !hasPrimaryKey {
            return schemaError("PRIMARY_KEY_REQUIRED", string `Model '${modelName}' must define at least one @orm:Id field.`,
                modelName);
        }

        if createdAtCount > 1 {
            return schemaError("MULTIPLE_CREATED_AT", string `Model '${modelName}' has multiple created-at fields.`, modelName);
        }

        if updatedAtCount > 1 {
            return schemaError("MULTIPLE_UPDATED_AT", string `Model '${modelName}' has multiple updated-at fields.`, modelName);
        }

        string tableKey = model.tableName;
        if model.schema is string {
            string schemaName = <string>model.schema;
            tableKey = string `${schemaName}.${model.tableName}`;
        }
        if usedTables.hasKey(tableKey) {
            string otherModel = usedTables[tableKey] ?: "";
            return schemaError(
                "DUPLICATE_TABLE_NAME",
                string `Models '${otherModel}' and '${modelName}' resolve to the same table '${tableKey}'.`,
                modelName
            );
        }
        usedTables[tableKey] = modelName;

        foreach IndexDefinition indexDefinition in model.indexes {
            foreach string indexedField in indexDefinition.columns {
                if !model.columnsByField.hasKey(indexedField) {
                    return schemaError(
                        "INDEX_FIELD_NOT_FOUND",
                        string `Index '${indexDefinition.name}' references unknown field '${indexedField}'.`,
                        modelName,
                        indexedField
                    );
                }
            }
        }

        foreach RelationDefinition relation in model.relations {
            if relation.targetModel.trim().length() == 0 {
                return schemaError(
                    "RELATION_TARGET_REQUIRED",
                    string `Relation field '${relation.fieldName}' has no target model.`,
                    modelName,
                    relation.fieldName
                );
            }

            if !graph.models.hasKey(relation.targetModel) {
                return schemaError(
                    "RELATION_TARGET_NOT_FOUND",
                    string `Relation field '${relation.fieldName}' points to unknown model '${relation.targetModel}'.`,
                    modelName,
                    relation.fieldName
                );
            }

            ModelDefinition targetModel = <ModelDefinition>graph.models[relation.targetModel];

            foreach string referenceField in relation.references {
                if !targetModel.columnsByField.hasKey(referenceField) {
                    return schemaError(
                        "RELATION_REFERENCE_NOT_FOUND",
                        string `Relation '${relation.fieldName}' references unknown field '${referenceField}' in '${targetModel.name}'.`,
                        modelName,
                        relation.fieldName
                    );
                }
            }

            foreach string fkField in relation.foreignKey {
                if !model.columnsByField.hasKey(fkField) {
                    return schemaError(
                        "RELATION_FOREIGN_KEY_NOT_FOUND",
                        string `Relation '${relation.fieldName}' uses unknown foreign-key field '${fkField}'.`,
                        modelName,
                        relation.fieldName
                    );
                }
            }

            if relation.relationType == MANY_TO_MANY {
                string? joinTable = relation.joinTable;
                if joinTable is () || joinTable.trim().length() == 0 {
                    return schemaError(
                        "JOIN_TABLE_REQUIRED",
                        string `Many-to-many relation '${relation.fieldName}' must define a join table.`,
                        modelName,
                        relation.fieldName
                    );
                }
            }
        }
    }

    return;
}
