package io.ballerina.orm.plugin;

import io.ballerina.projects.plugins.CompilerPlugin;
import io.ballerina.projects.plugins.CompilerPluginContext;

/**
 * Main entry point for the ORM compiler plugin.
 *
 * <p>This plugin is loaded by the Ballerina compiler via {@link java.util.ServiceLoader}
 * when building packages that depend on {@code thambaru/bal_orm}. It orchestrates
 * schema analysis and code generation based on {@code @orm:Entity} annotations.
 */
public class OrmCompilerPlugin extends CompilerPlugin {

    @Override
    public void init(CompilerPluginContext context) {
        context.addCodeAnalyzer(new OrmCodeAnalyzer());
        context.addCodeGenerator(new OrmCodeGenerator());
    }
}
