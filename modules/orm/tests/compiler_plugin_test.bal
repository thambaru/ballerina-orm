import ballerina/test;

@test:Config {}
function testCompilerPluginGeneratesTypedArtifacts() {
    RawSchema schemaSource = {
        models: [
            {
                name: "User",
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
                        name: "name",
                        ballerinaType: "string",
                        column: {
                            nullable: true
                        }
                    },
                    {
                        name: "posts",
                        ballerinaType: "Post[]",
                        relation: {
                            'type: ONE_TO_MANY,
                            model: "Post"
                        }
                    },
                    {
                        name: "createdAt",
                        ballerinaType: "time:Utc",
                        createdAt: true
                    },
                    {
                        name: "updatedAt",
                        ballerinaType: "time:Utc",
                        updatedAt: true
                    }
                ]
            },
            {
                name: "Post",
                fields: [
                    {
                        name: "id",
                        ballerinaType: "int",
                        id: true,
                        autoIncrement: true
                    },
                    {
                        name: "title",
                        ballerinaType: "string",
                        column: {
                            nullable: false
                        }
                    },
                    {
                        name: "authorId",
                        ballerinaType: "int"
                    },
                    {
                        name: "author",
                        ballerinaType: "User",
                        relation: {
                            'type: ONE_TO_ONE,
                            model: "User",
                            references: ["id"],
                            foreignKey: ["authorId"]
                        }
                    }
                ],
                indexes: [
                    {
                        columns: ["authorId"]
                    }
                ]
            }
        ]
    };

    PluginExecution execution = checkpanic executeCompilerPlugin(schemaSource);

    test:assertEquals(hasPluginErrors(execution), false);
    test:assertTrue(execution.modelArtifacts.hasKey("User"));
    test:assertTrue(execution.modelArtifacts.hasKey("Post"));

    ModelGeneration? maybeUserArtifacts = execution.modelArtifacts.get("User");
    test:assertTrue(maybeUserArtifacts is ModelGeneration);
    ModelGeneration userArtifacts = <ModelGeneration>maybeUserArtifacts;

    string createSource = getTypeSource(userArtifacts.generatedTypes, "UserCreateInput");
    string updateSource = getTypeSource(userArtifacts.generatedTypes, "UserUpdateInput");
    string includeSource = getTypeSource(userArtifacts.generatedTypes, "UserInclude");

    test:assertFalse(createSource == "");
    test:assertTrue(contains(createSource, "string email;"));
    test:assertTrue(contains(createSource, "string name?;"));
    test:assertTrue(contains(updateSource, "string email?;"));
    test:assertTrue(contains(includeSource, "boolean posts?;"));

    test:assertEquals(userArtifacts.generatedCrud.length(), 5);
}

@test:Config {}
function testCompilerPluginDetectsRelationTypeMismatch() {
    RawSchema schemaSource = {
        models: [
            {
                name: "User",
                fields: [
                    {
                        name: "id",
                        ballerinaType: "int",
                        id: true
                    }
                ]
            },
            {
                name: "Post",
                fields: [
                    {
                        name: "id",
                        ballerinaType: "int",
                        id: true
                    },
                    {
                        name: "authorId",
                        ballerinaType: "string"
                    },
                    {
                        name: "author",
                        ballerinaType: "User",
                        relation: {
                            'type: ONE_TO_ONE,
                            model: "User",
                            references: ["id"],
                            foreignKey: ["authorId"]
                        }
                    }
                ],
                indexes: [
                    {
                        columns: ["authorId"]
                    }
                ]
            }
        ]
    };

    PluginExecution execution = checkpanic executeCompilerPlugin(schemaSource);

    PluginDiagnostic? mismatch = findDiagnostic(execution.diagnostics, "PLUGIN_RELATION_TYPE_MISMATCH");
    test:assertTrue(mismatch is PluginDiagnostic);
    if mismatch is PluginDiagnostic {
        test:assertEquals(mismatch.severity, PLUGIN_ERROR);
    }
    test:assertEquals(hasPluginErrors(execution), true);
}

@test:Config {}
function testCompilerPluginWarnsOnMissingForeignKeyIndexes() {
    RawSchema schemaSource = {
        models: [
            {
                name: "User",
                fields: [
                    {
                        name: "id",
                        ballerinaType: "int",
                        id: true
                    }
                ]
            },
            {
                name: "Post",
                fields: [
                    {
                        name: "id",
                        ballerinaType: "int",
                        id: true
                    },
                    {
                        name: "authorId",
                        ballerinaType: "int"
                    },
                    {
                        name: "author",
                        ballerinaType: "User",
                        relation: {
                            'type: ONE_TO_ONE,
                            model: "User",
                            references: ["id"],
                            foreignKey: ["authorId"]
                        }
                    }
                ]
            }
        ]
    };

    PluginExecution execution = checkpanic executeCompilerPlugin(schemaSource);

    PluginDiagnostic? warning = findDiagnostic(execution.diagnostics, "PLUGIN_RELATION_FOREIGN_KEY_NOT_INDEXED");
    test:assertTrue(warning is PluginDiagnostic);
    if warning is PluginDiagnostic {
        test:assertEquals(warning.severity, PLUGIN_WARNING);
    }
}

function getTypeSource(GeneratedTypeSource[] generatedTypes, string typeName) returns string {
    foreach GeneratedTypeSource generatedType in generatedTypes {
        if generatedType.name == typeName {
            return generatedType.content;
        }
    }
    return "";
}

function findDiagnostic(PluginDiagnostic[] diagnostics, string code) returns PluginDiagnostic? {
    foreach PluginDiagnostic diagnostic in diagnostics {
        if diagnostic.code == code {
            return diagnostic;
        }
    }
    return;
}

function contains(string value, string fragment) returns boolean {
    int? position = value.indexOf(fragment);
    return position is int;
}
