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
                            'type: ONE_TO_ONE,
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

@test:Config {}
function testParseSchemaUsesSchemaDefaultEngine() {
    RawSchema schemaSource = {
        defaultEngine: POSTGRESQL,
        models: [
            {
                name: "AuditLog",
                fields: [
                    {
                        name: "id",
                        ballerinaType: "int",
                        id: true
                    }
                ]
            }
        ]
    };

    SchemaGraph result = checkpanic parseSchema(schemaSource);

    ModelDefinition? maybeAuditLog = result.models.get("AuditLog");
    test:assertTrue(maybeAuditLog is ModelDefinition);
    ModelDefinition auditLog = <ModelDefinition>maybeAuditLog;
    test:assertTrue(auditLog.engine is string);
    test:assertEquals(auditLog.engine, POSTGRESQL);
}

@test:Config {}
function testParseSchemaLeavesEngineUnsetWithoutDefault() {
    RawSchema schemaSource = {
        models: [
            {
                name: "Session",
                fields: [
                    {
                        name: "id",
                        ballerinaType: "int",
                        id: true
                    }
                ]
            }
        ]
    };

    SchemaGraph result = checkpanic parseSchema(schemaSource);

    ModelDefinition? maybeSession = result.models.get("Session");
    test:assertTrue(maybeSession is ModelDefinition);
    ModelDefinition sessionModel = <ModelDefinition>maybeSession;
    test:assertTrue(sessionModel.engine is ());
}

@test:Config {}
function testDefaultTableNamePluralization() {
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
                ]
            },
            {
                name: "Address",
                fields: [
                    {
                        name: "id",
                        ballerinaType: "int",
                        id: true
                    }
                ]
            }
        ]
    };

    SchemaGraph result = checkpanic parseSchema(schemaSource);

    ModelDefinition? maybeCategory = result.models.get("Category");
    test:assertTrue(maybeCategory is ModelDefinition);
    test:assertEquals((<ModelDefinition>maybeCategory).tableName, "categories");

    ModelDefinition? maybeAddress = result.models.get("Address");
    test:assertTrue(maybeAddress is ModelDefinition);
    test:assertEquals((<ModelDefinition>maybeAddress).tableName, "addresses");
}
