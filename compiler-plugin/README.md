# Ballerina ORM Compiler Plugin

This is the **Java-based compiler plugin** for the `thambaru/bal_orm` package. It integrates with the Ballerina build toolchain to perform compile-time schema analysis and code generation for ORM entities.

## Architecture

- **OrmCompilerPlugin** — Plugin entry point registered via `ServiceLoader`
- **OrmCodeAnalyzer** — Scans `@orm:Entity` record types and validates schema consistency
- **OrmCodeGenerator** — Emits typed input/output records and CRUD wrapper functions per model

The plugin delegates to the Ballerina `orm` module's runtime APIs for parsing, analysis, and generation logic.

## Build

```bash
./gradlew build
```

This produces a JAR at `build/libs/compiler-plugin-0.1.0.jar` containing:
- Compiled plugin classes
- `META-INF/services/io.ballerina.projects.plugins.CompilerPlugin` (ServiceLoader registration)

## Integration

1. **Package the plugin JAR** with the Ballerina package by adding it to `Ballerina.toml`:
   ```toml
   [[platform.java21.dependency]]
   path = "compiler-plugin/build/libs/compiler-plugin-0.1.0.jar"
   ```

2. **Alternatively**, publish the plugin JAR to Maven Central or a local repository and declare it as a dependency.

3. The Ballerina compiler auto-loads the plugin during `bal build` and runs:
   - **Analysis**: scans entities, validates relations, checks FK types
   - **Generation**: emits typed sources into `target/generated/`

## Implementation Status

✅ **Scaffold**: Java plugin classes + ServiceLoader registration  
⬜ **Entity scanning**: reflection-based annotation reader  
⬜ **Schema IR builder**: construct `RawSchema` from AST nodes  
⬜ **Diagnostic reporting**: convert `PluginDiagnostic` → `io.ballerina.tools.diagnostics.Diagnostic`  
⬜ **Source file emission**: write generated `.bal` files via `SourceGeneratorContext`  
⬜ **Build integration**: package JAR with Ballerina distribution  

## Testing

Unit tests can mock the `CodeAnalysisContext` and `CodeGeneratorContext` to verify analyzer/generator behavior without a full build pipeline.

Integration tests should:
1. Build a sample Ballerina project with `@orm:Entity` records
2. Verify diagnostics are reported correctly
3. Confirm generated sources appear in `target/generated/`
4. Compile and run generated code

## Next Steps

1. Implement entity scanning logic in `OrmCodeAnalyzer`
2. Build `RawSchema` from Ballerina AST nodes
3. Call `orm:parseSchema` + `orm:analyzeSchemaForPlugin` from Java
4. Implement source file emission in `OrmCodeGenerator`
5. Package and test end-to-end
