# Compiler plugin scaffolding for schema analysis and model-aware code generation.

# Plugin diagnostic severity values.
public const PLUGIN_ERROR = "ERROR";
public const PLUGIN_WARNING = "WARNING";

# Severity type for plugin diagnostics.
public type PluginSeverity PLUGIN_ERROR|PLUGIN_WARNING;

# Compiler-plugin diagnostic payload.
public type PluginDiagnostic record {| 
    string code;
    string message;
    PluginSeverity severity;
    string? model = ();
    string? fieldName = ();
|};

# Generated source payload for a type definition.
public type GeneratedTypeSource record {| 
    string name;
    string content;
|};

# Generated source payload for a CRUD wrapper.
public type GeneratedCrudSource record {| 
    string name;
    string content;
|};

# Generated artifacts for a single ORM model.
public type ModelGeneration record {| 
    string model;
    GeneratedTypeSource[] generatedTypes;
    GeneratedCrudSource[] generatedCrud;
|};

# Output returned by the compiler-plugin execution pipeline.
public type PluginExecution record {| 
    SchemaGraph schemaGraph;
    map<ModelGeneration> modelArtifacts;
    PluginDiagnostic[] diagnostics = [];
|};

# Orchestrates schema scan, analysis, and code generation.
public class CompilerPlugin {
    public function init() {
    }

    # Scan schema payload that was derived from `@orm:Entity` records.
    public function scan(RawSchema rawSchema) returns RawSchema {
        return rawSchema;
    }

    # Execute plugin pipeline and return generated outputs and diagnostics.
    public function run(RawSchema rawSchema) returns PluginExecution|SchemaError {
        RawSchema scannedSchema = self.scan(rawSchema);
        SchemaGraph schemaGraph = check parseSchema(scannedSchema);
        PluginDiagnostic[] diagnostics = analyzeSchemaForPlugin(schemaGraph);
        map<ModelGeneration> modelArtifacts = generateModelArtifacts(schemaGraph);

        return {
            schemaGraph,
            modelArtifacts,
            diagnostics
        };
    }
}

# Convenience API that runs the default plugin implementation.
public function executeCompilerPlugin(RawSchema rawSchema) returns PluginExecution|SchemaError {
    CompilerPlugin plugin = new;
    return plugin.run(rawSchema);
}

# Returns `true` if the plugin reported at least one error diagnostic.
public function hasPluginErrors(PluginExecution execution) returns boolean {
    foreach PluginDiagnostic diagnostic in execution.diagnostics {
        if diagnostic.severity == PLUGIN_ERROR {
            return true;
        }
    }
    return false;
}

# Build an error diagnostic value.
function pluginError(string code, string message, string? model = (), string? fieldName = ()) returns PluginDiagnostic {
    return {
        code,
        message,
        severity: PLUGIN_ERROR,
        model,
        fieldName
    };
}

# Build a warning diagnostic value.
function pluginWarning(string code, string message, string? model = (), string? fieldName = ()) returns PluginDiagnostic {
    return {
        code,
        message,
        severity: PLUGIN_WARNING,
        model,
        fieldName
    };
}
