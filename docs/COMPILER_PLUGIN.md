# ORM Compiler Plugin

## Overview

This directory defines the **library-level compiler plugin API** exposed by the `orm` module. The actual **compiler plugin implementation** is a separate Java-based Gradle project that depends on this package.

---

## Current Implementation

The `orm` module includes:  
- **Plugin execution pipeline** (`modules/orm/plugin.bal`) — in-memory plugin orchestration for testing and programmatic use  
- **Analyzer** (`modules/orm/analyzer.bal`) — relation validation, FK/reference type-checking, index coverage warnings  
- **Generator** (`modules/orm/generator.bal`) — per-model typed input/output sources, CRUD wrapper skeletons  
- **Type mapper** (`modules/orm/type_mapper.bal`) — Ballerina type compatibility checks for relation keys  

These APIs allow **library consumers** to execute the plugin pipeline programmatically:
```ballerina
import thambaru/bal_orm.orm;

RawSchema schema = {
    defaultEngine: orm:POSTGRESQL,
    models: [/* ...normalized model metadata... */]
};
orm:PluginExecution execution = check orm:executeCompilerPlugin(schema);

// execution.diagnostics => warnings/errors
// execution.modelArtifacts => generated type/CRUD sources per model
```

Today, `RawSchema` is still a normalized input model. Automatic extraction from `@orm:Entity` records is expected from compiler tooling; the library-level API does not yet reflect annotations at runtime on its own.

---

## Actual Compiler Plugin (Java-based)

Ballerina compiler plugins must be implemented in **Java** using the `io.ballerina.projects.plugins` API. To integrate Phase 4 into the **Ballerina build lifecycle**, create a separate Gradle project:

### Structure
```
orm-compiler-plugin/
├── build.gradle.kts
├── src/main/java/
│   └── io/ballerina/orm/plugin/
│       ├── OrmCompilerPlugin.java
│       ├── OrmCodeAnalyzer.java
│       └── OrmCodeGenerator.java
└── src/main/resources/
    └── META-INF/services/
        └── io.ballerina.projects.plugins.CompilerPlugin
```

### Java Implementation

**OrmCompilerPlugin.java**
```java
package io.ballerina.orm.plugin;

import io.ballerina.projects.plugins.*;

public class OrmCompilerPlugin extends CompilerPlugin {
    @Override
    public void init(CompilerPluginContext ctx) {
        ctx.addCodeAnalyzer(new OrmCodeAnalyzer());
        ctx.addCodeGenerator(new OrmCodeGenerator());
    }
}
```

**SERVICE REGISTRATION** (`META-INF/services/io.ballerina.projects.plugins.CompilerPlugin`):
```
io.ballerina.orm.plugin.OrmCompilerPlugin
```

**Analyzer**: scans `@Entity` records via `SyntaxNodeAnalysisContext`, calls the `orm` module's parser/validator, reports diagnostics via `ctx.reportDiagnostic(...)`.

**Generator**: invokes the `orm` module's `generateModelArtifacts(...)`, writes output via `SourceGeneratorContext.addSourceFile(...)`.

### Build & Package

1. **Compile** the Java plugin JAR with dependencies on `ballerina-lang`, `ballerina-tools-api`.  
2. **Bundle** the plugin JAR into the Ballerina package's `platform-libs` directory or distribute as a library JAR.  
3. Update `Ballerina.toml` with `[[platform.java21.dependency]]` entries pointing to the plugin artifact.

### Integration

Once packaged correctly, the Ballerina build automatically loads the plugin via `ServiceLoader`, scans entities at compile time, and emits generated sources into `target/generated`.

---

## Next Steps

1. **Scaffold Java plugin** in a sibling Gradle project (`orm-compiler-plugin/`)  
2. **Wire lifecycle hooks** to call the `orm` module's parsing/analysis/generation APIs  
3. **Package & distribute** the plugin JAR alongside the `bal_orm` package  
4. **Test end-to-end** by placing the plugin in a test project's dependencies and verifying it runs during `bal build`.

---

## Verification

✅ **Plugin API & IR** implemented in `modules/orm/`  
✅ **Analyzer** checks relation types, FKs, and indexing  
✅ **Generator** emits typed inputs, where/order-by types, include configs, CRUD wrappers  
✅ **Library-level execution** via `orm:executeCompilerPlugin(...)` tested  
⬜ **Java compiler plugin** scaffolded  
⬜ **Build integration** via `ServiceLoader` + `CompilerPlugin.toml`  
