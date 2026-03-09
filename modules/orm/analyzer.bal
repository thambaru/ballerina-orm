# Compile-time validation helpers for ORM schema plugin diagnostics.

# Analyze schema relationships and return plugin diagnostics.
public function analyzeSchemaForPlugin(SchemaGraph graph) returns PluginDiagnostic[] {
    PluginDiagnostic[] diagnostics = [];

    foreach var [modelName, model] in graph.models.entries() {
        map<boolean> indexedFields = indexedFieldLookup(model);

        foreach RelationDefinition relation in model.relations {
            int fkCount = relation.foreignKey.length();
            int refCount = relation.references.length();

            if fkCount == 0 && refCount == 0 {
                continue;
            }

            if fkCount == 0 || refCount == 0 {
                diagnostics.push(pluginError(
                    "PLUGIN_RELATION_KEYS_INCOMPLETE",
                    string `Relation '${relation.fieldName}' in '${modelName}' must define both references and foreign keys.`,
                    modelName,
                    relation.fieldName
                ));
                continue;
            }

            if fkCount != refCount {
                diagnostics.push(pluginError(
                    "PLUGIN_RELATION_KEY_COUNT_MISMATCH",
                    string `Relation '${relation.fieldName}' in '${modelName}' has ${fkCount.toString()} foreign keys and ${refCount.toString()} references.`,
                    modelName,
                    relation.fieldName
                ));
                continue;
            }

            ModelDefinition? maybeTarget = graph.models.get(relation.targetModel);
            if maybeTarget !is ModelDefinition {
                continue;
            }
            ModelDefinition targetModel = maybeTarget;

            int index = 0;
            while index < fkCount {
                string fkField = relation.foreignKey[index];
                string referenceField = relation.references[index];

                ColumnDefinition? maybeFkColumn = model.columnsByField.get(fkField);
                ColumnDefinition? maybeReferenceColumn = targetModel.columnsByField.get(referenceField);

                if maybeFkColumn is ColumnDefinition && maybeReferenceColumn is ColumnDefinition {
                    if !areRelationTypesCompatible(maybeFkColumn.ballerinaType, maybeReferenceColumn.ballerinaType) {
                        diagnostics.push(pluginError(
                            "PLUGIN_RELATION_TYPE_MISMATCH",
                            string `Relation '${relation.fieldName}' maps '${modelName}.${fkField}' (${maybeFkColumn.ballerinaType}) to '${targetModel.name}.${referenceField}' (${maybeReferenceColumn.ballerinaType}) with incompatible types.`,
                            modelName,
                            relation.fieldName
                        ));
                    }
                }

                if !indexedFields.hasKey(fkField) {
                    diagnostics.push(pluginWarning(
                        "PLUGIN_RELATION_FOREIGN_KEY_NOT_INDEXED",
                        string `Foreign key '${modelName}.${fkField}' used by relation '${relation.fieldName}' has no supporting index.`,
                        modelName,
                        relation.fieldName
                    ));
                }

                index += 1;
            }
        }
    }

    return diagnostics;
}

function indexedFieldLookup(ModelDefinition model) returns map<boolean> {
    map<boolean> indexed = {};

    foreach ColumnDefinition column in model.columns {
        if column.isId {
            indexed[column.fieldName] = true;
        }
    }

    foreach IndexDefinition indexDefinition in model.indexes {
        foreach string fieldName in indexDefinition.columns {
            indexed[fieldName] = true;
        }
    }

    return indexed;
}
