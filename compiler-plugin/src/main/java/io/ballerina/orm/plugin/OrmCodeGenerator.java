package io.ballerina.orm.plugin;

import io.ballerina.projects.plugins.CodeGenerator;
import io.ballerina.projects.plugins.CodeGeneratorContext;

/**
 * Generates typed input records and CRUD wrapper functions at compile time.
 *
 * <p>This generator creates model-specific types ({@code UserCreateInput},
 * {@code UserWhereInput}, etc.) and CRUD helper functions (e.g., {@code userFindMany}).
 * The generation logic delegates to the {@code orm} module's runtime generator APIs.
 */
public class OrmCodeGenerator extends CodeGenerator {

    @Override
    public void init(CodeGeneratorContext context) {
        // TODO: Register source generation task
        // TODO: Build SchemaGraph from scanned entities
        // TODO: Call orm:generateModelArtifacts
        // TODO: Write generated source files via context.addSourceFile(...)
    }
}
