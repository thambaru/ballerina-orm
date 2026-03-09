import ballerina/test;

@test:Config {}
function testParseSchemaWithDefaults() {
    RawSchema schemaSource = {
        models: [
            {
                name: "User",
                entity: {
                    tableName: "users",
                    engine: MYSQL
                },
                fields: [
                    {
                        name: "id",
                        ballerinaType: "int",
                        id: true,
                        autoIncrement: true
                    },
                    {
                        name: "email",
                        ballerinaType: "string",
                        column: {
                            nullable: false,
                            unique: true
                        }
                    },
                    {
                        name: "createdAt",
                        ballerinaType: "time:Utc",
                        createdAt: true
                    }
                ],
                indexes: [
                    {
                        columns: ["email"],
                        unique: true
                    }
                ]
            }
        ]
    };

    SchemaGraph result = checkpanic parseSchema(schemaSource);

    test:assertTrue(result.models.hasKey("User"));
    ModelDefinition? maybeUserModel = result.models.get("User");
    test:assertTrue(maybeUserModel is ModelDefinition);
    ModelDefinition userModel = <ModelDefinition>maybeUserModel;
    test:assertEquals(userModel.tableName, "users");
    test:assertEquals(userModel.engine, MYSQL);
    test:assertEquals(userModel.columns.length(), 3);
    test:assertEquals(userModel.indexes[0].unique, true);
    ColumnDefinition? maybeIdColumn = userModel.columnsByField.get("id");
    test:assertTrue(maybeIdColumn is ColumnDefinition);
    ColumnDefinition idColumn = <ColumnDefinition>maybeIdColumn;
    test:assertEquals(idColumn.autoIncrement, true);
}

@test:Config {}
function testRelationValidationFailure() {
    RawSchema schemaSource = {
        models: [
            {
                name: "Post",
                fields: [
                    {
                        name: "id",
                        ballerinaType: "int",
                        id: true
                    },
                    {
                        name: "author",
                        ballerinaType: "User",
                        relation: {
                            relationType: ONE_TO_ONE,
                            references: ["id"],
                            foreignKey: ["authorId"]
                        }
                    },
                    {
                        name: "authorId",
                        ballerinaType: "int"
                    }
                ]
            }
        ]
    };

    SchemaGraph|SchemaError result = parseSchema(schemaSource);
    test:assertTrue(result is SchemaError);
    if result is SchemaError {
        SchemaIssue issue = result.detail();
        test:assertEquals(issue.code, "RELATION_TARGET_NOT_FOUND");
    }
}

@test:Config {}
function testIndexValidationFailure() {
    RawSchema schemaSource = {
        models: [
            {
                name: "Category",
                fields: [
                    {
                        name: "id",
                        ballerinaType: "int",
                        id: true
                    }
                ],
                indexes: [
                    {
                        columns: ["slug"]
                    }
                ]
            }
        ]
    };

    SchemaGraph|SchemaError result = parseSchema(schemaSource);
    test:assertTrue(result is SchemaError);
    if result is SchemaError {
        SchemaIssue issue = result.detail();
        test:assertEquals(issue.code, "INDEX_FIELD_NOT_FOUND");
    }
}
