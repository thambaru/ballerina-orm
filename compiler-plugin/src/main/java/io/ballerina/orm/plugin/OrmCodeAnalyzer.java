package io.ballerina.orm.plugin;

import io.ballerina.projects.plugins.CodeAnalysisContext;
import io.ballerina.projects.plugins.CodeAnalyzer;

/**
 * Analyzes {@code @orm:Entity} annotated record types at compile time.
 *
 * <p>This analyzer validates schema consistency (primary keys, relation types, etc.)
 * and reports diagnostics. The validation logic delegates to the Ballerina {@code orm}
 * module's runtime APIs.
 */
public class OrmCodeAnalyzer extends CodeAnalyzer {

    @Override
    public void init(CodeAnalysisContext context) {
        // TODO: Register syntax node analysis task for TYPE_DEFINITION nodes
        // TODO: Scan for @orm:Entity annotations
        // TODO: Build RawSchema from annotations
        // TODO: Call orm:parseSchema + orm:analyzeSchemaForPlugin
        // TODO: Report diagnostics via context.reportDiagnostic(...)
    }
}
